// Streaming ZIP reader.
//
// The ZET static feed ships `stop_times.txt` at ~112 MB uncompressed. Reading
// it through `archive` (or any whole-file API) allocates the full text plus a
// Dart String — hundreds of MB and multi-second GC pauses. This reader walks
// the central directory once and inflates each entry as a chunk stream, so the
// parser can consume it line by line with a constant memory budget.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class ZetZipException implements Exception {
  final String message;
  const ZetZipException(this.message);
  @override
  String toString() => 'ZetZipException: $message';
}

class ZipEntryInfo {
  final String name;
  final int method; // 0 = stored, 8 = raw deflate
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;

  const ZipEntryInfo({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
  });
}

class ZipSource {
  static const int _cdSig = 0x02014B50;
  static const int _lhSig = 0x04034B50;

  final RandomAccessFile _raf;
  final List<ZipEntryInfo> entries;

  ZipSource._(this._raf, this.entries);

  static Future<ZipSource> open(String path) async {
    final raf = await File(path).open();
    try {
      final length = await raf.length();
      if (length < 22) throw const ZetZipException('file too small');

      // End of central directory: signature + 18 bytes + comment.
      final tailLen = math.min(length, 66 * 1024);
      final tailStart = length - tailLen;
      await raf.setPosition(tailStart);
      final tail = await raf.read(tailLen);

      var eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (tail[i] == 0x50 &&
            tail[i + 1] == 0x4B &&
            tail[i + 2] == 0x05 &&
            tail[i + 3] == 0x06) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) throw const ZetZipException('EOCD not found');

      final endian = Endian.little;
      final bd = ByteData.sublistView(tail);
      final totalEntries = bd.getUint16(eocd + 10, endian);
      final cdSize = bd.getUint32(eocd + 12, endian);
      final cdOffset = bd.getUint32(eocd + 16, endian);

      if (cdOffset + cdSize > length) {
        throw const ZetZipException('central directory out of range');
      }

      await raf.setPosition(cdOffset);
      final cd = await raf.read(cdSize);
      final cdData = ByteData.sublistView(cd);

      final entries = <ZipEntryInfo>[];
      var p = 0;
      for (var i = 0; i < totalEntries; i++) {
        if (p + 46 > cd.length) break;
        if (cdData.getUint32(p, endian) != _cdSig) break;
        final method = cdData.getUint16(p + 10, endian);
        final compSize = cdData.getUint32(p + 20, endian);
        final uncompSize = cdData.getUint32(p + 24, endian);
        final nameLen = cdData.getUint16(p + 28, endian);
        final extraLen = cdData.getUint16(p + 30, endian);
        final commentLen = cdData.getUint16(p + 32, endian);
        final localOffset = cdData.getUint32(p + 42, endian);
        final name = String.fromCharCodes(cd, p + 46, p + 46 + nameLen);
        entries.add(ZipEntryInfo(
          name: name,
          method: method,
          compressedSize: compSize,
          uncompressedSize: uncompSize,
          localHeaderOffset: localOffset,
        ));
        p += 46 + nameLen + extraLen + commentLen;
      }

      if (entries.isEmpty) throw const ZetZipException('no entries');
      return ZipSource._(raf, entries);
    } catch (_) {
      await raf.close();
      rethrow;
    }
  }

  ZipEntryInfo? entry(String name) {
    final target = name.toLowerCase();
    for (final e in entries) {
      final base = e.name.split('/').last.toLowerCase();
      if (base == target) return e;
    }
    return null;
  }

  /// Inflates [entry] in chunks of [chunkSize] bytes.
  Stream<List<int>> stream(ZipEntryInfo entry, {int chunkSize = 256 * 1024}) async* {
    if (entry.compressedSize <= 0) {
      throw ZetZipException('entry ${entry.name} has no size (zip64?)');
    }
    await _raf.setPosition(entry.localHeaderOffset);
    final header = await _raf.read(30);
    if (header.length < 30) {
      throw ZetZipException('bad local header for ${entry.name}');
    }
    final hb = ByteData.sublistView(header);
    if (hb.getUint32(0, Endian.little) != _lhSig) {
      throw ZetZipException('bad local signature for ${entry.name}');
    }
    final nameLen = hb.getUint16(26, Endian.little);
    final extraLen = hb.getUint16(28, Endian.little);
    await _raf.setPosition(
        entry.localHeaderOffset + 30 + nameLen + extraLen);

    if (entry.method == 0) {
      var remaining = entry.compressedSize;
      while (remaining > 0) {
        final data = await _raf.read(math.min(chunkSize, remaining));
        if (data.isEmpty) break;
        remaining -= data.length;
        yield data;
      }
      return;
    }

    if (entry.method != 8) {
      throw ZetZipException(
          'unsupported compression ${entry.method} for ${entry.name}');
    }

    final filter = RawZLibFilter.inflateFilter(raw: true);
    var remaining = entry.compressedSize;
    while (remaining > 0) {
      final data = await _raf.read(math.min(chunkSize, remaining));
      if (data.isEmpty) break;
      remaining -= data.length;
      filter.process(data, 0, data.length);
      // `processed` must be drained completely before the next `process` call.
      while (true) {
        final out = filter.processed(flush: remaining == 0);
        if (out == null || out.isEmpty) break;
        yield out;
      }
    }
    while (true) {
      final tail = filter.processed(flush: true, end: true);
      if (tail == null || tail.isEmpty) break;
      yield tail;
    }
  }

  Future<Uint8List> readAll(ZipEntryInfo entry) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream(entry)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> close() => _raf.close();
}

/// Splits a byte stream into lines without decoding to [String].
///
/// The callback receives the shared buffer plus a start/end range. The range is
/// only valid for the duration of the call — callers must copy anything they
/// want to keep.
class ByteLineSplitter {
  final void Function(Uint8List buffer, int start, int end) onLine;

  Uint8List _buf;
  int _len = 0;
  static const int _initial = 1 << 16;

  ByteLineSplitter(this.onLine, {int initialCapacity = _initial})
      : _buf = Uint8List(initialCapacity);

  void add(List<int> chunk) {
    final chunkLen = chunk.length;
    if (chunkLen == 0) return;
    final needed = _len + chunkLen;
    if (needed > _buf.length) {
      var cap = _buf.length;
      while (cap < needed) {
        cap *= 2;
      }
      final next = Uint8List(cap)..setRange(0, _len, _buf);
      _buf = next;
    }
    _buf.setRange(_len, needed, chunk);
    _len = needed;

    var start = 0;
    for (var i = 0; i < _len; i++) {
      if (_buf[i] != 10) continue;
      var end = i;
      if (end > start && _buf[end - 1] == 13) end--;
      onLine(_buf, start, end);
      start = i + 1;
    }
    if (start > 0) {
      final rest = _len - start;
      if (rest > 0) _buf.setRange(0, rest, _buf, start);
      _len = rest;
    }
  }

  void finish() {
    if (_len == 0) return;
    var end = _len;
    if (end > 0 && _buf[end - 1] == 13) end--;
    if (end > 0) onLine(_buf, 0, end);
    _len = 0;
  }
}

// ── Byte-level CSV helpers ─────────────────────────────────────────────────

/// Index of the next comma in `[start, end)`, or `end`.
int nextComma(Uint8List b, int start, int end) {
  for (var i = start; i < end; i++) {
    if (b[i] == 44) return i;
  }
  return end;
}

/// Signed byte range → String (unquoted, trimmed).
String fieldString(Uint8List b, int start, int end) {
  var s = start;
  var e = end;
  if (s < e && b[s] == 34) s++;
  if (e > s && b[e - 1] == 34) e--;
  while (s < e && (b[s] == 32 || b[s] == 9)) {
    s++;
  }
  while (e > s && (b[e - 1] == 32 || b[e - 1] == 9)) {
    e--;
  }
  if (s == e) return '';
  return String.fromCharCodes(b, s, e);
}

int? parseByteInt(Uint8List b, int start, int end) {
  var s = start;
  while (s < end && (b[s] == 32 || b[s] == 34)) {
    s++;
  }
  var e = end;
  while (e > s && (b[e - 1] == 32 || b[e - 1] == 13 || b[e - 1] == 34)) {
    e--;
  }
  if (s >= e) return null;
  var negative = false;
  if (b[s] == 45) {
    negative = true;
    s++;
  }
  var value = 0;
  for (var i = s; i < e; i++) {
    final c = b[i] - 48;
    if (c < 0 || c > 9) return null;
    value = value * 10 + c;
  }
  return negative ? -value : value;
}

double? parseByteDouble(Uint8List b, int start, int end) {
  final s = fieldString(b, start, end);
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Manual CSV line splitter for the small files (stops, routes, trips,
/// calendar), which are decoded to a String first.
List<String> csvRow(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') {
      inQuotes = !inQuotes;
    } else if (c == ',' && !inQuotes) {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

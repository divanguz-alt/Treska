// Compact, immutable index over the ZET GTFS static feed.
//
// Design goals (this is where ZET 1 spent most of its memory and CPU):
//   * never materialise stop_times.txt (112 MB) as a String — stream it;
//   * store per-stop and per-trip rows in Int32List instead of objects/maps;
//   * filter to the trips that actually run today while parsing;
//   * expose O(log n) lookups for the two questions the UI asks:
//       "what departs from this stop in the next hour?"
//       "where is this trip right now?"
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'zip.dart';

class StopRecord {
  final String stopId;
  final String name;
  final double lat;
  final double lon;

  /// Bit mask of [kModeTram] / [kModeBus]; filled after stop_times are read.
  int modes = 0;

  StopRecord({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
  });
}

class RouteRecord {
  final String routeId;
  final String shortName;
  final int type;
  const RouteRecord({
    required this.routeId,
    required this.shortName,
    required this.type,
  });
}

/// One trip's stops in stop_sequence order.
class TripPattern {
  final Int32List stopIdx;
  final Int32List sequence;
  final Int32List departureSec; // seconds after midnight, may exceed 86400
  const TripPattern({
    required this.stopIdx,
    required this.sequence,
    required this.departureSec,
  });
}

/// Departures from one stop, sorted by scheduled arrival.
class StopDepartures {
  final Int32List tripIdx;
  final Int32List arrivalSec;
  const StopDepartures(this.tripIdx, this.arrivalSec);
  static final empty = StopDepartures(Int32List(0), Int32List(0));
}

class StaticData {
  final List<StopRecord> stops;
  final Map<String, int> stopIdx;
  final List<RouteRecord> routes;
  final Map<String, int> routeIdx;
  final List<String> headsigns;
  final Map<String, int> tripIdx; // only trips active today
  final Int32List tripRoute;
  final Int32List tripHeadsign;
  final List<TripPattern> patterns;
  final List<StopDepartures> departures;
  final int parseMs;

  const StaticData({
    required this.stops,
    required this.stopIdx,
    required this.routes,
    required this.routeIdx,
    required this.headsigns,
    required this.tripIdx,
    required this.tripRoute,
    required this.tripHeadsign,
    required this.patterns,
    required this.departures,
    required this.parseMs,
  });

  /// Index of the pattern position whose stop_sequence equals [sequence],
  /// or -1. Sequences are ascending in a GTFS stop_times row order.
  static int indexForSequence(Int32List sequences, int sequence) {
    var lo = 0;
    var hi = sequences.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final value = sequences[mid];
      if (value == sequence) return mid;
      if (value < sequence) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// First index in [arrivalSec] with value >= [sec].
  static int lowerBound(Int32List arrivalSec, int sec) {
    var lo = 0;
    var hi = arrivalSec.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (arrivalSec[mid] < sec) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

// ── Parsing ────────────────────────────────────────────────────────────────

/// Parses [zipPath]. Runs on the worker isolate.
Future<StaticData> parseStaticZip(String zipPath, DateTime day) async {
  final sw = Stopwatch()..start();
  final zip = await ZipSource.open(zipPath);
  try {
    final activeServices = await _readActiveServices(zip, day);

    final stopsRaw = await _readText(zip, 'stops.txt');
    final routesRaw = await _readText(zip, 'routes.txt');
    final tripsRaw = await _readText(zip, 'trips.txt');

    final stops = _parseStops(stopsRaw);
    final stopIdx = <String, int>{
      for (var i = 0; i < stops.length; i++) stops[i].stopId: i,
    };

    final routes = _parseRoutes(routesRaw);
    final routeIdx = <String, int>{
      for (var i = 0; i < routes.length; i++) routes[i].routeId: i,
    };

    final headsigns = <String>[];
    final headsignIdx = <String, int>{};

    final tripIds = <String>[];
    final tripIdxMap = <String, int>{};
    final tripRouteList = <int>[];
    final tripHeadsignList = <int>[];

    _parseActiveTrips(
      tripsRaw,
      activeServices,
      routeIdx,
      headsigns,
      headsignIdx,
      tripIds,
      tripIdxMap,
      tripRouteList,
      tripHeadsignList,
    );

    final tripCount = tripIds.length;
    final stopBuilders = List<List<int>?>.filled(tripCount, null);
    final seqBuilders = List<List<int>?>.filled(tripCount, null);
    final arrBuilders = List<List<int>?>.filled(tripCount, null);
    final depBuilders = List<List<int>?>.filled(tripCount, null);

    final entry = zip.entry('stop_times.txt');
    if (entry != null) {
      await _parseStopTimes(
        zip,
        entry,
        stopIdx,
        tripIdxMap,
        stopBuilders,
        seqBuilders,
        arrBuilders,
        depBuilders,
      );
    }

    // Convert per-trip lists to compact typed arrays.
    final patterns = List<TripPattern>.filled(tripCount, _emptyPattern,
        growable: false);
    for (var t = 0; t < tripCount; t++) {
      final s = stopBuilders[t];
      if (s == null || s.isEmpty) continue;
      final seq = seqBuilders[t]!;
      if (!_ascending(seq)) {
        final order = List<int>.generate(seq.length, (i) => i)
          ..sort((a, b) => seq[a].compareTo(seq[b]));
        patterns[t] = TripPattern(
          stopIdx: Int32List.fromList([for (final i in order) s[i]]),
          sequence: Int32List.fromList([for (final i in order) seq[i]]),
          departureSec:
              Int32List.fromList([for (final i in order) depBuilders[t]![i]]),
        );
        _reorderInPlace(arrBuilders[t]!, order);
        _reorderInPlace(stopBuilders[t]!, order);
      } else {
        patterns[t] = TripPattern(
          stopIdx: Int32List.fromList(s),
          sequence: Int32List.fromList(seq),
          departureSec: Int32List.fromList(depBuilders[t]!),
        );
      }
      // Fill mode masks once, while patterns are hot.
      final type = routes[tripRouteList[t]].type;
      final mode = type == kRouteTypeTram ? kModeTram : kModeBus;
      final stopIndices = patterns[t].stopIdx;
      for (var i = 0; i < stopIndices.length; i++) {
        stops[stopIndices[i]].modes |= mode;
      }
    }

    // Per-stop departure index. Pack (arrivalSec, tripIdx) into one int so a
    // plain sort keeps the pair aligned; both ranges fit comfortably in 64 bits.
    final perStop = List<List<int>?>.filled(stops.length, null);
    for (var t = 0; t < tripCount; t++) {
      final arr = arrBuilders[t];
      if (arr == null || arr.isEmpty) continue;
      final stopList = stopBuilders[t]!;
      for (var i = 0; i < stopList.length; i++) {
        (perStop[stopList[i]] ??= <int>[]).add((arr[i] << 20) | t);
      }
    }

    final departures = List<StopDepartures>.filled(
        stops.length, StopDepartures.empty,
        growable: false);
    for (var s = 0; s < stops.length; s++) {
      final packed = perStop[s];
      if (packed == null || packed.isEmpty) continue;
      packed.sort();
      final n = packed.length;
      final trips = Int32List(n);
      final arr = Int32List(n);
      for (var i = 0; i < n; i++) {
        final v = packed[i];
        trips[i] = v & 0xFFFFF;
        arr[i] = v >> 20;
      }
      departures[s] = StopDepartures(trips, arr);
    }

    return StaticData(
      stops: stops,
      stopIdx: stopIdx,
      routes: routes,
      routeIdx: routeIdx,
      headsigns: headsigns,
      tripIdx: tripIdxMap,
      tripRoute: Int32List.fromList(tripRouteList),
      tripHeadsign: Int32List.fromList(tripHeadsignList),
      patterns: patterns,
      departures: departures,
      parseMs: sw.elapsedMilliseconds,
    );
  } finally {
    await zip.close();
  }
}

final _emptyPattern = TripPattern(
  stopIdx: Int32List(0),
  sequence: Int32List(0),
  departureSec: Int32List(0),
);

bool _ascending(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[i - 1]) return false;
  }
  return true;
}

void _reorderInPlace(List<int> values, List<int> order) {
  final copy = List<int>.of(values);
  for (var i = 0; i < order.length; i++) {
    values[i] = copy[order[i]];
  }
}

Future<String> _readText(ZipSource zip, String name) async {
  final entry = zip.entry(name);
  if (entry == null) return '';
  final bytes = await zip.readAll(entry);
  return utf8.decode(bytes, allowMalformed: true)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
}

Set<String> _activeServices(String calendar, String calendarDates,
    String today, int weekday) {
  final active = <String>{};
  const dayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  if (calendar.isNotEmpty) {
    final lines = calendar.split('\n');
    if (lines.length > 1) {
      final header = csvRow(lines[0]);
      final iService = header.indexOf('service_id');
      final iStart = header.indexOf('start_date');
      final iEnd = header.indexOf('end_date');
      final iDay = header.indexOf(dayNames[weekday - 1]);
      if (iService >= 0 && iDay >= 0) {
        for (var i = 1; i < lines.length; i++) {
          final row = csvRow(lines[i]);
          if (row.length <= iService) continue;
          if (row.length <= iDay || row[iDay] != '1') continue;
          final start = iStart >= 0 && iStart < row.length ? row[iStart] : '';
          final end = iEnd >= 0 && iEnd < row.length ? row[iEnd] : '';
          if (start.isEmpty || today.compareTo(start) < 0) continue;
          if (end.isNotEmpty && today.compareTo(end) > 0) continue;
          active.add(row[iService]);
        }
      }
    }
  }

  if (calendarDates.isNotEmpty) {
    final lines = calendarDates.split('\n');
    if (lines.length > 1) {
      final header = csvRow(lines[0]);
      final iService = header.indexOf('service_id');
      final iDate = header.indexOf('date');
      final iType = header.indexOf('exception_type');
      for (var i = 1; i < lines.length; i++) {
        final row = csvRow(lines[i]);
        if (iService >= 0 && row.length <= iService) continue;
        if (iDate >= 0 &&
            iDate < row.length &&
            row[iDate] != today) {
          continue;
        }
        if (iType < 0 || iType >= row.length) continue;
        if (row[iType] == '1') active.add(row[iService]);
        if (row[iType] == '2') active.remove(row[iService]);
      }
    }
  }
  return active;
}

Future<Set<String>> _readActiveServices(ZipSource zip, DateTime day) async {
  final calendar = await _readText(zip, 'calendar.txt');
  final calendarDates = await _readText(zip, 'calendar_dates.txt');
  final today = '${day.year}${_pad2(day.month)}${_pad2(day.day)}';
  return _activeServices(calendar, calendarDates, today, day.weekday);
}

String _pad2(int v) => v.toString().padLeft(2, '0');

List<StopRecord> _parseStops(String raw) {
  final out = <StopRecord>[];
  if (raw.isEmpty) return out;
  final lines = raw.split('\n');
  if (lines.length < 2) return out;
  final header = csvRow(lines[0]);
  final iId = header.indexOf('stop_id');
  final iName = header.indexOf('stop_name');
  final iLat = header.indexOf('stop_lat');
  final iLon = header.indexOf('stop_lon');
  if (iId < 0 || iName < 0 || iLat < 0 || iLon < 0) return out;

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iLon) continue;
    final lat = double.tryParse(row[iLat]) ?? 0;
    final lon = double.tryParse(row[iLon]) ?? 0;
    if (lat == 0 || lon == 0) continue;
    out.add(StopRecord(
      stopId: row[iId],
      name: row[iName],
      lat: lat,
      lon: lon,
    ));
  }
  return out;
}

List<RouteRecord> _parseRoutes(String raw) {
  final out = <RouteRecord>[];
  if (raw.isEmpty) return out;
  final lines = raw.split('\n');
  if (lines.length < 2) return out;
  final header = csvRow(lines[0]);
  final iId = header.indexOf('route_id');
  final iShort = header.indexOf('route_short_name');
  final iType = header.indexOf('route_type');
  if (iId < 0) return out;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iId) continue;
    final type =
        iType >= 0 && iType < row.length ? int.tryParse(row[iType]) ?? 3 : 3;
    final short =
        iShort >= 0 && iShort < row.length ? row[iShort] : row[iId];
    out.add(RouteRecord(routeId: row[iId], shortName: short, type: type));
  }
  return out;
}

void _parseActiveTrips(
  String raw,
  Set<String> activeServices,
  Map<String, int> routeIdx,
  List<String> headsigns,
  Map<String, int> headsignIdx,
  List<String> tripIds,
  Map<String, int> tripIdxMap,
  List<int> tripRouteList,
  List<int> tripHeadsignList,
) {
  if (raw.isEmpty) return;
  final lines = raw.split('\n');
  if (lines.length < 2) return;
  final header = csvRow(lines[0]);
  final iTrip = header.indexOf('trip_id');
  final iRoute = header.indexOf('route_id');
  final iService = header.indexOf('service_id');
  final iHead = header.indexOf('trip_headsign');
  if (iTrip < 0 || iRoute < 0 || iService < 0) return;

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iService || row.length <= iRoute) continue;
    if (!activeServices.contains(row[iService])) continue;
    final route = routeIdx[row[iRoute]];
    if (route == null) continue;
    final headsign = iHead >= 0 && iHead < row.length ? row[iHead] : '';
    final hIdx = headsign.isEmpty
        ? -1
        : (headsignIdx[headsign] ??= _addHeadsign(headsigns, headsign));
    final idx = tripIds.length;
    tripIds.add(row[iTrip]);
    tripIdxMap[row[iTrip]] = idx;
    tripRouteList.add(route);
    tripHeadsignList.add(hIdx);
  }
}

int _addHeadsign(List<String> headsigns, String value) {
  headsigns.add(value);
  return headsigns.length - 1;
}

/// Streams stop_times.txt and keeps only rows of trips active today.
///
/// The trip_id column repeats for every row of a trip, so it is compared as raw
/// bytes against the previous row and only decoded when it changes. That avoids
/// ~1.4 million throw-away Strings in the common case.
Future<void> _parseStopTimes(
  ZipSource zip,
  ZipEntryInfo entry,
  Map<String, int> stopIdx,
  Map<String, int> tripIdx,
  List<List<int>?> stopBuilders,
  List<List<int>?> seqBuilders,
  List<List<int>?> arrBuilders,
  List<List<int>?> depBuilders,
) async {
  var headerSeen = false;
  var iTrip = 0, iArr = 1, iDep = 2, iStop = 3, iSeq = 4;

  var prevStart = -1, prevEnd = -1;
  var prevTrip = -1;
  final prevBytes = Uint8List(64);
  var prevLen = 0;

  final splitter = ByteLineSplitter((b, start, end) {
    if (end <= start) return;
    if (!headerSeen) {
      headerSeen = true;
      final header = csvRow(String.fromCharCodes(b, start, end));
      final t = header.indexOf('trip_id');
      final a = header.indexOf('arrival_time');
      final d = header.indexOf('departure_time');
      final s = header.indexOf('stop_id');
      final q = header.indexOf('stop_sequence');
      if (t < 0 || s < 0 || (a < 0 && d < 0)) return;
      iTrip = t;
      iArr = a;
      iDep = d;
      iStop = s;
      iSeq = q;
      return;
    }

    // Locate the needed columns in one pass.
    var field = 0;
    var tripS = -1, tripE = -1;
    var arrS = -1, arrE = -1;
    var depS = -1, depE = -1;
    var stopS = -1, stopE = -1;
    var seqS = -1, seqE = -1;

    var pos = start;
    while (true) {
      final comma = nextComma(b, pos, end);
      if (field == iTrip) {
        tripS = pos;
        tripE = comma;
      }
      if (field == iArr) {
        arrS = pos;
        arrE = comma;
      }
      if (field == iDep) {
        depS = pos;
        depE = comma;
      }
      if (field == iStop) {
        stopS = pos;
        stopE = comma;
      }
      if (field == iSeq) {
        seqS = pos;
        seqE = comma;
      }
      if (comma >= end) break;
      pos = comma + 1;
      field++;
    }

    if (tripS < 0 || stopS < 0) return;

    // Fast path: same trip_id as the previous row.
    var trip = -1;
    final tripLen = tripE - tripS;
    if (prevTrip >= 0 &&
        tripLen == prevEnd - prevStart &&
        _sameBytes(b, tripS, prevBytes, 0, tripLen)) {
      trip = prevTrip;
    } else {
      final id = fieldString(b, tripS, tripE);
      trip = tripIdx[id] ?? -1;
      prevTrip = trip;
      prevStart = 0;
      prevEnd = tripLen;
      prevLen = tripLen < prevBytes.length ? tripLen : prevBytes.length;
      if (prevLen > 0) prevBytes.setRange(0, prevLen, b, tripS);
    }
    if (trip < 0) return;

    final stopId = fieldString(b, stopS, stopE);
    final stop = stopIdx[stopId];
    if (stop == null) return;

    final arr = arrS >= 0 ? _timeSec(b, arrS, arrE) : 0;
    final dep = depS >= 0 ? _timeSec(b, depS, depE) : arr;
    final arrSec = arr != 0 ? arr : dep;
    if (arrSec == 0) return;
    final seq = seqS >= 0 ? parseByteInt(b, seqS, seqE) ?? 0 : 0;

    (stopBuilders[trip] ??= <int>[]).add(stop);
    (seqBuilders[trip] ??= <int>[]).add(seq);
    (arrBuilders[trip] ??= <int>[]).add(arrSec);
    (depBuilders[trip] ??= <int>[]).add(dep != 0 ? dep : arrSec);
  });

  await for (final chunk in zip.stream(entry)) {
    splitter.add(chunk);
  }
  splitter.finish();
}

bool _sameBytes(Uint8List a, int aStart, Uint8List prev, int prevStart, int len) {
  for (var i = 0; i < len; i++) {
    if (a[aStart + i] != prev[prevStart + i]) return false;
  }
  return true;
}

/// "HH:MM:SS" bytes → seconds after midnight. Hours may exceed 23 (GTFS allows
/// trips after midnight, e.g. 25:10:00).
int _timeSec(Uint8List b, int start, int end) {
  var s = start;
  var e = end;
  if (s < e && b[s] == 34) s++;
  if (e > s && b[e - 1] == 34) e--;
  var colons = 0;
  var h = 0, m = 0, sec = 0;
  var value = 0;
  for (var i = s; i < e; i++) {
    final c = b[i];
    if (c == 58) {
      if (colons == 0) {
        h = value;
      } else if (colons == 1) {
        m = value;
      }
      colons++;
      value = 0;
    } else if (c >= 48 && c <= 57) {
      value = value * 10 + (c - 48);
    }
  }
  sec = value;
  if (colons != 2) return 0;
  return h * 3600 + m * 60 + sec;
}

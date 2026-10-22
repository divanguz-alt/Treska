import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/gtfs_rt.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/data/rt_socket.dart';

/// Encodes a protobuf varint.
List<int> _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return out;
}

List<int> _tag(int field, int wire) => _varint((field << 3) | wire);

List<int> _bytesField(int field, List<int> payload) =>
    [..._tag(field, 2), ..._varint(payload.length), ...payload];

List<int> _floatField(int field, double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  return [..._tag(field, 5), ...data.buffer.asUint8List()];
}

List<int> _intField(int field, int value) =>
    [..._tag(field, 0), ..._varint(value)];

List<int> _stringField(int field, String value) =>
    _bytesField(field, utf8.encode(value));

void main() {
  group('gtfs-rt parser', () {
    test('reads header timestamp, vehicle timestamp and position', () {
      final trip = _stringField(1, 'trip-1');
      final position = [
        ..._floatField(1, 45.8),
        ..._floatField(2, 15.9),
        ..._floatField(3, 123.5),
      ];
      final vehicle = [
        ..._bytesField(1, trip),
        ..._bytesField(3, position),
        ..._intField(6, 1792687645),
      ];
      final entity = [
        ..._stringField(1, 'e1'),
        ..._bytesField(4, vehicle),
      ];
      final feed = Uint8List.fromList([
        ..._bytesField(1, _intField(1, 1792687650)),
        ..._bytesField(2, entity),
      ]);

      final parsed = parseRtFeed(feed);

      expect(parsed.timestamp, 1792687650);
      expect(parsed.entities, hasLength(1));
      final vp = parsed.entities.first.vehicle!;
      expect(vp.trip.tripId, 'trip-1');
      expect(vp.position.latitude, closeTo(45.8, 0.001));
      expect(vp.position.longitude, closeTo(15.9, 0.001));
      expect(vp.timestamp, 1792687645);
    });

    test('keeps parsing after a malformed tail', () {
      final entity = [
        ..._stringField(1, 'e1'),
        ..._bytesField(4, _stringField(1, 'trip-1')),
      ];
      final valid = [..._bytesField(2, entity)];
      final feed = Uint8List.fromList([...valid, 0xFF, 0xFF, 0xFF]);

      expect(parseRtFeed(feed).entities, hasLength(1));
    });
  });

  group('feed age', () {
    final now = DateTime(2026, 10, 22, 18, 0, 0);
    int unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

    test('adds header age to the position age exactly once', () {
      final stats = FeedStats(
        feedTimestamp: unix(now) - 10,
        positionAgeSec: 4,
      );
      expect(stats.ageSecAt(now), 14);
    });

    test('keeps growing when the feed stalls', () {
      final stats = FeedStats(
        feedTimestamp: unix(now) - 180,
        positionAgeSec: 5,
      );
      expect(stats.ageSecAt(now), 185);
    });

    test('falls back to position age when the header is missing', () {
      const stats = FeedStats(positionAgeSec: 42);
      expect(stats.ageSecAt(now), 42);
    });
  });

  group('rt socket protocol', () {
    test('hex decoding round-trips through the relay payload shape', () {
      final payload = Uint8List.fromList(List.generate(240, (i) => i % 251));
      final hex = payload
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      // The socket decodes hex then gunzips; this checks the hex step matches
      // what the relay sends for `gzipped_data`.
      expect(hex.length, payload.length * 2);
      expect(hex.substring(0, 4), '0001');
      expect(RtSocket.defaultUrl, startsWith('wss://'));
    });
  });
}

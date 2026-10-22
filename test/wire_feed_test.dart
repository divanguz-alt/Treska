import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/wire_feed.dart';

/// Builds a relay snapshot the way zet.skoljka.org sends it.
String relaySnapshot({
  required int timestamp,
  required List<Map<String, Object?>> vehicles,
}) {
  return jsonEncode({
    'timestamp': timestamp,
    'activeStaticKey': 'abc',
    'vehicles': {
      'routeIds': [for (final v in vehicles) v['route']],
      'shapeIds': [for (final v in vehicles) v['shape']],
      'vehicleIds': [for (final _ in vehicles) 'veh'],
      'tripIds': [for (final v in vehicles) v['trip']],
      'blockIds': [for (final _ in vehicles) null],
      'timestamps': [for (final v in vehicles) v['age']],
      'reportDelays': [for (final v in vehicles) v['delay']],
      'directionDegrees': [for (final v in vehicles) v['dir']],
      'compressedLats': [for (final v in vehicles) v['lats']],
      'compressedLons': [for (final v in vehicles) v['lons']],
    },
  });
}

/// Micro-degree deltas that land on the given decimal degree value.
List<int> microDeltas(double value, double reference) =>
    [((value - reference) * 1e6).round()];

void main() {
  group('wire feed', () {
    test('decodes delta-encoded coordinates around Zagreb', () {
      const refLat = 45.815;
      const refLon = 15.9819;
      final json = relaySnapshot(
        timestamp: 1792687650,
        vehicles: [
          {
            'route': 17,
            'shape': '17_2',
            'trip': '0_1_1706_17_12679',
            'age': 6,
            'delay': 158,
            'dir': 66,
            'lats': microDeltas(45.81221, refLat),
            'lons': microDeltas(15.92043, refLon),
          },
        ],
      );

      final feed = parseWireFeed(json)!;

      expect(feed.timestamp, 1792687650);
      expect(feed.entities, hasLength(1));
      final vp = feed.entities.first.vehicle!;
      expect(vp.trip.tripId, '0_1_1706_17_12679');
      expect(vp.trip.routeId, '17');
      expect(vp.position.latitude, closeTo(45.81221, 1e-5));
      expect(vp.position.longitude, closeTo(15.92043, 1e-5));
      expect(vp.position.bearing, 66);
      expect(vp.timestamp, 1792687644);

      final tu = feed.entities.first.tripUpdate!;
      expect(tu.delay, 158);
      expect(tu.hasDelay, isTrue);
      expect(tu.stopTimeUpdates, isEmpty);
      expect(tu.shapeId, '17_2');
    });

    test('accumulates multi-point deltas along a vehicle track', () {
      const refLat = 45.815;
      final json = relaySnapshot(
        timestamp: 1792687650,
        vehicles: [
          {
            'route': 4,
            'shape': '4_1',
            'trip': 't',
            'age': 0,
            'delay': 0,
            'dir': 12,
            'lats': [1000, 20, -30],
            'lons': [500, -10],
          },
        ],
      );

      final feed = parseWireFeed(json)!;
      final vp = feed.entities.first.vehicle!;
      expect(vp.position.latitude, closeTo(refLat + 990 * 1e-6, 1e-9));
      expect(vp.position.longitude, closeTo(15.9819 + 490 * 1e-6, 1e-9));
    });

    test('ignores news and app-version notices', () {
      expect(parseWireFeed('{"type":"news-status","version":"abc"}'), isNull);
      expect(parseWireFeed('{"type":"app-version","version":"abc"}'), isNull);
      expect(parseWireFeed('not json'), isNull);
    });

    test('treats a fix ahead of the feed as just now', () {
      final json = relaySnapshot(
        timestamp: 1792687650,
        vehicles: [
          {
            'route': 6,
            'shape': '6_1',
            'trip': 't',
            'age': -3,
            'delay': null,
            'dir': null,
            'lats': [0],
            'lons': [0],
          },
        ],
      );

      final feed = parseWireFeed(json)!;
      expect(feed.entities.first.vehicle!.timestamp, 1792687650);
      expect(feed.entities.first.tripUpdate!.hasDelay, isFalse);
    });
  });
}

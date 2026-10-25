@Tags(['reality'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/gtfs_rt.dart';

/// Needs a fresh copy of ZET's realtime feed (see CLAUDE.md for the curl line).
/// Run with:
///   flutter test --tags reality --run-skipped test/rt_reality_test.dart
void main() {
  const rtPath = '/tmp/zet_rt.bin';

  test('vehicles from the real feed carry a GPS fix in Zagreb', () {
    final file = File(rtPath);
    if (!file.existsSync()) {
      markTestSkipped('fixture missing');
      return;
    }
    final feed = parseRtFeed(file.readAsBytesSync());
    final vehicles = [
      for (final e in feed.entities)
        if (e.vehicle != null) e.vehicle!,
    ];
    expect(vehicles, isNotEmpty);
    // The header timestamp is a real unix time, not a misread field.
    expect(feed.timestamp, greaterThan(1700000000));
    for (final v in vehicles) {
      expect(v.position.latitude, inInclusiveRange(45.6, 46.0),
          reason: v.trip.tripId);
      expect(v.position.longitude, inInclusiveRange(15.7, 16.3),
          reason: v.trip.tripId);
      expect(v.timestamp, greaterThan(1700000000), reason: v.trip.tripId);
    }
  });
}

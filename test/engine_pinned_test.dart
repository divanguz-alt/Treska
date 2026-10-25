@Tags(['reality'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/feed_engine.dart';
import 'package:zet2/data/gtfs_static.dart';
import 'package:zet2/data/models.dart';

/// Needs the real static feed (see CLAUDE.md for the curl line). Run with:
///   flutter test --tags reality --run-skipped test/engine_pinned_test.dart
void main() {
  const zipPath = '/tmp/zet_static.zip';

  Future<FeedEngine?> load(DateTime day) async {
    if (!File(zipPath).existsSync()) return null;
    return FeedEngine(await parseStaticZip(zipPath, day));
  }

  test('a pinned stop outside the radius still gets a board', () async {
    final now = DateTime(2026, 10, 22, 10);
    final engine = await load(now);
    if (engine == null) {
      markTestSkipped('fixture missing');
      return;
    }
    // A Črnomerec platform, ~3.5 km west of Kaptol.
    final crnomerec = engine.data.stops
        .firstWhere((s) => stopGroupKey(s.name) == 'ČRNOMEREC');

    final snap = engine.refresh(
      lat: 45.8143,
      lon: 15.9790,
      rtBytes: null,
      now: now,
      pinnedStopIds: {crnomerec.stopId},
    );

    final nearbyIds = [
      for (final s in [...snap.tramStops, ...snap.busStops]) s.stop.id,
    ];
    expect(nearbyIds, isNot(contains(crnomerec.stopId)),
        reason: 'pinned stops must not leak into the nearby lists');
    expect(snap.pinnedStops, hasLength(1));
    expect(snap.pinnedStops.single.stop.id, crnomerec.stopId);
    expect(snap.pinnedStops.single.arrivals, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('timetable rows are not shifted on a DST change day', () async {
    // 25 Oct 2026: clocks go back. Local midnight is 01:00 in GTFS terms, so
    // anchoring schedule times at midnight made every row an hour early and
    // dropped them as already departed.
    final now = DateTime(2026, 10, 25, 9);
    final engine = await load(now);
    if (engine == null) {
      markTestSkipped('fixture missing');
      return;
    }
    final snap = engine.refresh(
      lat: 45.8143,
      lon: 15.9790,
      rtBytes: null,
      now: now,
    );
    final rows = [
      for (final s in [...snap.tramStops, ...snap.busStops]) ...s.arrivals,
    ];
    expect(rows, isNotEmpty);
    for (final a in rows) {
      final minutes = a.time.difference(now).inMinutes;
      expect(minutes, inInclusiveRange(-2, 60),
          reason: '${a.routeShortName} at ${a.time} is outside the hour');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

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

  test('vehicles from ZET\'s own protobuf are measured, not estimated',
      () async {
    final rt = File('/tmp/zet_rt.bin');
    if (!rt.existsSync()) {
      markTestSkipped('fixture missing');
      return;
    }
    final bytes = rt.readAsBytesSync();
    // Use the feed's own day so its trip ids resolve against the timetable.
    final engine = await load(DateTime.now());
    if (engine == null) {
      markTestSkipped('fixture missing');
      return;
    }
    final snap = engine.refresh(
      lat: 45.8143,
      lon: 15.9790,
      rtBytes: bytes,
      now: DateTime.now(),
    );
    final measured = snap.vehicles.where((v) => !v.estimated).length;
    expect(measured, greaterThan(50),
        reason: 'VehiclePosition fixes must be decoded from the protobuf');
    expect(snap.stats.feedTimestamp, greaterThan(1700000000));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('after midnight the board shows yesterday\'s night trams', () async {
    // Tue 27 Oct 2026, 00:30. Night trams 31–34 are timetabled as 24:xx–28:xx
    // on Monday's service, which also runs on Tuesday under the same trip ids.
    final now = DateTime(2026, 10, 27, 0, 30);
    final engine = await load(now);
    if (engine == null) {
      markTestSkipped('fixture missing');
      return;
    }
    expect(engine.data.carryDate, '20261026');
    expect(engine.data.carryTripIdx, isNotEmpty);

    final snap = engine.refresh(
      lat: 45.8131,
      lon: 15.9772,
      rtBytes: null,
      now: now,
      radiusM: 1200,
    );
    final rows = [for (final s in snap.tramStops) ...s.arrivals];
    expect(rows.map((a) => a.routeShortName),
        contains(anyOf('31', '32', '33', '34')));
    for (final a in rows) {
      expect(a.time.difference(now).inMinutes, inInclusiveRange(-2, 60),
          reason: '${a.routeShortName} at ${a.time}');
    }

    // The same id resolves to Monday's run with Monday's start date and to
    // Tuesday's run otherwise.
    final id = engine.data.carryTripIdx.keys
        .firstWhere(engine.data.tripIdx.containsKey);
    expect(engine.data.tripFor(id, startDate: '20261026'),
        engine.data.carryTripIdx[id]);
    expect(engine.data.tripFor(id, startDate: '20261027'),
        engine.data.tripIdx[id]);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

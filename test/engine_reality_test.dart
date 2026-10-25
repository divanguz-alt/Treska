// ignore_for_file: avoid_print
@Tags(['reality'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/feed_engine.dart';
import 'package:zet2/data/gtfs_rt.dart';
import 'package:zet2/data/gtfs_static.dart';
import 'package:zet2/data/wire_feed.dart';

/// Runs the production engine against a real ZET static feed and a real relay
/// frame captured from wss://zet.skoljka.org. Not part of the normal test run:
/// it needs ~19 MB of fixtures. Run with:
///   flutter test --tags reality --run-skipped test/engine_reality_test.dart
void main() {
  test('engine vehicle count matches the relay frame', () async {
    final zipFile = File('/private/var/folders/qz/p0jys3n54v52bgv7w2bxkf080000gn/T/opencode/gtfs.zip');
    final frameFile = File('/private/var/folders/qz/p0jys3n54v52bgv7w2bxkf080000gn/T/opencode/relay_frame.json');
    if (!zipFile.existsSync() || !frameFile.existsSync()) {
      markTestSkipped('fixtures missing');
      return;
    }

    final data =
        await parseStaticZip(zipFile.path, DateTime(2026, 10, 22));
    final frame =
        jsonDecode(frameFile.readAsStringSync()) as Map<String, dynamic>;
    final relayCount = (frame['vehicles']['routeIds'] as List).length;

    final feed = parseWireFeed(jsonEncode(frame))!;
    final engine = FeedEngine(data);
    final snap = engine.refresh(
      lat: 45.815,
      lon: 15.982,
      rtBytes: null,
      rtFeed: feed,
      now: DateTime(2026, 10, 22, 20, 39),
    );

    print('relay frame vehicles: $relayCount');
    print('engine vehicles:      ${snap.vehicles.length}');
    print('  tram: ${snap.stats.vehiclesTram}  bus: ${snap.stats.vehiclesBus}');
    print('  entities: ${snap.stats.rtEntities}');
    print('  tram stops: ${snap.tramStops.length}  bus stops: ${snap.busStops.length}');

    expect(
      snap.vehicles.length,
      relayCount,
      reason: 'engine must not invent or drop vehicles',
    );
    expect(snap.vehicles.every((v) => !v.estimated), isTrue,
        reason: 'map vehicles must all have a real GPS fix');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('stream + REST merge does not inflate the vehicle count', () async {
    final dir = Directory(
        '/private/var/folders/qz/p0jys3n54v52bgv7w2bxkf080000gn/T/opencode');
    final zipFile = File('${dir.path}/gtfs.zip');
    final frameFile = File('${dir.path}/relay_frame.json');
    final rtFile = File('${dir.path}/rt_now.pb');
    if (!zipFile.existsSync() || !frameFile.existsSync() || !rtFile.existsSync()) {
      markTestSkipped('fixtures missing');
      return;
    }

    final data =
        await parseStaticZip(zipFile.path, DateTime(2026, 10, 22));
    final frame =
        jsonDecode(frameFile.readAsStringSync()) as Map<String, dynamic>;
    final relayCount = (frame['vehicles']['routeIds'] as List).length;
    final streamFeed = parseWireFeed(jsonEncode(frame))!;
    final restFeed = parseRtFeed(rtFile.readAsBytesSync());

    final engine = FeedEngine(data);
    final snap = engine.refresh(
      lat: 45.815,
      lon: 15.982,
      rtBytes: rtFile.readAsBytesSync(),
      rtFeed: streamFeed,
      now: DateTime(2026, 10, 22, 20, 41),
    );

    print('stream ${streamFeed.entities.length} + '
        'REST ${restFeed.entities.length} = merged ${snap.stats.rtEntities}');
    print('vehicles drawn: ${snap.vehicles.length} '
        '(${snap.stats.vehiclesTram} tram / ${snap.stats.vehiclesBus} bus), '
        'trip-update-only: ${snap.stats.estimatedVehicles}');
    print('board: ${snap.stats.rtArrivals} RT, '
        '${snap.stats.estimatedArrivals} estimated, '
        '${snap.stats.scheduledArrivals} scheduled');

    // Every REST vehicle is also in the stream, so the merged set must stay
    // close to the stream count rather than doubling.
    expect(
      snap.vehicles.length,
      lessThanOrEqualTo(relayCount + 20),
      reason: 'merging REST must not invent vehicles the stream already has',
    );
    expect(snap.vehicles.length, greaterThan(relayCount - 20));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

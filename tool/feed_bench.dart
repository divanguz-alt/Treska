// ignore_for_file: avoid_print
// Dev-only benchmark for the realtime join.
//
//   dart run tool/feed_bench.dart /tmp/zet_static.zip /tmp/zet_rt.bin
//
// Prints one sample board and steady-state refresh timings.
import 'dart:io';
import 'dart:typed_data';

import 'package:zet2/data/feed_engine.dart';
import 'package:zet2/data/gtfs_static.dart';

Future<void> main(List<String> args) async {
  final staticPath = args.isNotEmpty ? args[0] : '/tmp/zet_static.zip';
  final rtPath = args.length > 1 ? args[1] : '/tmp/zet_rt.bin';

  final data = await parseStaticZip(staticPath, DateTime.now());
  final engine = FeedEngine(data);
  final rt = Uint8List.fromList(File(rtPath).readAsBytesSync());

  // A few points around Zagreb.
  const points = [
    (45.8150, 15.9819, 'Glavni kolodvor'),
    (45.815002, 15.934932, 'Črnomerec'),
    (45.7960, 15.9550, 'Trešnjevka'),
    (45.8280, 16.0180, 'Dubrava'),
  ];

  for (final (lat, lon, label) in points) {
    final snap = engine.refresh(
      lat: lat,
      lon: lon,
      rtBytes: rt,
      now: DateTime.now(),
    );
    print('\n=== $label');
    print('tram stops ${snap.tramStops.length} | bus stops ${snap.busStops.length} '
        '| vehicles ${snap.vehicles.length} '
        '(${snap.stats.vehiclesTram} tram / ${snap.stats.vehiclesBus} bus) '
        '| rt arr ${snap.stats.rtArrivals} | sched ${snap.stats.scheduledArrivals} '
        '| ${snap.stats.refreshMs} ms');
    for (final s in snap.tramStops.take(2)) {
      print('  TRAM ${s.stop.name} ${s.distanceM.round()}m');
      for (final a in s.arrivals.take(4)) {
        print('    ${a.routeShortName.padLeft(3)}  '
            '${a.time.hour.toString().padLeft(2, '0')}:'
            '${a.time.minute.toString().padLeft(2, '0')}  '
            '${a.isRealtime ? 'RT ' : 'sch'}  ${a.headsign}');
      }
    }
    for (final s in snap.busStops.take(1)) {
      print('  BUS  ${s.stop.name} ${s.distanceM.round()}m');
      for (final a in s.arrivals.take(3)) {
        print('    ${a.routeShortName.padLeft(3)}  '
            '${a.time.hour.toString().padLeft(2, '0')}:'
            '${a.time.minute.toString().padLeft(2, '0')}  '
            '${a.isRealtime ? 'RT ' : 'sch'}  ${a.headsign}');
      }
    }
  }

  // Steady state: 30 refreshes at a fixed point.
  final sw = Stopwatch()..start();
  var ms = 0;
  for (var i = 0; i < 30; i++) {
    final snap = engine.refresh(
      lat: 45.8150,
      lon: 15.9819,
      rtBytes: rt,
      now: DateTime.now(),
    );
    ms += snap.stats.refreshMs;
  }
  sw.stop();
  print('\nrefresh          avg ${(ms / 30).toStringAsFixed(1)} ms '
      'over 30 runs (wall ${sw.elapsedMilliseconds} ms)');
  print('rss              ${(ProcessInfo.currentRss / (1 << 20)).round()} MB');
}

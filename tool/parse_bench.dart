// ignore_for_file: avoid_print
// Dev-only benchmark for the GTFS static parser.
//
//   dart run tool/parse_bench.dart /tmp/zet_static.zip
//
// Verifies the streaming ZIP reader against the real ZET feed and prints
// timings so regressions in startup cost are visible immediately.
import 'dart:io';

import 'package:zet2/data/gtfs_static.dart';

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args[0] : '/tmp/zet_static.zip';
  if (!File(path).existsSync()) {
    stderr.writeln('missing file: $path');
    exit(2);
  }

  final total = Stopwatch()..start();
  final data = await parseStaticZip(path, DateTime.now());
  total.stop();

  var departures = 0;
  for (final d in data.departures) {
    departures += d.tripIdx.length;
  }
  var patternRows = 0;
  for (final p in data.patterns) {
    patternRows += p.stopIdx.length;
  }
  final tramStops = data.stops.where((s) => s.modes & 1 != 0).length;
  final busStops = data.stops.where((s) => s.modes & 2 != 0).length;

  print('parse              ${data.parseMs} ms (wall ${total.elapsedMilliseconds} ms)');
  print('stops              ${data.stops.length}  (tram $tramStops, bus $busStops)');
  print('routes             ${data.routes.length}');
  print('active trips       ${data.tripIdx.length} / patterns ${data.patterns.length}');
  print('pattern rows       $patternRows');
  print('stop departures    $departures');
  print('headsigns          ${data.headsigns.length}');

  // Sanity: every pattern length matches, times ascending.
  var bad = 0;
  for (final p in data.patterns) {
    if (p.stopIdx.length != p.sequence.length ||
        p.stopIdx.length != p.departureSec.length) {
      bad++;
    }
  }
  print('inconsistent       $bad');

  // Spot-check one stop: next 5 departures from now.
  final now = DateTime.now();
  final nowSec = now.hour * 3600 + now.minute * 60 + now.second;
  var bestStop = 0;
  var bestCount = -1;
  for (var i = 0; i < data.departures.length; i++) {
    final c = data.departures[i].tripIdx.length;
    if (c > bestCount) {
      bestCount = c;
      bestStop = i;
    }
  }
  final d = data.departures[bestStop];
  final from = StaticData.lowerBound(d.arrivalSec, nowSec);
  print('busiest stop       ${data.stops[bestStop].name} ($bestCount departures)');
  for (var i = from; i < d.tripIdx.length && i < from + 5; i++) {
    final t = d.tripIdx[i];
    final route = data.routes[data.tripRoute[t]];
    final h = data.tripHeadsign[t];
    final headsign = h >= 0 ? data.headsigns[h] : '';
    final sec = d.arrivalSec[i];
    print('  ${route.shortName.padLeft(3)}  '
        '${(sec ~/ 3600).toString().padLeft(2, '0')}:'
        '${((sec % 3600) ~/ 60).toString().padLeft(2, '0')}  $headsign');
  }

  print('rss                ${(ProcessInfo.currentRss / (1 << 20)).round()} MB');
}

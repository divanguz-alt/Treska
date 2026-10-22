// Joins the static schedule with the GTFS-Realtime feed.
//
// Pure Dart: no Flutter imports, no platform channels. Runs on the worker
// isolate and returns a small, immutable [FeedSnapshot] for the UI.
import 'dart:typed_data';

import 'gtfs_rt.dart';
import 'gtfs_static.dart';
import 'models.dart';

class _RtTripStop {
  final int stopIdx;
  final int unixTime;
  const _RtTripStop(this.stopIdx, this.unixTime);
}

class _PendingVehicle {
  final String tripId;
  final String routeId;
  final double bearing;
  final int timestamp;
  const _PendingVehicle(this.tripId, this.routeId, this.bearing,
      [this.timestamp = 0]);
}

class _PrevPos {
  final double lat;
  final double lon;
  final double bearing;
  const _PrevPos(this.lat, this.lon, this.bearing);
}

class _CandidateStop {
  final int stopIdx;
  final double distanceM;
  final List<_Arr> arrivals = [];
  _CandidateStop(this.stopIdx, this.distanceM);
}

class _Arr {
  final String route;
  final String headsign;
  final int routeType;
  final DateTime time;
  final bool realtime;

  /// Schedule shifted by the trip's current RT delay.
  final bool estimated;

  /// Current trip delay in seconds (positive = late).
  final int delaySec;

  const _Arr({
    required this.route,
    required this.headsign,
    required this.routeType,
    required this.time,
    required this.realtime,
    this.estimated = false,
    this.delaySec = 0,
  });
}

class _MergeBox {
  int stopIdx;
  double distanceM;
  final List<_Arr> arrivals = [];
  _MergeBox(this.stopIdx, this.distanceM);
}

/// Joins [StaticData] with an optional realtime payload.
///
/// One instance lives inside the worker isolate for the lifetime of the app, so
/// the previous-position table and lookup maps survive between refreshes.
class FeedEngine {
  final StaticData data;

  final Map<String, List<_PrevPos>> _prevByRoute = {};

  FeedEngine(this.data);

  static const double searchRadiusM = 800;
  static const int maxStopsPerMode = 5;
  static const int maxArrivalsPerStop = 10;
  static const int maxPerRouteHeadsign = 2;
  static const int horizonSec = 3600;

  FeedSnapshot refresh({
    required double lat,
    required double lon,
    required Uint8List? rtBytes,
    required DateTime now,
    RtFeed? rtFeed,
  }) {
    final sw = Stopwatch()..start();

    final nowUnix = now.millisecondsSinceEpoch ~/ 1000;
    final midnight = DateTime(now.year, now.month, now.day);
    final midnightUnix = midnight.millisecondsSinceEpoch ~/ 1000;
    final nowSec = now.hour * 3600 + now.minute * 60 + now.second;

    // ── Candidate stops around the user ────────────────────────────────────
    final candidates = <_CandidateStop>[];
    for (var i = 0; i < data.stops.length; i++) {
      final s = data.stops[i];
      final d = haversineM(lat, lon, s.lat, s.lon);
      if (d > searchRadiusM) continue;
      candidates.add(_CandidateStop(i, d));
    }
    candidates.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    final candidateByStop = <int, _CandidateStop>{
      for (final c in candidates) c.stopIdx: c,
    };

    // ── Realtime feeds ─────────────────────────────────────────────────────
    // Two sources can be present at once and they complement each other:
    //   * the protobuf REST feed carries StopTimeUpdate predictions (per stop),
    //   * the streaming feed carries the freshest vehicle fixes and a
    //     per-vehicle delay but no per-stop predictions.
    // Vehicles are preferred from the stream; predictions always come from the
    // protobuf feed.
    var error = '';
    var restFeed = const RtFeed([]);
    if (rtBytes != null && rtBytes.isNotEmpty) {
      try {
        restFeed = parseRtFeed(rtBytes);
      } catch (e) {
        error = 'RT: $e';
      }
    }
    final streamFeed = rtFeed ?? const RtFeed([]);
    final feed = streamFeed.entities.isEmpty && streamFeed.timestamp == 0
        ? restFeed
        : _merge(restFeed, streamFeed);

    final rtByTrip = <String, List<_RtTripStop>>{};
    final pending = <_PendingVehicle>[];
    final direct = <Vehicle>[];
    final pendingKeys = <String>{};
    var rtArrivalCount = 0;

    // ZET timestamps positions against the feed header rather than "now", and
    // both can be a couple of minutes behind wall clock. Track the newest fix
    // so the UI can be honest about how live the dots really are.
    var newestFix = 0;

    // ZET mostly publishes a single StopTimeUpdate per trip (the stop the
    // vehicle just left / is approaching), not a prediction chain. Store the
    // freshest delay per trip so timetable rows further down the line can be
    // shifted too — otherwise the board silently shows stale schedule times.
    final tripDelay = <int, int>{};

    for (final entity in feed.entities) {
      final vp = entity.vehicle;
      final hasGps =
          vp != null && vp.position.latitude.abs() > 0.001;

      if (hasGps) {
        final tid = vp.trip.tripId;
        final trip = data.tripIdx[tid];
        final routeIdx = trip != null
            ? data.tripRoute[trip]
            : data.routeIdx[vp.trip.routeId];
        if (routeIdx != null) {
          final route = data.routes[routeIdx];
          if (vp.timestamp > newestFix) newestFix = vp.timestamp;
          direct.add(Vehicle(
            routeShortName: route.shortName,
            routeType: route.type,
            lat: vp.position.latitude,
            lon: vp.position.longitude,
            bearing: vp.position.bearing,
            headsign: _headsignFor(trip),
            positionTimestamp: vp.timestamp,
          ));
          if (tid.isNotEmpty) pendingKeys.add(tid);
        }
      }

      final tu = entity.tripUpdate;
      if (tu == null) {
        if (!hasGps && vp != null) {
          pending.add(_PendingVehicle(
              vp.trip.tripId, vp.trip.routeId, vp.position.bearing,
              vp.timestamp));
        }
        continue;
      }

      final tid = tu.trip.tripId;
      final trip = data.tripIdx[tid];
      final pattern = trip != null ? data.patterns[trip] : null;
      final routeIdx = trip != null
          ? data.tripRoute[trip]
          : data.routeIdx[tu.trip.routeId];
      if (routeIdx == null) continue;
      final route = data.routes[routeIdx];
      final headsign = _headsignFor(trip);

      for (final stu in tu.stopTimeUpdates) {
        var stopIdx = data.stopIdx[stu.stopId] ?? -1;
        var pos = -1;
        if (pattern != null) {
          pos = StaticData.indexForSequence(pattern.sequence, stu.stopSequence);
          if (stopIdx < 0 && pos >= 0) stopIdx = pattern.stopIdx[pos];
        }
        if (stopIdx < 0) continue;

        final schedSec =
            pos >= 0 && pattern != null ? pattern.departureSec[pos] : 0;

        // Delay reported for this stop (falls back to time - schedule).
        int? stuDelay = stu.departure?.hasDelay == true
            ? stu.departure!.delay
            : (stu.arrival?.hasDelay == true ? stu.arrival!.delay : null);

        // Board time: absolute departure > absolute arrival > schedule + delay.
        var boardTs = stu.departure?.time ?? 0;
        if (boardTs == 0) boardTs = stu.arrival?.time ?? 0;
        if (boardTs == 0 && schedSec != 0 && stuDelay != null) {
          boardTs = midnightUnix + schedSec + stuDelay;
        }
        if (stuDelay == null && boardTs > 0 && schedSec != 0) {
          stuDelay = boardTs - (midnightUnix + schedSec);
        }
        // Reject the wild values ZET occasionally emits (up to ±2 h).
        if (stuDelay != null && stuDelay.abs() > 1800) stuDelay = null;

        // Vehicle-position time: prefer departure, fall back to board time.
        var depTs = stu.departure?.time ?? 0;
        if (depTs == 0) depTs = stu.arrival?.time ?? 0;
        if (depTs == 0 && schedSec != 0 && stu.departure?.hasDelay == true) {
          depTs = midnightUnix + schedSec + stu.departure!.delay;
        }
        if (depTs == 0) depTs = boardTs;

        if (boardTs > 0) {
          final candidate = candidateByStop[stopIdx];
          if (candidate != null &&
              boardTs >= nowUnix - 30 &&
              boardTs <= nowUnix + horizonSec) {
            candidate.arrivals.add(_Arr(
              route: route.shortName,
              headsign: headsign,
              routeType: route.type,
              time: DateTime.fromMillisecondsSinceEpoch(boardTs * 1000),
              realtime: true,
              delaySec: stuDelay ?? 0,
            ));
            rtArrivalCount++;
          }
        }

        if (depTs > 0) {
          (rtByTrip[tid] ??= <_RtTripStop>[])
              .add(_RtTripStop(stopIdx, depTs));
        }

        // The last update in a TU is the most recent / furthest prediction.
        if (trip != null && stuDelay != null) {
          tripDelay[trip] = stuDelay.clamp(-300, 1200).toInt();
        }
      }

      // Streaming snapshots carry a per-vehicle delay but no stop predictions,
      // so the whole trip inherits it and later timetable rows stay aligned.
      if (tu.stopTimeUpdates.isEmpty && tu.hasDelay && trip != null) {
        tripDelay[trip] = tu.delay.clamp(-300, 1200).toInt();
      }

      if (!hasGps) {
        pending.add(_PendingVehicle(
            tid, tu.trip.routeId, vp?.position.bearing ?? 0));
      }
    }

    for (final list in rtByTrip.values) {
      list.sort((a, b) => a.unixTime.compareTo(b.unixTime));
    }

    // ── Vehicles ───────────────────────────────────────────────────────────
    final vehicles = <Vehicle>[...direct];

    void addPending(_PendingVehicle p) {
      if (p.tripId.isEmpty) return;
      if (!pendingKeys.add(p.tripId)) return;

      final trip = data.tripIdx[p.tripId];
      final pattern = trip != null ? data.patterns[trip] : null;

      var pos = -1;
      final rtStops = rtByTrip[p.tripId];
      if (rtStops != null && rtStops.isNotEmpty) {
        for (var i = 0; i < rtStops.length; i++) {
          if (rtStops[i].unixTime >= nowUnix - 30) {
            pos = i;
            break;
          }
        }
        if (pos < 0) pos = rtStops.length - 1;
      }

      final int stopIdx;
      var nextStopIdx = -1;
      if (pos >= 0) {
        stopIdx = rtStops![pos].stopIdx;
        if (pos + 1 < rtStops.length) nextStopIdx = rtStops[pos + 1].stopIdx;
      } else if (pattern != null && pattern.departureSec.isNotEmpty) {
        final idx = _upperBound(pattern.departureSec, nowSec);
        final cur = (idx - 1).clamp(0, pattern.departureSec.length - 1);
        stopIdx = pattern.stopIdx[cur];
        if (cur + 1 < pattern.stopIdx.length) {
          nextStopIdx = pattern.stopIdx[cur + 1];
        }
      } else {
        return;
      }

      final stop = data.stops[stopIdx];
      var bearing = p.bearing;
      if (bearing.abs() <= 1 && nextStopIdx >= 0) {
        final next = data.stops[nextStopIdx];
        bearing = bearingDeg(stop.lat, stop.lon, next.lat, next.lon);
      }

      final routeIdx = trip != null
          ? data.tripRoute[trip]
          : data.routeIdx[p.routeId];
      if (routeIdx == null) return;
      final route = data.routes[routeIdx];

      vehicles.add(Vehicle(
        routeShortName: route.shortName,
        routeType: route.type,
        lat: stop.lat,
        lon: stop.lon,
        bearing: bearing,
        headsign: _headsignFor(trip),
        positionTimestamp: p.timestamp,
        // No GPS fix: the dot is where the timetable thinks the vehicle is,
        // not where ZET measured it. Shown differently so it never reads live.
        estimated: true,
      ));
    }

    for (final p in pending) {
      addPending(p);
    }

    _enrichBearings(vehicles);

    // ── Arrivals at nearby stops ───────────────────────────────────────────
    var scheduledCount = 0;
    var estimatedCount = 0;
    for (final c in candidates) {
      final stopDeps = data.departures[c.stopIdx];

      // Deduplicate realtime rows (same route + exact time from two platforms).
      final seenRt = <String>{};
      c.arrivals.retainWhere((a) {
        final ts = a.time.millisecondsSinceEpoch ~/ 1000;
        return seenRt.add('${a.route}|$ts');
      });

      final from = StaticData.lowerBound(stopDeps.arrivalSec, nowSec - 60);
      for (var i = from; i < stopDeps.arrivalSec.length; i++) {
        final arrSec = stopDeps.arrivalSec[i];
        if (arrSec > nowSec + horizonSec) break;
        final trip = stopDeps.tripIdx[i];
        final route = data.routes[data.tripRoute[trip]];

        // Shift timetable rows by the delay we learned for this trip. This is
        // what makes the board useful beyond the one stop ZET reports.
        final tripDelta = tripDelay[trip] ?? 0;
        final applyDelay = tripDelta.abs() >= 60;
        final delay = applyDelay ? tripDelta : 0;
        final time = midnight.add(Duration(seconds: arrSec + delay));
        if (time.millisecondsSinceEpoch ~/ 1000 < nowUnix - 60) continue;

        scheduledCount++;
        if (applyDelay) estimatedCount++;
        c.arrivals.add(_Arr(
          route: route.shortName,
          headsign: _headsignFor(trip),
          routeType: route.type,
          time: time,
          realtime: false,
          estimated: applyDelay,
          delaySec: delay,
        ));
      }

      c.arrivals.sort((a, b) => a.time.compareTo(b.time));
    }

    final tramStops = _mergeForMode(candidates, kRouteTypeTram);
    final busStops = _mergeForMode(candidates, kRouteTypeBus);

    final vehicleCount = vehicles.length;
    final tramVehicles = vehicles.where((v) => v.isTram).length;
    final nowUnixForAge = now.millisecondsSinceEpoch ~/ 1000;
    final feedTs = feed.timestamp > 0 ? feed.timestamp : nowUnixForAge;
    final positionAge = newestFix > 0
        ? (feedTs - newestFix).clamp(0, 3600)
        : 0;

    final stats = FeedStats(
      vehicles: vehicleCount,
      vehiclesTram: tramVehicles,
      vehiclesBus: vehicleCount - tramVehicles,
      rtArrivals: rtArrivalCount,
      estimatedArrivals: estimatedCount,
      scheduledArrivals: scheduledCount,
      rtEntities: feed.entities.length,
      staticStops: data.stops.length,
      staticTrips: data.tripIdx.length,
      staticParseMs: data.parseMs,
      refreshMs: sw.elapsedMilliseconds,
      feedTimestamp: feed.timestamp,
      positionAgeSec: positionAge,
    );

    return FeedSnapshot(
      tramStops: tramStops,
      busStops: busStops,
      vehicles: vehicles,
      stats: stats,
      updatedAt: now,
      error: error,
    );
  }

  String _headsignFor(int? trip) {
    if (trip == null) return '';
    final h = data.tripHeadsign[trip];
    return h >= 0 && h < data.headsigns.length ? data.headsigns[h] : '';
  }

  void _enrichBearings(List<Vehicle> vehicles) {
    final next = <String, List<_PrevPos>>{};

    for (var i = 0; i < vehicles.length; i++) {
      final v = vehicles[i];
      var bearing = v.bearing;

      if (bearing.abs() <= 1) {
        final prev = _prevByRoute[v.routeShortName];
        if (prev != null) {
          var best = 250.0;
          for (final p in prev) {
            final d = haversineM(p.lat, p.lon, v.lat, v.lon);
            if (d < best) {
              best = d;
              bearing =
                  d > 8 ? bearingDeg(p.lat, p.lon, v.lat, v.lon) : p.bearing;
            }
          }
        }
      }

      if (bearing != v.bearing) {
        vehicles[i] = v.copyWith(bearing: bearing);
      }

      (next[v.routeShortName] ??= <_PrevPos>[])
          .add(_PrevPos(v.lat, v.lon, bearing));
    }

    _prevByRoute
      ..clear()
      ..addAll(next);
  }

  List<NearbyStop> _mergeForMode(
      List<_CandidateStop> candidates, int routeType) {
    final groups = <String, _MergeBox>{};
    final order = <String>[];

    for (final c in candidates) {
      final arrivals =
          c.arrivals.where((a) => a.routeType == routeType).toList();
      if (arrivals.isEmpty) continue;

      final stop = data.stops[c.stopIdx];
      final key = _normalizeName(stop.name);
      final box = groups[key];
      if (box == null) {
        order.add(key);
        groups[key] = _MergeBox(c.stopIdx, c.distanceM)
          ..arrivals.addAll(arrivals);
      } else {
        if (c.distanceM < box.distanceM) {
          box.stopIdx = c.stopIdx;
          box.distanceM = c.distanceM;
        }
        box.arrivals.addAll(arrivals);
      }
    }

    final out = <NearbyStop>[];
    for (final key in order) {
      if (out.length >= maxStopsPerMode) break;
      final box = groups[key]!;

      // A realtime row supersedes the scheduled row of the same trip. We do not
      // know the trip id of a scheduled row after the merge, so match on
      // route+headsign and closeness in time (3 min). Later departures of the
      // same route are kept — they are different vehicles.
      final rtTimes = <String, List<int>>{};
      for (final a in box.arrivals) {
        if (!a.realtime) continue;
        (rtTimes['${a.route}|${a.headsign}'] ??= <int>[])
            .add(a.time.millisecondsSinceEpoch ~/ 1000);
      }
      if (rtTimes.isNotEmpty) {
        box.arrivals.removeWhere((a) {
          if (a.realtime) return false;
          final times = rtTimes['${a.route}|${a.headsign}'];
          if (times == null) return false;
          final t = a.time.millisecondsSinceEpoch ~/ 1000;
          for (final rt in times) {
            if ((rt - t).abs() <= 180) return true;
          }
          return false;
        });
      }

      box.arrivals.sort((a, b) => a.time.compareTo(b.time));
      final limited = _limitArrivals(box.arrivals);
      if (limited.isEmpty) continue;
      final stop = data.stops[box.stopIdx];
      out.add(NearbyStop(
        stop: StopInfo(
          id: stop.stopId,
          name: stop.name,
          lat: stop.lat,
          lon: stop.lon,
          modes: stop.modes,
        ),
        distanceM: box.distanceM,
        arrivals: [
          for (final a in limited)
            Arrival(
              routeShortName: a.route,
              headsign: a.headsign,
              time: a.time,
              source: a.realtime
                  ? ArrivalSource.realtime
                  : (a.estimated
                      ? ArrivalSource.estimated
                      : ArrivalSource.scheduled),
              routeType: a.routeType,
              delaySec: a.delaySec,
            ),
        ],
      ));
    }
    return out;
  }

  static List<_Arr> _limitArrivals(List<_Arr> sorted) {
    final seen = <String>{};
    final perRouteHeadsign = <String, int>{};
    final out = <_Arr>[];
    for (final a in sorted) {
      if (out.length >= maxArrivalsPerStop) break;
      final exact = '${a.route}|${a.time.millisecondsSinceEpoch}';
      if (!seen.add(exact)) continue;
      final key = '${a.route}|${a.headsign}';
      final count = perRouteHeadsign[key] ?? 0;
      if (count >= maxPerRouteHeadsign) continue;
      perRouteHeadsign[key] = count + 1;
      out.add(a);
    }
    return out;
  }

  static String _normalizeName(String name) =>
      name.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Folds the protobuf predictions and the streamed vehicle fixes into one
  /// feed. Streamed entities win for positions (newest fix) and contribute a
  /// per-trip delay when the protobuf feed has no prediction for that trip.
  static RtFeed _merge(RtFeed restFeed, RtFeed streamFeed) {
    if (restFeed.entities.isEmpty) return streamFeed;
    if (streamFeed.entities.isEmpty) return restFeed;

    final entities = <RtEntity>[...streamFeed.entities];

    final seen = <String>{};
    for (final e in streamFeed.entities) {
      final tid = e.tripUpdate?.trip.tripId ?? e.vehicle?.trip.tripId ?? '';
      if (tid.isNotEmpty) seen.add(tid);
    }

    // Protobuf entities for trips the stream already covers would duplicate
    // vehicles; keep only their predictions by clearing the position.
    for (final e in restFeed.entities) {
      final tid = e.tripUpdate?.trip.tripId ?? e.vehicle?.trip.tripId ?? '';
      if (tid.isNotEmpty && seen.contains(tid)) {
        if (e.tripUpdate != null && e.vehicle == null) {
          entities.add(RtEntity(id: e.id, tripUpdate: e.tripUpdate));
        }
        continue;
      }
      entities.add(e);
    }

    return RtFeed(entities, timestamp: streamFeed.timestamp);
  }

  static int _upperBound(Int32List values, int target) {
    var lo = 0;
    var hi = values.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (values[mid] <= target) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

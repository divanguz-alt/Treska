// Background worker isolate: static GTFS download/parse + realtime polling.
//
// The UI isolate never sees the 112 MB stop_times file, never parses protobuf
// and never sorts schedules. It only receives immutable [FeedSnapshot]s.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'feed_engine.dart';
import 'gtfs_static.dart';
import 'models.dart';

const String _staticUrl = 'https://zet.hr/gtfs-scheduled/latest';
const String _rtUrl = 'https://zet.hr/gtfs-rt-protobuf';
const String _userAgent = 'Treska/2.0 (Flutter; ZET timetable)';

const Duration _rtTimeout = Duration(seconds: 12);
const Duration _staticTimeout = Duration(minutes: 3);
// A cached ZIP younger than this is used at startup without asking ZET.
const Duration _staticMaxAge = Duration(hours: 12);
// A running app asks ZET this often whether the ZIP changed. The request is
// conditional (ETag / Last-Modified), so an unchanged feed costs a 304, not
// 18.8 MB.
const Duration _staticCheckAfter = Duration(hours: 4);

// ── Messages ────────────────────────────────────────────────────────────────

class WorkerInit {
  final String cacheDir;
  const WorkerInit(this.cacheDir);
}

class WorkerRefresh {
  final double lat;
  final double lon;

  /// Nearby-stop radius in metres (400 / 800 / 1200, chosen in Settings).
  final double radiusM;

  /// Stop ids that need a board regardless of distance (selected, favourites).
  final List<String> pinnedStopIds;

  const WorkerRefresh(
    this.lat,
    this.lon, {
    this.radiusM = 800,
    this.pinnedStopIds = const [],
  });
}

class WorkerInvalidateStatic {
  const WorkerInvalidateStatic();
}

/// Asks for the ordered stop timeline of the next trip of [routeShortName] /
/// [headsign] that departs after [afterUnix] and serves [stopId] — used by the
/// arrival-details screen.
class WorkerTripStops {
  final String routeShortName;
  final String headsign;
  final String stopId;
  final int afterUnix;

  /// Correlates the reply with the request; the controller keeps a map.
  final int id;

  const WorkerTripStops({
    required this.routeShortName,
    required this.headsign,
    required this.stopId,
    required this.afterUnix,
    required this.id,
  });
}

class WorkerTripStopsResult {
  final String routeShortName;
  final String headsign;
  final int routeType;
  final int id;

  /// Ordered stops with the scheduled seconds-after-midnight for each.
  final List<TripStop> stops;
  const WorkerTripStopsResult({
    required this.routeShortName,
    required this.headsign,
    required this.routeType,
    required this.stops,
    this.id = 0,
  });
}

class WorkerShape {
  /// GTFS shape id when already known (empty: resolved from trips.txt).
  final String shapeId;

  /// Trip id, used as a fallback when the shape id is missing.
  final String tripId;
  final int id;

  const WorkerShape({
    required this.shapeId,
    required this.tripId,
    required this.id,
  });
}

class WorkerShapeResult {
  final int id;

  /// Flat `[lat, lon, lat, lon, …]` array; empty when no geometry is known.
  final List<double> points;
  const WorkerShapeResult({required this.id, this.points = const []});
}

class WorkerHello {
  final SendPort port;
  const WorkerHello(this.port);
}

class WorkerStaticReady {
  final bool ok;
  final String error;
  final List<StopInfo> stops;
  final int trips;
  final int parseMs;
  final bool fromCache;

  const WorkerStaticReady({
    required this.ok,
    required this.error,
    this.stops = const [],
    this.trips = 0,
    this.parseMs = 0,
    this.fromCache = false,
  });
}

class WorkerFeed {
  final FeedSnapshot snapshot;
  const WorkerFeed(this.snapshot);
}

/// Entry point. Must be a top-level function.
void zetWorkerMain(SendPort handshake) {
  final inbox = ReceivePort();
  handshake.send(WorkerHello(inbox.sendPort));

  StaticData? staticData;
  FeedEngine? engine;
  String zipPath = '';
  final shapeCache = <String, List<double>>{};
  final tripShapeCache = <String, String>{};
  DateTime? checkedAt;
  // Service day the loaded index was built for; a new day means a reparse.
  DateTime? indexDay;
  var staticLoading = false;
  var refreshInFlight = false;
  DateTime? lastStaticAttempt;

  void sendStatic(WorkerStaticReady result) => handshake.send(result);

  /// Resolves route geometry for a tapped vehicle.
  ///
  /// A shape is read from the cached ZIP only once and then kept in a small
  /// LRU-ish cache; trips without a shape in trips.txt fall back to their
  /// stop sequence.
  Future<void> sendShape(WorkerShape message) async {
    var points = const <double>[];
    var shapeId = message.shapeId;

    // REST vehicles have a trip id but no shape id; resolve it from trips.txt.
    if (shapeId.isEmpty && message.tripId.isNotEmpty && zipPath.isNotEmpty) {
      final cachedTrip = tripShapeCache[message.tripId];
      if (cachedTrip != null) {
        shapeId = cachedTrip;
      } else {
        try {
          final resolved = await readTripShapeId(zipPath, message.tripId);
          if (resolved.isNotEmpty) tripShapeCache[message.tripId] = resolved;
          shapeId = resolved;
        } catch (_) {
          // Fall through to the stop-sequence outline.
        }
      }
    }

    if (shapeId.isNotEmpty && zipPath.isNotEmpty) {
      final cached = shapeCache[shapeId];
      if (cached != null) {
        points = cached;
      } else {
        try {
          final parsed = await readShapePoints(zipPath, shapeId);
          if (parsed.isNotEmpty) {
            if (shapeCache.length >= 24) {
              shapeCache.remove(shapeCache.keys.first);
            }
            shapeCache[shapeId] = parsed;
          }
          points = parsed;
        } catch (_) {
          // A corrupt shape must not break the rest of the feed.
        }
      }
    }
    if (points.isEmpty && message.tripId.isNotEmpty) {
      points = engine?.shapeForTrip(message.tripId) ?? const [];
    }
    handshake.send(WorkerShapeResult(id: message.id, points: points));
  }
  
  /// Fetches the static ZIP. Returns false when ZET answered 304 (the cached
  /// copy is current; its mtime is bumped so the age check restarts).
  Future<bool> downloadStatic({bool conditional = true}) async {
    final tmp = File('$zipPath.tmp');
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
    final zip = File(zipPath);
    final validators = File('$zipPath.validators');
    final headers = {
      'User-Agent': _userAgent,
      'Accept': 'application/zip,*/*',
    };
    if (conditional && await zip.exists() && await validators.exists()) {
      try {
        final lines = await validators.readAsLines();
        if (lines.isNotEmpty && lines[0].isNotEmpty) {
          headers['If-None-Match'] = lines[0];
        }
        if (lines.length > 1 && lines[1].isNotEmpty) {
          headers['If-Modified-Since'] = lines[1];
        }
      } catch (_) {}
    }
    final request = http.Request('GET', Uri.parse(_staticUrl))
      ..headers.addAll(headers);
    final response = await request.send().timeout(_staticTimeout);
    if (response.statusCode == 304) {
      await response.stream.drain<void>();
      try {
        await zip.setLastModified(DateTime.now());
      } catch (_) {}
      return false;
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final sink = tmp.openWrite();
    try {
      await response.stream.pipe(sink).timeout(_staticTimeout);
    } catch (_) {
      await sink.close();
      rethrow;
    }
    final length = await tmp.length();
    if (length < 10000) {
      await tmp.delete();
      throw Exception('premali ZIP ($length B)');
    }
    await tmp.rename(zipPath);
    try {
      await validators.writeAsString(
          '${response.headers['etag'] ?? ''}\n'
          '${response.headers['last-modified'] ?? ''}\n');
    } catch (_) {}
    return true;
  }

  /// Makes sure an index for today is loaded. [force] re-downloads
  /// unconditionally (the RASPORED button); [check] asks ZET whether the ZIP
  /// changed even though the cache is still fresh (the periodic check).
  Future<bool> ensureStatic({bool force = false, bool check = false}) async {
    if (staticLoading) return false;
    staticLoading = true;
    lastStaticAttempt = DateTime.now();
    try {
      final file = File(zipPath);
      var needDownload = force || check;
      var fromCache = false;

      if (!needDownload && await file.exists()) {
        final length = await file.length();
        if (length > 10000) {
          final age = DateTime.now().difference(await file.lastModified());
          if (age < _staticMaxAge) {
            needDownload = false;
            fromCache = true;
          } else {
            needDownload = true;
          }
        } else {
          needDownload = true;
        }
      } else if (!needDownload) {
        needDownload = true;
      }

      var changed = force;
      if (needDownload) {
        try {
          changed = await downloadStatic(conditional: !force);
          checkedAt = DateTime.now();
          fromCache = !changed;
        } catch (e) {
          if (!await file.exists() || await file.length() < 10000) {
            sendStatic(WorkerStaticReady(
              ok: false,
              error: 'Preuzimanje rasporeda nije uspjelo: $e',
            ));
            return false;
          }
          // Keep the cached copy and try again at the next periodic check.
          checkedAt = DateTime.now();
          fromCache = true;
        }
      }
      if (changed) {
        shapeCache.clear();
        tripShapeCache.clear();
      }

      // An unchanged ZIP only needs a reparse for a new service day.
      final now = DateTime.now();
      final day = serviceDayStart(now);
      if (staticData != null && !changed && indexDay == day) return true;

      final parsed = await parseStaticZip(zipPath, now);
      staticData = parsed;
      engine = FeedEngine(parsed);
      checkedAt ??= now;
      indexDay = day;

      sendStatic(WorkerStaticReady(
        ok: true,
        error: '',
        stops: [
          for (final s in parsed.stops)
            StopInfo(
              id: s.stopId,
              name: s.name,
              lat: s.lat,
              lon: s.lon,
              modes: s.modes,
            ),
        ],
        trips: parsed.tripIdx.length,
        parseMs: parsed.parseMs,
        fromCache: fromCache,
      ));
      return true;
    } catch (e) {
      // A corrupt cache must not survive to the next attempt.
      try {
        final file = File(zipPath);
        if (await file.exists() && force) await file.delete();
      } catch (_) {}
      sendStatic(WorkerStaticReady(
        ok: false,
        error: 'Raspored nije moguće pročitati: $e',
      ));
      return false;
    } finally {
      staticLoading = false;
    }
  }

  Future<Uint8List?> fetchRealtime(StringBuffer errors) async {
    try {
      final response = await http
          .get(
            Uri.parse(_rtUrl),
            headers: {
              'User-Agent': _userAgent,
              'Cache-Control': 'no-cache',
              'Pragma': 'no-cache',
            },
          )
          .timeout(_rtTimeout);
      if (response.statusCode != 200) {
        errors.write('RT HTTP ${response.statusCode}');
        return null;
      }
      if (response.bodyBytes.length < 100) {
        errors.write('RT prazan odgovor');
        return null;
      }
      return response.bodyBytes;
    } catch (e) {
      errors.write('RT: $e');
      return null;
    }
  }

  Future<void> doRefresh(WorkerRefresh message) async {
    if (refreshInFlight) return;
    refreshInFlight = true;
    try {
      // After midnight the index must switch to the new service day (and
      // carry yesterday's late trips); every few hours, ask ZET whether the
      // timetable changed.
      if (staticData != null && !staticLoading) {
        final now = DateTime.now();
        final dueCheck = checkedAt == null ||
            now.difference(checkedAt!) > _staticCheckAfter;
        if (dueCheck || serviceDayStart(now) != indexDay) {
          await ensureStatic(check: dueCheck);
        }
      }

      if (staticData == null) {
        final throttle = lastStaticAttempt == null ||
            DateTime.now().difference(lastStaticAttempt!) > const Duration(seconds: 20);
        if (throttle) await ensureStatic();
        if (staticData == null) {
          handshake.send(WorkerFeed(FeedSnapshot(
            updatedAt: DateTime.now(),
            error: 'Raspored još nije učitan',
          )));
          return;
        }
      }

      final errors = StringBuffer();

      // One protobuf carries both vehicle fixes and stop predictions.
      final rtBytes = await fetchRealtime(errors);

      final snapshot = engine!.refresh(
        lat: message.lat,
        lon: message.lon,
        radiusM: message.radiusM,
        pinnedStopIds: message.pinnedStopIds.toSet(),
        rtBytes: rtBytes,
        now: DateTime.now(),
      );

      var error = snapshot.error;
      if (rtBytes == null && errors.isNotEmpty) {
        error = error.isEmpty ? errors.toString() : '$error | $errors';
      }

      handshake.send(WorkerFeed(
        error.isEmpty ? snapshot : snapshot.copyWith(error: error),
      ));
    } catch (e) {
      handshake.send(WorkerFeed(FeedSnapshot(
        updatedAt: DateTime.now(),
        error: 'Osvježavanje nije uspjelo: $e',
      )));
    } finally {
      refreshInFlight = false;
    }
  }

  inbox.listen((message) {
    if (message is WorkerInit) {
      zipPath = '${message.cacheDir}/gtfs_static.zip';
      ensureStatic(force: false);
    } else if (message is WorkerRefresh) {
      doRefresh(message);
    } else if (message is WorkerTripStops) {
      final result = engine?.tripStops(
        routeShortName: message.routeShortName,
        headsign: message.headsign,
        stopId: message.stopId,
        afterUnix: message.afterUnix,
        now: DateTime.now(),
      );
      handshake.send(WorkerTripStopsResult(
        routeShortName: message.routeShortName,
        headsign: message.headsign,
        routeType: result?.routeType ?? kRouteTypeBus,
        stops: result?.stops ?? const [],
        id: message.id,
      ));
    } else if (message is WorkerShape) {
      sendShape(message);
    } else if (message is WorkerInvalidateStatic) {
      if (zipPath.isEmpty) return;
      shapeCache.clear();
      tripShapeCache.clear();
      try {
        final file = File(zipPath);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
      staticData = null;
      engine = null;
      ensureStatic(force: true);
    }
  });
}

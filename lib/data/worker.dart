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
import 'gtfs_rt.dart';
import 'gtfs_static.dart';
import 'models.dart';
import 'rt_socket.dart';

const String _staticUrl = 'https://zet.hr/gtfs-scheduled/latest';
const String _rtUrl = 'https://zet.hr/gtfs-rt-protobuf';
const String _userAgent = 'Treska/2.0 (Flutter; ZET timetable)';

const Duration _rtTimeout = Duration(seconds: 12);
const Duration _staticTimeout = Duration(minutes: 3);
const Duration _staticMaxAge = Duration(hours: 12);
const Duration _staticReloadAfter = Duration(hours: 4);

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
  /// GTFS shape id from the streaming relay (empty when unknown).
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
  DateTime? loadedAt;
  String staticWarning = '';
  var staticLoading = false;
  var refreshInFlight = false;
  DateTime? lastStaticAttempt;

  // ── Streaming realtime ────────────────────────────────────────────────────
  // The relay pushes each new feed the moment ZET produces it; the UI isolates
  // never see the socket, they only get the joined snapshot.
  RtFeed? lastWireFeed;
  DateTime? lastPushAt;
  String rtChannel = '';
  WorkerRefresh? lastRefresh;
  RtSocket? socket;

  void sendStatic(WorkerStaticReady result) => handshake.send(result);

  /// Resolves route geometry for a tapped vehicle.
  ///
  /// A shape is read from the cached ZIP only once and then kept in a small
  /// LRU-ish cache; vehicles whose relay payload lacked a shape id fall back to
  /// the trip's stop sequence.
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
  
  Future<void> downloadStatic() async {
    final tmp = File('$zipPath.tmp');
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
    final request = http.Request('GET', Uri.parse(_staticUrl))
      ..headers.addAll({
        'User-Agent': _userAgent,
        'Accept': 'application/zip,*/*',
      });
    final response = await request.send().timeout(_staticTimeout);
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
  }

  Future<bool> ensureStatic({bool force = false}) async {
    if (staticLoading) return false;
    staticLoading = true;
    lastStaticAttempt = DateTime.now();
    try {
      final file = File(zipPath);
      var needDownload = force;
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

      if (needDownload) {
        try {
          await downloadStatic();
          fromCache = false;
        } catch (e) {
          if (!await file.exists() || await file.length() < 10000) {
            sendStatic(WorkerStaticReady(
              ok: false,
              error: 'Preuzimanje rasporeda nije uspjelo: $e',
            ));
            return false;
          }
          staticWarning = 'Keširani raspored (preuzimanje nije uspjelo)';
          fromCache = true;
        }
      }

      final parsed = await parseStaticZip(zipPath, DateTime.now());
      staticData = parsed;
      engine = FeedEngine(parsed);
      loadedAt = DateTime.now();
      staticWarning = '';

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
      // Reload the static feed every few hours so service changes show up.
      if (staticData != null &&
          loadedAt != null &&
          DateTime.now().difference(loadedAt!) > _staticReloadAfter &&
          !staticLoading) {
        await ensureStatic();
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
      if (staticWarning.isNotEmpty) errors.write(staticWarning);

      // Vehicles come from the streaming relay when it is live (newest fix,
      // ~10 s cadence). Stop predictions (StopTimeUpdate) are not part of that
      // stream, so the REST feed still supplies them; it is fetched every
      // refresh and merged in by the engine.
      final pushed = lastWireFeed != null &&
          lastPushAt != null &&
          DateTime.now().difference(lastPushAt!) < const Duration(seconds: 45);

      final rtBytes = await fetchRealtime(errors);
      if (rtBytes != null) rtChannel = pushed ? 'WS+REST' : 'REST';

      final snapshot = engine!.refresh(
        lat: message.lat,
        lon: message.lon,
        radiusM: message.radiusM,
        pinnedStopIds: message.pinnedStopIds.toSet(),
        rtBytes: rtBytes,
        rtFeed: pushed ? lastWireFeed : null,
        now: DateTime.now(),
      );

      var error = snapshot.error;
      if (rtBytes == null && errors.isNotEmpty) {
        error = error.isEmpty ? errors.toString() : '$error | $errors';
      }
      if (staticWarning.isNotEmpty) {
        error = error.isEmpty
            ? staticWarning
            : '$error | $staticWarning';
      }

      final streaming = pushed || socket?.connected == true;
      final withChannel = snapshot.copyWith(
        stats: snapshot.stats.copyWith(
          streaming: streaming,
        ),
      );

      handshake.send(WorkerFeed(
        error.isEmpty ? withChannel : withChannel.copyWith(error: error),
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

  void startSocket() {
    if (socket != null) return;
    socket = RtSocket(
      onError: (e) => rtChannel = rtChannel.isEmpty ? e : rtChannel,
      onFeed: (feed, receivedAt) async {
        lastWireFeed = feed;
        lastPushAt = receivedAt;
        rtChannel = 'WS';
        // Recompute immediately when a static feed is loaded; otherwise the
        // pending refresh will pick the feed up.
        final pending = lastRefresh;
        if (pending != null && staticData != null && !refreshInFlight) {
          await doRefresh(pending);
        }
      },
    );
    socket!.start();
  }

  inbox.listen((message) {
    if (message is WorkerInit) {
      zipPath = '${message.cacheDir}/gtfs_static.zip';
      ensureStatic(force: false);
      startSocket();
    } else if (message is WorkerRefresh) {
      lastRefresh = message;
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

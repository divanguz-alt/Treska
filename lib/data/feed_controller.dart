import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'location_service.dart';
import 'models.dart';
import 'worker.dart';

class FeedStatus {
  final bool staticReady;
  final String loading;
  final String staticError;
  final int stopCount;
  final int tripCount;
  final int parseMs;
  final bool gps;

  const FeedStatus({
    this.staticReady = false,
    this.loading = 'Učitavam raspored…',
    this.staticError = '',
    this.stopCount = 0,
    this.tripCount = 0,
    this.parseMs = 0,
    this.gps = false,
  });

  FeedStatus copyWith({
    bool? staticReady,
    String? loading,
    String? staticError,
    int? stopCount,
    int? tripCount,
    int? parseMs,
    bool? gps,
  }) {
    return FeedStatus(
      staticReady: staticReady ?? this.staticReady,
      loading: loading ?? this.loading,
      staticError: staticError ?? this.staticError,
      stopCount: stopCount ?? this.stopCount,
      tripCount: tripCount ?? this.tripCount,
      parseMs: parseMs ?? this.parseMs,
      gps: gps ?? this.gps,
    );
  }
}

/// Owns the worker isolate and exposes small [ValueNotifier]s.
///
/// Widgets subscribe only to the slice they draw: the map listens to
/// [vehicles]/[stops]/[position], the board to [snapshot], the header to
/// [status]. A refresh therefore never rebuilds the whole screen.
class FeedController with WidgetsBindingObserver {
  static const Duration pollInterval = Duration(seconds: 5);
  static const Duration _requestTimeout = Duration(seconds: 15);

  final ValueNotifier<FeedSnapshot?> snapshot = ValueNotifier(null);
  final ValueNotifier<List<Vehicle>> vehicles = ValueNotifier(const []);
  final ValueNotifier<List<StopInfo>> stops = ValueNotifier(const []);

  /// [stops] by id, rebuilt whenever the stop list changes.
  Map<String, StopInfo> get stopById {
    final list = stops.value;
    if (!identical(list, _stopByIdSource)) {
      _stopByIdSource = list;
      _stopById = {for (final s in list) s.id: s};
    }
    return _stopById;
  }

  List<StopInfo>? _stopByIdSource;
  Map<String, StopInfo> _stopById = const {};
  final ValueNotifier<PositionState> position =
      ValueNotifier(PositionState.fallback);
  final ValueNotifier<FeedStatus> status = ValueNotifier(const FeedStatus());

  final LocationService _location = LocationService();
  final ReceivePort _inbox = ReceivePort();

  Isolate? _isolate;
  SendPort? _worker;
  String _cacheDir = '';
  Timer? _timer;
  Timer? _requestGuard;
  Completer<void>? _manual;
  bool _inFlight = false;
  bool _started = false;
  bool _disposed = false;
  int _lastVehicleSignature = 0;

  /// Nearby-stop radius in metres, driven by Settings (400 / 800 / 1200).
  double radiusM = 800;

  /// Called when the radius changes: the next tick uses the new circle.
  void setRadius(double meters) {
    if (meters == radiusM) return;
    radiusM = meters;
    if (_inFlight) {
      _retickAfterFlight = true;
    } else {
      _tick();
    }
  }

  /// Stops that get a board even outside the radius: the selected stop and the
  /// favourites. Without this a stop picked in search or on the map shows an
  /// empty board as soon as it is further away than [radiusM].
  Set<String> _pinned = const {};

  void setPinnedStops(Set<String> ids) {
    if (setEquals(ids, _pinned)) return;
    _pinned = Set.unmodifiable(ids);
    if (_inFlight) {
      _retickAfterFlight = true;
    } else {
      _tick();
    }
  }

  /// Set when an input changed mid-request, so the answer that comes back is
  /// followed immediately by one that reflects the change.
  bool _retickAfterFlight = false;

  bool get isRunning => _timer != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _inbox.listen(_onMessage);

    try {
      final dir = await getApplicationCacheDirectory();
      _cacheDir = dir.path;
    } catch (e) {
      status.value = status.value.copyWith(
        staticError: 'Ne mogu otvoriti keš: $e',
      );
      _cacheDir = Directory.systemTemp.path;
    }

    try {
      _isolate = await Isolate.spawn(
        zetWorkerMain,
        _inbox.sendPort,
        debugName: 'zet-gtfs-worker',
        onExit: _inbox.sendPort,
        onError: _inbox.sendPort,
      );
    } catch (e) {
      status.value = status.value.copyWith(
        staticError: 'Pozadinski radnik nije pokrenut: $e',
      );
    }

    _startTimer();
  }

  void _onMessage(dynamic message) {
    if (_disposed) return;

    if (message is WorkerHello) {
      _worker = message.port;
      if (_cacheDir.isNotEmpty) {
        _worker!.send(WorkerInit(_cacheDir));
      }
      _tick();
      return;
    }

    if (message is WorkerStaticReady) {
      if (message.ok) {
        stops.value = message.stops;
        status.value = status.value.copyWith(
          staticReady: true,
          loading: '',
          staticError: '',
          stopCount: message.stops.length,
          tripCount: message.trips,
          parseMs: message.parseMs,
        );
        _tick();
      } else {
        status.value = status.value.copyWith(
          staticReady: false,
          loading: '',
          staticError: message.error,
        );
      }
      return;
    }

    if (message is WorkerFeed) {
      _apply(message.snapshot);
      _inFlight = false;
      _requestGuard?.cancel();
      _requestGuard = null;
      final manual = _manual;
      _manual = null;
      if (manual != null && !manual.isCompleted) manual.complete();
      if (_retickAfterFlight) {
        _retickAfterFlight = false;
        _tick();
      }
      return;
    }

    if (message is WorkerTripStopsResult) {
      final completer = _tripRequests.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
      return;
    }

    if (message is WorkerShapeResult) {
      final completer = _shapeRequests.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
      return;
    }

    // Isolate crash (onExit/onError share the inbox).
    if (message is List) {
      status.value = status.value.copyWith(
        staticError: 'Pozadinski radnik je stao. Ponovno pokrećem…',
      );
      _restartWorker();
    }
  }

  void _apply(FeedSnapshot next) {
    snapshot.value = next;

    // Only rebuild the map when a vehicle actually moved.
    var signature = 17;
    for (final v in next.vehicles) {
      signature = signature * 31 +
          v.routeShortName.hashCode +
          (v.lat * 100000).round() +
          (v.lon * 100000).round() * 7 +
          (v.bearing * 10).round() * 13;
    }
    if (signature != _lastVehicleSignature) {
      _lastVehicleSignature = signature;
      vehicles.value = next.vehicles;
    }

    final pos = position.value;
    if (status.value.gps != pos.gps) {
      status.value = status.value.copyWith(gps: pos.gps);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (_disposed || _inFlight || _worker == null) return;
    _inFlight = true;

    final pos = await _location.locate(prompt: true);
    if (_disposed) return;
    if (pos != position.value) {
      position.value = pos;
      if (status.value.gps != pos.gps) {
        status.value = status.value.copyWith(gps: pos.gps);
      }
    }

    _worker!.send(WorkerRefresh(
      pos.lat,
      pos.lon,
      radiusM: radiusM,
      pinnedStopIds: _pinned.toList(growable: false),
    ));

    _requestGuard?.cancel();
    _requestGuard = Timer(_requestTimeout, () {
      _inFlight = false;
      final manual = _manual;
      _manual = null;
      if (manual != null && !manual.isCompleted) manual.complete();
    });
  }

  /// Pull-to-refresh / retry button. Completes when the next feed arrives.
  Future<void> refreshNow() {
    if (_inFlight) {
      final pending = _manual ??= Completer<void>();
      return pending.future;
    }
    final completer = _manual = Completer<void>();
    _tick();
    return completer.future.timeout(const Duration(seconds: 12), onTimeout: () {});
  }

  Future<void> retryStatic() async {
    status.value = status.value.copyWith(
      loading: 'Ponovno preuzimam raspored…',
      staticError: '',
    );
    _worker?.send(const WorkerInvalidateStatic());
  }

  Future<void> retryLocation() async {
    final pos = await _location.retry();
    position.value = pos;
    status.value = status.value.copyWith(gps: pos.gps);
    _tick();
  }

  /// Requests the stop timeline for the next matching trip. Never throws; an
  /// empty list means the details screen shows only the ETA card.
  final Map<int, Completer<WorkerTripStopsResult>> _tripRequests = {};
  int _tripRequestSeq = 0;

  Future<List<TripStop>> tripStopsFor({
    required String routeShortName,
    required String headsign,
    required String stopId,
    required DateTime at,
  }) async {
    final worker = _worker;
    if (worker == null) return const [];
    final id = ++_tripRequestSeq;
    final completer = Completer<WorkerTripStopsResult>();
    _tripRequests[id] = completer;
    worker.send(WorkerTripStops(
      routeShortName: routeShortName,
      headsign: headsign,
      stopId: stopId,
      afterUnix: at.millisecondsSinceEpoch ~/ 1000,
      id: id,
    ));
    try {
      final result = await completer.future
          .timeout(const Duration(seconds: 6), onTimeout: () {
        _tripRequests.remove(id);
        return const WorkerTripStopsResult(
          routeShortName: '',
          headsign: '',
          routeType: kRouteTypeBus,
          stops: [],
        );
      });
      return result.stops;
    } catch (_) {
      _tripRequests.remove(id);
      return const [];
    }
  }

  /// Route geometry for one vehicle, as map points. Empty when the shape is
  /// unknown; the caller then draws nothing rather than a made-up line.
  final Map<int, Completer<WorkerShapeResult>> _shapeRequests = {};
  int _shapeSeq = 0;

  Future<List<LatLng>> shapeFor({
    required String shapeId,
    required String tripId,
  }) async {
    final worker = _worker;
    if (worker == null || (shapeId.isEmpty && tripId.isEmpty)) {
      return const [];
    }
    final id = ++_shapeSeq;
    final completer = Completer<WorkerShapeResult>();
    _shapeRequests[id] = completer;
    worker.send(WorkerShape(shapeId: shapeId, tripId: tripId, id: id));
    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _shapeRequests.remove(id);
          return WorkerShapeResult(id: id);
        },
      );
      final points = <LatLng>[];
      for (var i = 0; i + 1 < result.points.length; i += 2) {
        points.add(LatLng(result.points[i], result.points[i + 1]));
      }
      return points;
    } catch (_) {
      _shapeRequests.remove(id);
      return const [];
    }
  }

  void _restartWorker() {    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _worker = null;
    _inFlight = false;
    Isolate.spawn(
      zetWorkerMain,
      _inbox.sendPort,
      debugName: 'zet-gtfs-worker',
    ).then((isolate) {
      _isolate = isolate;
    }).catchError((Object e) {
      status.value = status.value.copyWith(
        staticError: 'Radnik se ne može pokrenuti: $e',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _tick();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _requestGuard?.cancel();
    _inbox.close();
    _isolate?.kill(priority: Isolate.immediate);
    snapshot.dispose();
    vehicles.dispose();
    stops.dispose();
    position.dispose();
    status.dispose();
  }
}

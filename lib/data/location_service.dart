import 'dart:async';

import 'package:geolocator/geolocator.dart';

class PositionState {
  final double lat;
  final double lon;
  final bool gps;
  const PositionState(this.lat, this.lon, this.gps);

  /// Zagreb main station — used before the first fix and when location is off.
  static const fallback = PositionState(45.8150, 15.9819, false);

  @override
  bool operator ==(Object other) =>
      other is PositionState &&
      other.lat == lat &&
      other.lon == lon &&
      other.gps == gps;

  @override
  int get hashCode => Object.hash(lat, lon, gps);
}

/// Thin wrapper around geolocator with a short cache, so the 5 s refresh loop
/// never blocks on the GPS radio.
///
/// While the app is in front it also listens to the position stream (every
/// 5 m of movement), so walking moves the user's dot and the nearby stops
/// right away. Until 2.1.16 only a one-shot fix every 20 s was taken, and on
/// some phones that kept returning the fix from when the app was opened.
class LocationService {
  /// Called with every new streamed fix.
  void Function(PositionState)? onChange;

  StreamSubscription<Position>? _watch;

  static const Duration _cacheTtl = Duration(seconds: 20);

  PositionState _cached = PositionState.fallback;
  DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _permissionChecked = false;
  bool _granted = false;
  bool _prompted = false;

  PositionState get last => _cached;

  Future<PositionState> locate({bool prompt = false}) async {
    if (DateTime.now().difference(_cachedAt) < _cacheTtl) return _cached;

    if (!await _ensurePermission(prompt: prompt)) {
      _cached = PositionState(_cached.lat, _cached.lon, false);
      return _cached;
    }

    _startWatching();

    // Cheap first guess — returns instantly when Android has a cached fix.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _cachedAt.millisecondsSinceEpoch == 0) {
        _cached = PositionState(last.latitude, last.longitude, true);
      }
    } catch (_) {}

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _cached = PositionState(position.latitude, position.longitude, true);
      _cachedAt = DateTime.now();
      return _cached;
    } catch (_) {
      _cachedAt = DateTime.now();
      return _cached;
    }
  }

  void _startWatching() {
    if (_watch != null) return;
    try {
      _watch = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (p) {
          _cached = PositionState(p.latitude, p.longitude, true);
          _cachedAt = DateTime.now();
          onChange?.call(_cached);
        },
        onError: (Object _) => stopWatching(),
        cancelOnError: true,
      );
    } catch (_) {
      _watch = null;
    }
  }

  /// Stops the position stream (app in the background). The next [locate]
  /// starts it again.
  void stopWatching() {
    _watch?.cancel();
    _watch = null;
  }

  Future<bool> _ensurePermission({required bool prompt}) async {
    if (_permissionChecked) return _granted;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _permissionChecked = true;
        _granted = false;
        return false;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && prompt && !_prompted) {
        _prompted = true;
        permission = await Geolocator.requestPermission();
      }
      _permissionChecked = true;
      _granted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      return _granted;
    } catch (_) {
      _permissionChecked = true;
      _granted = false;
      return false;
    }
  }

  /// Called when the user taps the "GPS" chip: re-check and maybe prompt again.
  Future<PositionState> retry() async {
    stopWatching();
    _permissionChecked = false;
    _prompted = false;
    _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
    return locate(prompt: true);
  }
}

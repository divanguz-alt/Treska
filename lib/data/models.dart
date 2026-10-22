import 'dart:math' as math;

/// Bit flags for the two modes the app knows about.
const int kModeTram = 1;
const int kModeBus = 2;

/// GTFS route_type values used by ZET: 0 = tram, 3 = bus.
const int kRouteTypeTram = 0;
const int kRouteTypeBus = 3;

/// A stop that the map can draw. Parsed once in the worker isolate and sent to
/// the UI as a flat, lightweight object.
class StopInfo {
  final String id;
  final String name;
  final double lat;
  final double lon;

  /// Bit mask of [kModeTram] / [kModeBus].
  final int modes;

  const StopInfo({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.modes,
  });

  bool serves(int mode) => (modes & mode) != 0;
}

class StopInfoList {
  final List<StopInfo> stops;
  const StopInfoList(this.stops);

  List<StopInfo> forMode(int mode) =>
      stops.where((s) => s.serves(mode)).toList(growable: false);
}

enum ArrivalSource { realtime, scheduled }

class Arrival {
  final String routeShortName;
  final String headsign;

  /// Absolute local time of the arrival.
  final DateTime time;
  final ArrivalSource source;
  final int routeType; // 0 = tram, 3 = bus

  const Arrival({
    required this.routeShortName,
    required this.headsign,
    required this.time,
    required this.source,
    required this.routeType,
  });

  bool get isRealtime => source == ArrivalSource.realtime;

  int secondsUntil(DateTime now) => time.difference(now).inSeconds;
  int minutesUntil(DateTime now) {
    final s = secondsUntil(now);
    return s <= 0 ? 0 : (s + 59) ~/ 60;
  }
}

class NearbyStop {
  final StopInfo stop;
  final double distanceM;
  final List<Arrival> arrivals;

  const NearbyStop({
    required this.stop,
    required this.distanceM,
    required this.arrivals,
  });
}

class Vehicle {
  final String routeShortName;
  final int routeType;
  final double lat;
  final double lon;
  final double bearing;
  final String headsign;

  const Vehicle({
    required this.routeShortName,
    required this.routeType,
    required this.lat,
    required this.lon,
    required this.bearing,
    required this.headsign,
  });

  bool get isTram => routeType == kRouteTypeTram;
  bool get isMoving => bearing.abs() > 1;
}

class FeedStats {
  final int vehicles;
  final int vehiclesTram;
  final int vehiclesBus;
  final int rtArrivals;
  final int scheduledArrivals;
  final int rtEntities;
  final int staticStops;
  final int staticTrips;
  final int staticParseMs;
  final int refreshMs;

  const FeedStats({
    this.vehicles = 0,
    this.vehiclesTram = 0,
    this.vehiclesBus = 0,
    this.rtArrivals = 0,
    this.scheduledArrivals = 0,
    this.rtEntities = 0,
    this.staticStops = 0,
    this.staticTrips = 0,
    this.staticParseMs = 0,
    this.refreshMs = 0,
  });

  FeedStats copyWith({
    int? vehicles,
    int? vehiclesTram,
    int? vehiclesBus,
    int? rtArrivals,
    int? scheduledArrivals,
    int? rtEntities,
    int? staticStops,
    int? staticTrips,
    int? staticParseMs,
    int? refreshMs,
  }) {
    return FeedStats(
      vehicles: vehicles ?? this.vehicles,
      vehiclesTram: vehiclesTram ?? this.vehiclesTram,
      vehiclesBus: vehiclesBus ?? this.vehiclesBus,
      rtArrivals: rtArrivals ?? this.rtArrivals,
      scheduledArrivals: scheduledArrivals ?? this.scheduledArrivals,
      rtEntities: rtEntities ?? this.rtEntities,
      staticStops: staticStops ?? this.staticStops,
      staticTrips: staticTrips ?? this.staticTrips,
      staticParseMs: staticParseMs ?? this.staticParseMs,
      refreshMs: refreshMs ?? this.refreshMs,
    );
  }
}

/// Immutable result of one refresh cycle.
class FeedSnapshot {
  final List<NearbyStop> tramStops;
  final List<NearbyStop> busStops;
  final List<Vehicle> vehicles;
  final FeedStats stats;
  final DateTime updatedAt;
  final String error;

  const FeedSnapshot({
    this.tramStops = const [],
    this.busStops = const [],
    this.vehicles = const [],
    this.stats = const FeedStats(),
    required this.updatedAt,
    this.error = '',
  });

  FeedSnapshot copyWith({
    List<NearbyStop>? tramStops,
    List<NearbyStop>? busStops,
    List<Vehicle>? vehicles,
    FeedStats? stats,
    DateTime? updatedAt,
    String? error,
  }) {
    return FeedSnapshot(
      tramStops: tramStops ?? this.tramStops,
      busStops: busStops ?? this.busStops,
      vehicles: vehicles ?? this.vehicles,
      stats: stats ?? this.stats,
      updatedAt: updatedAt ?? this.updatedAt,
      error: error ?? this.error,
    );
  }
}

// ── Geometry ────────────────────────────────────────────────────────────────

const double kEarthRadiusM = 6371000.0;

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLon = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) *
          math.cos(lat2 * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * kEarthRadiusM * math.asin(math.sqrt(a));
}

double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final dLon = (lon2 - lon1) * math.pi / 180;
  final lat1r = lat1 * math.pi / 180;
  final lat2r = lat2 * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2r);
  final x = math.cos(lat1r) * math.sin(lat2r) -
      math.sin(lat1r) * math.cos(lat2r) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

// ── Formatting ──────────────────────────────────────────────────────────────

String two(int n) => n.toString().padLeft(2, '0');

String hhmmss(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String distanceLabel(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

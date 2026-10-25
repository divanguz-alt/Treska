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

/// Name key that platforms of one stop share ("Draškovićeva" has several
/// stop ids, one per platform/direction).
String stopGroupKey(String name) =>
    name.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

/// Platforms of the same stop: same name and close together. The distance cap
/// keeps unrelated stops that merely share a name in other parts of the city
/// apart.
const double kStopGroupRadiusM = 400;

bool sameStopGroup(StopInfo a, StopInfo b) =>
    a.id == b.id ||
    (stopGroupKey(a.name) == stopGroupKey(b.name) &&
        haversineM(a.lat, a.lon, b.lat, b.lon) <= kStopGroupRadiusM);

class StopInfoList {
  final List<StopInfo> stops;
  const StopInfoList(this.stops);

  List<StopInfo> forMode(int mode) =>
      stops.where((s) => s.serves(mode)).toList(growable: false);
}

enum ArrivalSource {
  /// Position/time straight from the GTFS-Realtime feed.
  realtime,

  /// Schedule shifted by the delay ZET currently reports for the same trip.
  estimated,

  /// Untouched timetable.
  scheduled,
}

class Arrival {
  final String routeShortName;
  final String headsign;

  /// Absolute local time of the arrival.
  final DateTime time;
  final ArrivalSource source;
  final int routeType; // 0 = tram, 3 = bus

  /// Current delay of the trip in seconds (positive = late). Only meaningful
  /// for [ArrivalSource.realtime] and [ArrivalSource.estimated].
  final int delaySec;

  const Arrival({
    required this.routeShortName,
    required this.headsign,
    required this.time,
    required this.source,
    required this.routeType,
    this.delaySec = 0,
  });

  bool get isRealtime => source == ArrivalSource.realtime;
  bool get isEstimated => source == ArrivalSource.estimated;

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

/// One stop on a trip's timeline, used by the arrival-details screen.
class TripStop {
  final String stopId;
  final String name;
  final double lat;
  final double lon;

  /// Scheduled time on this trip (absolute local time, may be "next day" for
  /// services that run past midnight).
  final DateTime time;
  final bool passed;

  const TripStop({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.time,
    required this.passed,
  });
}

/// The ordered timelime of one trip, plus the route type the badge needs.
class TripTimeline {
  final int routeType;
  final List<TripStop> stops;

  const TripTimeline({required this.routeType, required this.stops});
}

class Vehicle {
  final String routeShortName;
  final int routeType;
  final double lat;
  final double lon;
  final double bearing;
  final String headsign;

  /// Unix seconds of the last position ZET measured for this vehicle (0 when
  /// unknown). Together with [FeedStats.feedTimestamp] it drives the staleness
  /// label so the map never pretends a 2-minute-old dot is live.
  final int positionTimestamp;

  /// True when the coordinates were derived from the timetable instead of a
  /// GPS report ZET published.
  final bool estimated;

  /// GTFS trip id, when the feed identified the trip. Used to look up the
  /// vehicle's route geometry when the user taps its badge.
  final String tripId;

  /// GTFS shape id of the trip. The streaming relay sends this with every
  /// vehicle, so tapping a badge can draw the exact road/track the vehicle
  /// follows instead of a straight line between stops.
  final String shapeId;

  const Vehicle({
    required this.routeShortName,
    required this.routeType,
    required this.lat,
    required this.lon,
    required this.bearing,
    required this.headsign,
    this.positionTimestamp = 0,
    this.estimated = false,
    this.tripId = '',
    this.shapeId = '',
  });

  bool get isTram => routeType == kRouteTypeTram;
  bool get isMoving => bearing.abs() > 1;

  Vehicle copyWith({
    double? lat,
    double? lon,
    double? bearing,
    String? headsign,
  }) {
    return Vehicle(
      routeShortName: routeShortName,
      routeType: routeType,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      bearing: bearing ?? this.bearing,
      headsign: headsign ?? this.headsign,
      positionTimestamp: positionTimestamp,
      estimated: estimated,
      tripId: tripId,
      shapeId: shapeId,
    );
  }
}

class FeedStats {
  /// Vehicles with a real GPS fix — the ones the map draws.
  final int vehicles;
  final int vehiclesTram;
  final int vehiclesBus;

  /// Trips that have predictions but no GPS fix. Not drawn; shown so the
  /// diagnostics can explain the gap between the feed and the map.
  final int estimatedVehicles;

  final int rtArrivals;
  final int estimatedArrivals;
  final int scheduledArrivals;
  final int rtEntities;
  final int staticStops;
  final int staticTrips;
  final int staticParseMs;
  final int refreshMs;

  /// Feed header timestamp in unix seconds (0 when unknown).
  final int feedTimestamp;

  /// Seconds between the newest vehicle fix and the feed timestamp.
  final int positionAgeSec;

  /// True while updates arrive over the streaming channel.
  final bool streaming;

  const FeedStats({
    this.vehicles = 0,
    this.vehiclesTram = 0,
    this.vehiclesBus = 0,
    this.estimatedVehicles = 0,
    this.rtArrivals = 0,
    this.estimatedArrivals = 0,
    this.scheduledArrivals = 0,
    this.rtEntities = 0,
    this.staticStops = 0,
    this.staticTrips = 0,
    this.staticParseMs = 0,
    this.refreshMs = 0,
    this.feedTimestamp = 0,
    this.positionAgeSec = 0,
    this.streaming = false,
  });

  FeedStats copyWith({
    int? vehicles,
    int? vehiclesTram,
    int? vehiclesBus,
    int? estimatedVehicles,
    int? rtArrivals,
    int? estimatedArrivals,
    int? scheduledArrivals,
    int? rtEntities,
    int? staticStops,
    int? staticTrips,
    int? staticParseMs,
    int? refreshMs,
    int? feedTimestamp,
    int? positionAgeSec,
    bool? streaming,
  }) {
    return FeedStats(
      vehicles: vehicles ?? this.vehicles,
      vehiclesTram: vehiclesTram ?? this.vehiclesTram,
      vehiclesBus: vehiclesBus ?? this.vehiclesBus,
      estimatedVehicles: estimatedVehicles ?? this.estimatedVehicles,
      rtArrivals: rtArrivals ?? this.rtArrivals,
      estimatedArrivals: estimatedArrivals ?? this.estimatedArrivals,
      scheduledArrivals: scheduledArrivals ?? this.scheduledArrivals,
      rtEntities: rtEntities ?? this.rtEntities,
      staticStops: staticStops ?? this.staticStops,
      staticTrips: staticTrips ?? this.staticTrips,
      staticParseMs: staticParseMs ?? this.staticParseMs,
      refreshMs: refreshMs ?? this.refreshMs,
      feedTimestamp: feedTimestamp ?? this.feedTimestamp,
      positionAgeSec: positionAgeSec ?? this.positionAgeSec,
      streaming: streaming ?? this.streaming,
    );
  }

  /// How old the newest vehicle fix is, counted from "now" rather than from the
  /// feed header, so a stalled feed keeps growing instead of freezing.
  int ageSecAt(DateTime now) {
    if (feedTimestamp <= 0) return positionAgeSec;
    final headerAge = now.millisecondsSinceEpoch ~/ 1000 - feedTimestamp;
    return (headerAge + positionAgeSec).clamp(0, 86400);
  }
}

/// Immutable result of one refresh cycle.
class FeedSnapshot {
  final List<NearbyStop> tramStops;
  final List<NearbyStop> busStops;

  /// Vehicles with a real GPS fix. Trip-update-only positions are kept apart in
  /// [estimatedVehicles] so the map never draws a dot nobody reported.
  final List<Vehicle> vehicles;
  final List<Vehicle> estimatedVehicles;
  final FeedStats stats;
  final DateTime updatedAt;
  final String error;

  /// Radius the nearby-stop search used, in metres. The map draws its circle
  /// from this so the ring always matches the list.
  final double radiusM;

  /// Boards for stops the UI asked for explicitly (the selected stop and the
  /// favourites), whether or not they are inside [radiusM]. Each carries the
  /// requested stop id and arrivals of every mode; the board filters by mode.
  final List<NearbyStop> pinnedStops;

  const FeedSnapshot({
    this.tramStops = const [],
    this.busStops = const [],
    this.pinnedStops = const [],
    this.vehicles = const [],
    this.estimatedVehicles = const [],
    this.stats = const FeedStats(),
    required this.updatedAt,
    this.error = '',
    this.radiusM = 800,
  });

  FeedSnapshot copyWith({
    List<NearbyStop>? tramStops,
    List<NearbyStop>? busStops,
    List<Vehicle>? vehicles,
    List<Vehicle>? estimatedVehicles,
    FeedStats? stats,
    DateTime? updatedAt,
    String? error,
    double? radiusM,
    List<NearbyStop>? pinnedStops,
  }) {
    return FeedSnapshot(
      tramStops: tramStops ?? this.tramStops,
      busStops: busStops ?? this.busStops,
      pinnedStops: pinnedStops ?? this.pinnedStops,
      vehicles: vehicles ?? this.vehicles,
      estimatedVehicles: estimatedVehicles ?? this.estimatedVehicles,
      stats: stats ?? this.stats,
      updatedAt: updatedAt ?? this.updatedAt,
      error: error ?? this.error,
      radiusM: radiusM ?? this.radiusM,
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

/// Origin of GTFS schedule times for the service day containing [now].
///
/// GTFS measures stop times from "noon minus 12 h", not from midnight. The two
/// agree on ordinary days, but on a DST change day local midnight is an hour
/// off, and every timetable time computed from it would shift by an hour.
DateTime serviceDayStart(DateTime now) =>
    DateTime(now.year, now.month, now.day, 12)
        .subtract(const Duration(hours: 12));

String two(int n) => n.toString().padLeft(2, '0');

String hhmmss(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';

String hhmm(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String distanceLabel(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

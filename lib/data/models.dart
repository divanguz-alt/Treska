import 'dart:math' as math;

/// Bit flags for the two modes the app knows about.
const int kModeTram = 1;
const int kModeBus = 2;

/// GTFS route_type values used by ZET: 0 = tram, 3 = bus.
const int kRouteTypeTram = 0;
const int kRouteTypeBus = 3;

/// A stop that the map can draw. Parsed once in the worker isolate and sent to
/// the UI as a flat, lightweight object.
/// A stop picked in search; [mode] is set when the pick names a mode (a saved
/// favourite), otherwise the current tab decides.
typedef StopPick = ({String id, int? mode});

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

  /// [kModeTram] / [kModeBus] bits of the vehicles in [arrivals]; falls back
  /// to the platform's own modes while the stop has no departures listed.
  int get arrivalModes {
    var modes = 0;
    for (final a in arrivals) {
      modes |= a.routeType == kRouteTypeTram ? kModeTram : kModeBus;
      if (modes == kModeTram | kModeBus) break;
    }
    return modes == 0 ? stop.modes : modes;
  }

  /// Distinct lines of [mode] at this stop (the number in a filter chip).
  int lineCount(int mode) => {
        for (final a in arrivals)
          if ((a.routeType == kRouteTypeTram) == (mode == kModeTram))
            a.routeShortName,
      }.length;

  /// This stop with only the arrivals of the [modes] bits.
  NearbyStop onlyModes(int modes) {
    if (modes == kModeTram | kModeBus) return this;
    final tram = modes == kModeTram;
    return NearbyStop(
      stop: stop,
      distanceM: distanceM,
      arrivals: [
        for (final a in arrivals)
          if ((a.routeType == kRouteTypeTram) == tram) a,
      ],
    );
  }
}

/// One board per stop for both modes: the engine merges platforms per mode,
/// so the tram and bus platforms of one stop (same name, within
/// [kStopGroupRadiusM]) are joined here. Arrivals are time-ordered, stops
/// nearest first.
List<NearbyStop> combineModes(List<NearbyStop> trams, List<NearbyStop> buses) {
  final out = <NearbyStop>[...trams];
  for (final b in buses) {
    final i = out.indexWhere((s) => sameStopGroup(s.stop, b.stop));
    if (i < 0) {
      out.add(b);
      continue;
    }
    final t = out[i];
    final closer = b.distanceM < t.distanceM ? b : t;
    out[i] = NearbyStop(
      stop: closer.stop,
      distanceM: closer.distanceM,
      arrivals: [...t.arrivals, ...b.arrivals]
        ..sort((x, y) => x.time.compareTo(y.time)),
    );
  }
  out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
  return out;
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

  /// GTFS shape id of the trip when known up front. Empty for ZET's feed: the
  /// worker resolves it from trips.txt via [tripId] when a badge is tapped.
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

  /// A GPS fix older than this reads as stale („Podaci kasne“).
  static const int staleAfterSec = 75;

  /// Seconds over [staleAfterSec] it takes to fade fully to grey.
  static const int staleFadeSec = 15;

  /// False when ZET's timestamp cannot be a measurement time: missing, or
  /// more than 10 s in the future. Timetable-placed vehicles have none.
  bool get hasValidTimestamp => positionTimestamp > 0;

  /// Seconds since ZET measured this position, or null when the timestamp is
  /// unusable.
  int? ageSec(DateTime now) {
    if (!hasValidTimestamp) return null;
    final age = now.millisecondsSinceEpoch ~/ 1000 - positionTimestamp;
    return age < -10 ? null : math.max(0, age);
  }

  /// 0 for a fresh fix, rising smoothly to 1 between 75 and 90 s of age (and
  /// 1 for an unusable timestamp): how far the badge fades to grey. Always 0
  /// for [estimated] vehicles, which are dimmed their own way.
  double staleness(DateTime now) {
    if (estimated) return 0;
    final age = ageSec(now);
    if (age == null) return 1;
    final t = ((age - staleAfterSec) / staleFadeSec).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

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

  /// Where the last realtime protobuf came from ('push', 'relay', 'zet.hr', or '').
  final String rtSource;

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
    this.rtSource = '',
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
    String? rtSource,
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
      rtSource: rtSource ?? this.rtSource,
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

/// „2 min 10 s“, „1 h 3 min“, „45 s“: a span of [seconds], largest units
/// first, zero parts left out.
String spanLabel(int seconds) {
  final d = seconds ~/ 86400;
  final h = seconds % 86400 ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = seconds % 60;
  final parts = [
    if (d > 0) '$d d',
    if (h > 0) '$h h',
    if (m > 0) '$m min',
  ];
  if (s > 0 || parts.isEmpty) parts.add('$s s');
  return parts.join(' ');
}

/// What the tapped vehicle's card says about an old fix, or null while the
/// fix is fresh: „Podaci kasne: 2 min 10 s“.
String? staleLabel(Vehicle v, DateTime now) {
  if (v.estimated) return null;
  final age = v.ageSec(now);
  if (age == null) return 'Neispravno vrijeme podataka';
  if (age <= Vehicle.staleAfterSec) return null;
  return 'Podaci kasne: ${spanLabel(age)}';
}

String distanceLabel(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

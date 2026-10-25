// Compact, immutable index over the ZET GTFS static feed.
//
// Design goals (this is where ZET 1 spent most of its memory and CPU):
//   * never materialise stop_times.txt (112 MB) as a String — stream it;
//   * store per-stop and per-trip rows in Int32List instead of objects/maps;
//   * filter to the trips that actually run today while parsing, plus
//     yesterday's trips that are still running after midnight;
//   * expose O(log n) lookups for the two questions the UI asks:
//       "what departs from this stop in the next hour?"
//       "where is this trip right now?"
import 'dart:convert';
import 'dart:typed_data';

import 'models.dart';
import 'zip.dart';

class StopRecord {
  final String stopId;
  final String name;
  final double lat;
  final double lon;

  /// Bit mask of [kModeTram] / [kModeBus]; filled after stop_times are read.
  int modes = 0;

  StopRecord({
    required this.stopId,
    required this.name,
    required this.lat,
    required this.lon,
  });
}

class RouteRecord {
  final String routeId;
  final String shortName;
  final int type;
  const RouteRecord({
    required this.routeId,
    required this.shortName,
    required this.type,
  });
}

/// One trip's stops in stop_sequence order.
class TripPattern {
  final Int32List stopIdx;
  final Int32List sequence;
  final Int32List departureSec; // seconds after midnight, may exceed 86400
  const TripPattern({
    required this.stopIdx,
    required this.sequence,
    required this.departureSec,
  });
}

/// Departures from one stop, sorted by scheduled arrival.
class StopDepartures {
  final Int32List tripIdx;
  final Int32List arrivalSec;
  const StopDepartures(this.tripIdx, this.arrivalSec);
  static final empty = StopDepartures(Int32List(0), Int32List(0));
}

class StaticData {
  final List<StopRecord> stops;
  final Map<String, int> stopIdx;
  final List<RouteRecord> routes;
  final Map<String, int> routeIdx;
  final List<String> headsigns;
  final Map<String, int> tripIdx; // only trips active today

  /// Yesterday's trips that run past midnight (GTFS times of 24:00 and later),
  /// keyed by trip id. Their times are shifted onto today's service day, so a
  /// 25:10 departure reads 01:10. The same id can be in both maps: ZET reuses
  /// a service on consecutive weekdays, so the realtime `start_date` decides.
  final Map<String, int> carryTripIdx;

  /// Yesterday's date as `YYYYMMDD`, the `start_date` of [carryTripIdx] trips.
  final String carryDate;
  final Int32List tripRoute;
  final Int32List tripHeadsign;
  final List<TripPattern> patterns;
  final List<StopDepartures> departures;
  final int parseMs;

  const StaticData({
    required this.stops,
    required this.stopIdx,
    required this.routes,
    required this.routeIdx,
    required this.headsigns,
    required this.tripIdx,
    this.carryTripIdx = const {},
    this.carryDate = '',
    required this.tripRoute,
    required this.tripHeadsign,
    required this.patterns,
    required this.departures,
    required this.parseMs,
  });

  /// Resolves a realtime trip id to a trip index. [startDate] (`YYYYMMDD`
  /// from the realtime trip descriptor) picks yesterday's run of an id that
  /// runs on both days; without it, yesterday's run wins while it is still
  /// within half an hour of its last stop at [nowSec].
  int? tripFor(String tripId, {String startDate = '', int? nowSec}) {
    final carry = carryTripIdx[tripId];
    final today = tripIdx[tripId];
    if (carry == null) return today;
    if (today == null) return carry;
    if (startDate.isNotEmpty) return startDate == carryDate ? carry : today;
    if (nowSec == null) return today;
    final dep = patterns[carry].departureSec;
    return dep.isNotEmpty && nowSec <= dep[dep.length - 1] + 1800
        ? carry
        : today;
  }

  /// Index of the pattern position whose stop_sequence equals [sequence],
  /// or -1. Sequences are ascending in a GTFS stop_times row order.
  static int indexForSequence(Int32List sequences, int sequence) {
    var lo = 0;
    var hi = sequences.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final value = sequences[mid];
      if (value == sequence) return mid;
      if (value < sequence) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// First index in [arrivalSec] with value >= [sec].
  static int lowerBound(Int32List arrivalSec, int sec) {
    var lo = 0;
    var hi = arrivalSec.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (arrivalSec[mid] < sec) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

// ── Parsing ────────────────────────────────────────────────────────────────

/// Parses [zipPath]. Runs on the worker isolate.
Future<StaticData> parseStaticZip(String zipPath, DateTime day) async {
  final sw = Stopwatch()..start();
  final zip = await ZipSource.open(zipPath);
  try {
    // Yesterday's trips with times past 24:00 are still running after
    // midnight; they join today's index shifted by the length of yesterday's
    // service day (86 400 s, or ±3 600 s across a DST change).
    final prevDay = DateTime(day.year, day.month, day.day - 1, 12);
    final carryShift =
        serviceDayStart(day).difference(serviceDayStart(prevDay)).inSeconds;
    final activeServices = await _readActiveServices(zip, day);
    final carryServices = await _readActiveServices(zip, prevDay);

    final stopsRaw = await _readText(zip, 'stops.txt');
    final routesRaw = await _readText(zip, 'routes.txt');
    final tripsRaw = await _readText(zip, 'trips.txt');

    final stops = _parseStops(stopsRaw);
    final stopIdx = <String, int>{
      for (var i = 0; i < stops.length; i++) stops[i].stopId: i,
    };

    final routes = _parseRoutes(routesRaw);
    final routeIdx = <String, int>{
      for (var i = 0; i < routes.length; i++) routes[i].routeId: i,
    };

    final headsigns = <String>[];
    final headsignIdx = <String, int>{};

    final tripIdxMap = <String, int>{};
    final carryIdxMap = <String, int>{};
    final rawRoute = <int>[];
    final rawHeadsign = <int>[];

    _parseActiveTrips(
      tripsRaw,
      activeServices,
      carryServices,
      routeIdx,
      headsigns,
      headsignIdx,
      tripIdxMap,
      carryIdxMap,
      rawRoute,
      rawHeadsign,
    );

    final rawCount = rawRoute.length;
    final rawStops = List<List<int>?>.filled(rawCount, null);
    final rawSeq = List<List<int>?>.filled(rawCount, null);
    final rawArr = List<List<int>?>.filled(rawCount, null);
    final rawDep = List<List<int>?>.filled(rawCount, null);

    final entry = zip.entry('stop_times.txt');
    if (entry != null) {
      await _parseStopTimes(
        zip,
        entry,
        stopIdx,
        tripIdxMap,
        carryIdxMap,
        carryShift,
        rawStops,
        rawSeq,
        rawArr,
        rawDep,
      );
    }

    // Drop trips without rows and carried trips that ended before midnight
    // (most of yesterday), then renumber densely.
    final carried = <int>{...carryIdxMap.values};
    final newIndex = Int32List(rawCount)..fillRange(0, rawCount, -1);
    final kept = <int>[];
    for (var t = 0; t < rawCount; t++) {
      final arr = rawArr[t];
      if (arr == null || arr.isEmpty) continue;
      if (carried.contains(t) && arr.reduce((a, b) => a > b ? a : b) < 0) {
        continue;
      }
      newIndex[t] = kept.length;
      kept.add(t);
    }
    Map<String, int> renumber(Map<String, int> map) => {
          for (final e in map.entries)
            if (newIndex[e.value] >= 0) e.key: newIndex[e.value],
        };
    final todayTrips = renumber(tripIdxMap);
    final carryTrips = renumber(carryIdxMap);
    final tripCount = kept.length;
    final tripRouteList = [for (final t in kept) rawRoute[t]];
    final tripHeadsignList = [for (final t in kept) rawHeadsign[t]];
    final stopBuilders = [for (final t in kept) rawStops[t]];
    final seqBuilders = [for (final t in kept) rawSeq[t]];
    final arrBuilders = [for (final t in kept) rawArr[t]];
    final depBuilders = [for (final t in kept) rawDep[t]];

    // Convert per-trip lists to compact typed arrays.
    final patterns = List<TripPattern>.filled(tripCount, _emptyPattern,
        growable: false);
    for (var t = 0; t < tripCount; t++) {
      final s = stopBuilders[t];
      if (s == null || s.isEmpty) continue;
      final seq = seqBuilders[t]!;
      if (!_ascending(seq)) {
        final order = List<int>.generate(seq.length, (i) => i)
          ..sort((a, b) => seq[a].compareTo(seq[b]));
        patterns[t] = TripPattern(
          stopIdx: Int32List.fromList([for (final i in order) s[i]]),
          sequence: Int32List.fromList([for (final i in order) seq[i]]),
          departureSec:
              Int32List.fromList([for (final i in order) depBuilders[t]![i]]),
        );
        _reorderInPlace(arrBuilders[t]!, order);
        _reorderInPlace(stopBuilders[t]!, order);
      } else {
        patterns[t] = TripPattern(
          stopIdx: Int32List.fromList(s),
          sequence: Int32List.fromList(seq),
          departureSec: Int32List.fromList(depBuilders[t]!),
        );
      }
      // Fill mode masks once, while patterns are hot.
      final type = routes[tripRouteList[t]].type;
      final mode = type == kRouteTypeTram ? kModeTram : kModeBus;
      final stopIndices = patterns[t].stopIdx;
      for (var i = 0; i < stopIndices.length; i++) {
        stops[stopIndices[i]].modes |= mode;
      }
    }

    // Per-stop departure index. Pack (arrivalSec, tripIdx) into one int so a
    // plain sort keeps the pair aligned; both ranges fit comfortably in 64 bits.
    // Carried trips have negative times before midnight: the arithmetic shift
    // below restores the sign and the low 20 bits still hold the trip.
    final perStop = List<List<int>?>.filled(stops.length, null);
    for (var t = 0; t < tripCount; t++) {
      final arr = arrBuilders[t];
      if (arr == null || arr.isEmpty) continue;
      final stopList = stopBuilders[t]!;
      for (var i = 0; i < stopList.length; i++) {
        (perStop[stopList[i]] ??= <int>[]).add((arr[i] << 20) | t);
      }
    }

    final departures = List<StopDepartures>.filled(
        stops.length, StopDepartures.empty,
        growable: false);
    for (var s = 0; s < stops.length; s++) {
      final packed = perStop[s];
      if (packed == null || packed.isEmpty) continue;
      packed.sort();
      final n = packed.length;
      final trips = Int32List(n);
      final arr = Int32List(n);
      for (var i = 0; i < n; i++) {
        final v = packed[i];
        trips[i] = v & 0xFFFFF;
        arr[i] = v >> 20;
      }
      departures[s] = StopDepartures(trips, arr);
    }

    return StaticData(
      stops: stops,
      stopIdx: stopIdx,
      routes: routes,
      routeIdx: routeIdx,
      headsigns: headsigns,
      tripIdx: todayTrips,
      carryTripIdx: carryTrips,
      carryDate: _yyyymmdd(prevDay),
      tripRoute: Int32List.fromList(tripRouteList),
      tripHeadsign: Int32List.fromList(tripHeadsignList),
      patterns: patterns,
      departures: departures,
      parseMs: sw.elapsedMilliseconds,
    );
  } finally {
    await zip.close();
  }
}

final _emptyPattern = TripPattern(
  stopIdx: Int32List(0),
  sequence: Int32List(0),
  departureSec: Int32List(0),
);

/// Reads one shape's coordinates from `shapes.txt`, streaming the entry so the
/// whole file never becomes a String.
///
/// Called on demand when the user taps a vehicle badge, and cached by the
/// worker: only the shapes actually looked at are ever held in memory.
/// Resolves `trip_id → shape_id` from `trips.txt`, streaming the entry.
///
/// ZET's vehicles carry a trip but no shape id. This lookup lets them draw the
/// real track instead of a straight line between stops.
Future<String> readTripShapeId(String zipPath, String tripId) async {
  if (tripId.isEmpty) return '';
  final zip = await ZipSource.open(zipPath);
  try {
    final entry = zip.entry('trips.txt');
    if (entry == null) return '';

    var headerSeen = false;
    var iTrip = -1, iShape = -1;
    var found = '';

    final splitter = ByteLineSplitter((b, start, end) {
      if (end <= start || found.isNotEmpty) return;
      if (!headerSeen) {
        headerSeen = true;
        final header = csvRow(String.fromCharCodes(b, start, end));
        iTrip = header.indexOf('trip_id');
        iShape = header.indexOf('shape_id');
        return;
      }
      if (iTrip < 0 || iShape < 0) return;

      var field = 0;
      var pos = start;
      var tripStart = -1, tripEnd = -1;
      var shapeStart = -1, shapeEnd = -1;
      while (true) {
        final comma = nextComma(b, pos, end);
        if (field == iTrip) {
          tripStart = pos;
          tripEnd = comma;
        } else if (field == iShape) {
          shapeStart = pos;
          shapeEnd = comma;
        }
        if (comma >= end) break;
        pos = comma + 1;
        field++;
      }
      if (tripStart < 0 || shapeStart < 0) return;
      if (fieldString(b, tripStart, tripEnd) != tripId) return;
      found = fieldString(b, shapeStart, shapeEnd);
    });

    await for (final chunk in zip.stream(entry)) {
      splitter.add(chunk);
      if (found.isNotEmpty) break;
    }
    splitter.finish();
    return found;
  } finally {
    await zip.close();
  }
}

Future<List<double>> readShapePoints(String zipPath, String shapeId) async {  if (shapeId.isEmpty) return const [];
  final zip = await ZipSource.open(zipPath);
  try {
    final entry = zip.entry('shapes.txt');
    if (entry == null) return const [];

    var headerSeen = false;
    var iShape = -1, iLat = -1, iLon = -1;
    final points = <double>[];

    final splitter = ByteLineSplitter((b, start, end) {
      if (end <= start) return;
      if (!headerSeen) {
        headerSeen = true;
        final header = csvRow(String.fromCharCodes(b, start, end));
        iShape = header.indexOf('shape_id');
        iLat = header.indexOf('shape_pt_lat');
        iLon = header.indexOf('shape_pt_lon');
        return;
      }
      if (iShape < 0 || iLat < 0 || iLon < 0) return;

      var field = 0;
      var pos = start;
      var shapeStart = -1, shapeEnd = -1;
      var latStart = -1, latEnd = -1;
      var lonStart = -1, lonEnd = -1;
      while (true) {
        final comma = nextComma(b, pos, end);
        if (field == iShape) {
          shapeStart = pos;
          shapeEnd = comma;
        } else if (field == iLat) {
          latStart = pos;
          latEnd = comma;
        } else if (field == iLon) {
          lonStart = pos;
          lonEnd = comma;
        }
        if (comma >= end) break;
        pos = comma + 1;
        field++;
      }
      if (shapeStart < 0 || latStart < 0 || lonStart < 0) return;
      if (fieldString(b, shapeStart, shapeEnd) != shapeId) return;

      final lat = parseByteDouble(b, latStart, latEnd);
      final lon = parseByteDouble(b, lonStart, lonEnd);
      if (lat == null || lon == null) return;
      points
        ..add(lat)
        ..add(lon);
    });

    await for (final chunk in zip.stream(entry)) {
      splitter.add(chunk);
    }
    splitter.finish();
    return points;
  } finally {
    await zip.close();
  }
}

bool _ascending(List<int> values) {
  for (var i = 1; i < values.length; i++) {
    if (values[i] < values[i - 1]) return false;
  }
  return true;
}

void _reorderInPlace(List<int> values, List<int> order) {
  final copy = List<int>.of(values);
  for (var i = 0; i < order.length; i++) {
    values[i] = copy[order[i]];
  }
}

Future<String> _readText(ZipSource zip, String name) async {
  final entry = zip.entry(name);
  if (entry == null) return '';
  final bytes = await zip.readAll(entry);
  return utf8.decode(bytes, allowMalformed: true)
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
}

Set<String> _activeServices(String calendar, String calendarDates,
    String today, int weekday) {
  final active = <String>{};
  const dayNames = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  if (calendar.isNotEmpty) {
    final lines = calendar.split('\n');
    if (lines.length > 1) {
      final header = csvRow(lines[0]);
      final iService = header.indexOf('service_id');
      final iStart = header.indexOf('start_date');
      final iEnd = header.indexOf('end_date');
      final iDay = header.indexOf(dayNames[weekday - 1]);
      if (iService >= 0 && iDay >= 0) {
        for (var i = 1; i < lines.length; i++) {
          final row = csvRow(lines[i]);
          if (row.length <= iService) continue;
          if (row.length <= iDay || row[iDay] != '1') continue;
          final start = iStart >= 0 && iStart < row.length ? row[iStart] : '';
          final end = iEnd >= 0 && iEnd < row.length ? row[iEnd] : '';
          if (start.isEmpty || today.compareTo(start) < 0) continue;
          if (end.isNotEmpty && today.compareTo(end) > 0) continue;
          active.add(row[iService]);
        }
      }
    }
  }

  if (calendarDates.isNotEmpty) {
    final lines = calendarDates.split('\n');
    if (lines.length > 1) {
      final header = csvRow(lines[0]);
      final iService = header.indexOf('service_id');
      final iDate = header.indexOf('date');
      final iType = header.indexOf('exception_type');
      for (var i = 1; i < lines.length; i++) {
        final row = csvRow(lines[i]);
        if (iService >= 0 && row.length <= iService) continue;
        if (iDate >= 0 &&
            iDate < row.length &&
            row[iDate] != today) {
          continue;
        }
        if (iType < 0 || iType >= row.length) continue;
        if (row[iType] == '1') active.add(row[iService]);
        if (row[iType] == '2') active.remove(row[iService]);
      }
    }
  }
  return active;
}

Future<Set<String>> _readActiveServices(ZipSource zip, DateTime day) async {
  final calendar = await _readText(zip, 'calendar.txt');
  final calendarDates = await _readText(zip, 'calendar_dates.txt');
  return _activeServices(calendar, calendarDates, _yyyymmdd(day), day.weekday);
}

String _yyyymmdd(DateTime day) =>
    '${day.year}${_pad2(day.month)}${_pad2(day.day)}';

String _pad2(int v) => v.toString().padLeft(2, '0');

List<StopRecord> _parseStops(String raw) {
  final out = <StopRecord>[];
  if (raw.isEmpty) return out;
  final lines = raw.split('\n');
  if (lines.length < 2) return out;
  final header = csvRow(lines[0]);
  final iId = header.indexOf('stop_id');
  final iName = header.indexOf('stop_name');
  final iLat = header.indexOf('stop_lat');
  final iLon = header.indexOf('stop_lon');
  if (iId < 0 || iName < 0 || iLat < 0 || iLon < 0) return out;

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iLon) continue;
    final lat = double.tryParse(row[iLat]) ?? 0;
    final lon = double.tryParse(row[iLon]) ?? 0;
    if (lat == 0 || lon == 0) continue;
    out.add(StopRecord(
      stopId: row[iId],
      name: row[iName],
      lat: lat,
      lon: lon,
    ));
  }
  return out;
}

List<RouteRecord> _parseRoutes(String raw) {
  final out = <RouteRecord>[];
  if (raw.isEmpty) return out;
  final lines = raw.split('\n');
  if (lines.length < 2) return out;
  final header = csvRow(lines[0]);
  final iId = header.indexOf('route_id');
  final iShort = header.indexOf('route_short_name');
  final iType = header.indexOf('route_type');
  if (iId < 0) return out;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iId) continue;
    final type =
        iType >= 0 && iType < row.length ? int.tryParse(row[iType]) ?? 3 : 3;
    final short =
        iShort >= 0 && iShort < row.length ? row[iShort] : row[iId];
    out.add(RouteRecord(routeId: row[iId], shortName: short, type: type));
  }
  return out;
}

/// Assigns a trip index to every trip running today ([tripIdxMap]) and,
/// separately, to every trip of yesterday ([carryIdxMap]); an id running on
/// both days gets two indices.
void _parseActiveTrips(
  String raw,
  Set<String> activeServices,
  Set<String> carryServices,
  Map<String, int> routeIdx,
  List<String> headsigns,
  Map<String, int> headsignIdx,
  Map<String, int> tripIdxMap,
  Map<String, int> carryIdxMap,
  List<int> tripRouteList,
  List<int> tripHeadsignList,
) {
  if (raw.isEmpty) return;
  final lines = raw.split('\n');
  if (lines.length < 2) return;
  final header = csvRow(lines[0]);
  final iTrip = header.indexOf('trip_id');
  final iRoute = header.indexOf('route_id');
  final iService = header.indexOf('service_id');
  final iHead = header.indexOf('trip_headsign');
  if (iTrip < 0 || iRoute < 0 || iService < 0) return;

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty) continue;
    final row = csvRow(line);
    if (row.length <= iService || row.length <= iRoute) continue;
    final today = activeServices.contains(row[iService]);
    final carry = carryServices.contains(row[iService]);
    if (!today && !carry) continue;
    final route = routeIdx[row[iRoute]];
    if (route == null) continue;
    final headsign = iHead >= 0 && iHead < row.length ? row[iHead] : '';
    final hIdx = headsign.isEmpty
        ? -1
        : (headsignIdx[headsign] ??= _addHeadsign(headsigns, headsign));
    for (final map in [if (today) tripIdxMap, if (carry) carryIdxMap]) {
      map[row[iTrip]] = tripRouteList.length;
      tripRouteList.add(route);
      tripHeadsignList.add(hIdx);
    }
  }
}

int _addHeadsign(List<String> headsigns, String value) {
  headsigns.add(value);
  return headsigns.length - 1;
}

/// Streams stop_times.txt and keeps only rows of trips active today, plus
/// yesterday's rows shifted back by [carryShift] seconds.
///
/// The trip_id column repeats for every row of a trip, so it is compared as raw
/// bytes against the previous row and only decoded when it changes. That avoids
/// ~1.4 million throw-away Strings in the common case.
Future<void> _parseStopTimes(
  ZipSource zip,
  ZipEntryInfo entry,
  Map<String, int> stopIdx,
  Map<String, int> tripIdx,
  Map<String, int> carryIdx,
  int carryShift,
  List<List<int>?> stopBuilders,
  List<List<int>?> seqBuilders,
  List<List<int>?> arrBuilders,
  List<List<int>?> depBuilders,
) async {
  var headerSeen = false;
  var iTrip = 0, iArr = 1, iDep = 2, iStop = 3, iSeq = 4;

  var prevStart = -1, prevEnd = -1;
  var prevTrip = -1;
  var prevCarry = -1;
  final prevBytes = Uint8List(64);
  var prevLen = 0;

  final splitter = ByteLineSplitter((b, start, end) {
    if (end <= start) return;
    if (!headerSeen) {
      headerSeen = true;
      final header = csvRow(String.fromCharCodes(b, start, end));
      final t = header.indexOf('trip_id');
      final a = header.indexOf('arrival_time');
      final d = header.indexOf('departure_time');
      final s = header.indexOf('stop_id');
      final q = header.indexOf('stop_sequence');
      if (t < 0 || s < 0 || (a < 0 && d < 0)) return;
      iTrip = t;
      iArr = a;
      iDep = d;
      iStop = s;
      iSeq = q;
      return;
    }

    // Locate the needed columns in one pass.
    var field = 0;
    var tripS = -1, tripE = -1;
    var arrS = -1, arrE = -1;
    var depS = -1, depE = -1;
    var stopS = -1, stopE = -1;
    var seqS = -1, seqE = -1;

    var pos = start;
    while (true) {
      final comma = nextComma(b, pos, end);
      if (field == iTrip) {
        tripS = pos;
        tripE = comma;
      }
      if (field == iArr) {
        arrS = pos;
        arrE = comma;
      }
      if (field == iDep) {
        depS = pos;
        depE = comma;
      }
      if (field == iStop) {
        stopS = pos;
        stopE = comma;
      }
      if (field == iSeq) {
        seqS = pos;
        seqE = comma;
      }
      if (comma >= end) break;
      pos = comma + 1;
      field++;
    }

    if (tripS < 0 || stopS < 0) return;

    // Fast path: same trip_id as the previous row.
    var trip = -1;
    var carry = -1;
    final tripLen = tripE - tripS;
    if (prevEnd >= 0 &&
        tripLen == prevEnd - prevStart &&
        tripLen <= prevBytes.length &&
        _sameBytes(b, tripS, prevBytes, 0, tripLen)) {
      trip = prevTrip;
      carry = prevCarry;
    } else {
      final id = fieldString(b, tripS, tripE);
      trip = tripIdx[id] ?? -1;
      carry = carryIdx[id] ?? -1;
      prevTrip = trip;
      prevCarry = carry;
      prevStart = 0;
      prevEnd = tripLen;
      prevLen = tripLen < prevBytes.length ? tripLen : prevBytes.length;
      if (prevLen > 0) prevBytes.setRange(0, prevLen, b, tripS);
    }
    if (trip < 0 && carry < 0) return;

    final stopId = fieldString(b, stopS, stopE);
    final stop = stopIdx[stopId];
    if (stop == null) return;

    final arr = arrS >= 0 ? _timeSec(b, arrS, arrE) : 0;
    final dep = depS >= 0 ? _timeSec(b, depS, depE) : arr;
    final arrSec = arr != 0 ? arr : dep;
    if (arrSec == 0) return;
    final seq = seqS >= 0 ? parseByteInt(b, seqS, seqE) ?? 0 : 0;

    final depSec = dep != 0 ? dep : arrSec;
    void add(int t, int shift) {
      (stopBuilders[t] ??= <int>[]).add(stop);
      (seqBuilders[t] ??= <int>[]).add(seq);
      (arrBuilders[t] ??= <int>[]).add(arrSec - shift);
      (depBuilders[t] ??= <int>[]).add(depSec - shift);
    }

    if (trip >= 0) add(trip, 0);
    if (carry >= 0) add(carry, carryShift);
  });

  await for (final chunk in zip.stream(entry)) {
    splitter.add(chunk);
  }
  splitter.finish();
}

bool _sameBytes(Uint8List a, int aStart, Uint8List prev, int prevStart, int len) {
  for (var i = 0; i < len; i++) {
    if (a[aStart + i] != prev[prevStart + i]) return false;
  }
  return true;
}

/// "HH:MM:SS" bytes → seconds after midnight. Hours may exceed 23 (GTFS allows
/// trips after midnight, e.g. 25:10:00).
int _timeSec(Uint8List b, int start, int end) {
  var s = start;
  var e = end;
  if (s < e && b[s] == 34) s++;
  if (e > s && b[e - 1] == 34) e--;
  var colons = 0;
  var h = 0, m = 0, sec = 0;
  var value = 0;
  for (var i = s; i < e; i++) {
    final c = b[i];
    if (c == 58) {
      if (colons == 0) {
        h = value;
      } else if (colons == 1) {
        m = value;
      }
      colons++;
      value = 0;
    } else if (c >= 48 && c <= 57) {
      value = value * 10 + (c - 48);
    }
  }
  sec = value;
  if (colons != 2) return 0;
  return h * 3600 + m * 60 + sec;
}

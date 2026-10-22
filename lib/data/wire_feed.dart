// Vehicle positions decoded straight off the streaming relay.
//
// The relay used by zet.skoljka.org pushes *decoded* state over its WebSocket
// rather than the raw protobuf:
//
//   {"timestamp": <unix>,
//    "activeStaticKey": "<hash>",
//    "vehicles": {
//      "routeIds": [...], "shapeIds": [...], "vehicleIds": [...],
//      "tripIds": [...], "blockIds": [...],
//      "timestamps": [<seconds before feed timestamp>...],
//      "reportDelays": [...], "directionDegrees": [...],
//      "compressedLats": [[<delta um>...]...], "compressedLons": [...]}}
//
// Coordinates are integer micro-degree deltas around Zagreb (45.815, 15.9819).
// We decode them and let the worker resolve trip ids against whichever static
// feed is loaded locally, so route/headsign naming stays self-contained instead
// of trusting per-vehicle labels from the relay.
import 'dart:convert';

import 'gtfs_rt.dart';

const double _refLat = 45.815;
const double _refLon = 15.9819;

/// Returns null when the payload is not a vehicle snapshot.
RtFeed? parseWireFeed(String json) {
  if (!json.contains('"vehicles"')) return null;

  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final rawVehicles = decoded['vehicles'];
  if (rawVehicles is! Map) return null;

  final feedTimestamp = _int(decoded['timestamp']);
  final routeIds = _list(rawVehicles['routeIds']);
  final shapeIds = _list(rawVehicles['shapeIds']);
  final tripIds = _list(rawVehicles['tripIds']);
  final reportDelays = _list(rawVehicles['reportDelays']);
  final directionDegrees = _list(rawVehicles['directionDegrees']);
  final timestamps = _list(rawVehicles['timestamps']);
  final lats = _list(rawVehicles['compressedLats']);
  final lons = _list(rawVehicles['compressedLons']);

  final count = routeIds.length;
  if (count == 0 || lats.length != count || lons.length != count) return null;

  final entities = <RtEntity>[];
  for (var i = 0; i < count; i++) {
    final lat = _decode(_refLat, lats[i]);
    final lon = _decode(_refLon, lons[i]);
    if (lat == null || lon == null) continue;

    final tripId = i < tripIds.length ? '${tripIds[i]}' : '';
    final shapeId = i < shapeIds.length ? '${shapeIds[i]}' : '';
    final routeId = '${routeIds[i]}';

    // The relay reports each vehicle's age relative to the feed timestamp; a
    // negative value means the fix is ahead of the feed (clock skew), which we
    // treat as "just now".
    var age = i < timestamps.length ? _intAt(timestamps, i) : 0;
    if (age < 0) age = 0;
    final delay = i < reportDelays.length ? _intAt(reportDelays, i) : 0;
    final bearing =
        i < directionDegrees.length ? _doubleAt(directionDegrees, i) : 0.0;

    entities.add(RtEntity(
      id: tripId.isEmpty ? '$routeId#$i' : tripId,
      vehicle: RtVehiclePosition(
        trip: RtTripDescriptor(tripId: tripId, routeId: routeId),
        position: RtPosition(
          latitude: lat,
          longitude: lon,
          bearing: bearing,
        ),
        timestamp: feedTimestamp - age,
      ),
      // ZET ships no predictions in this snapshot, so the board keeps using the
      // delay carried per vehicle instead of per stop.
      tripUpdate: RtTripUpdate(
        trip: RtTripDescriptor(tripId: tripId, routeId: routeId),
        stopTimeUpdates: const [],
        delay: delay,
        hasDelay: i < reportDelays.length && reportDelays[i] != null,
        shapeId: shapeId,
      ),
    ));
  }

  return RtFeed(entities, timestamp: feedTimestamp);
}

/// Decodes one delta-encoded coordinate array (micro-degrees accumulated).
double? _decode(double reference, Object? list) {
  if (list is! List || list.isEmpty) return null;
  var acc = 0;
  for (final value in list) {
    acc += _int(value);
  }
  return reference + acc * 1e-6;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return 0;
}

int _intAt(List<Object?> list, int i) => _int(list[i]);

double _doubleAt(List<Object?> list, int i) {
  final value = list[i];
  if (value is num) return value.toDouble();
  return 0;
}

// Minimal GTFS-Realtime protobuf reader — hand-written, no protoc / codegen.
//
// The reader never throws on malformed input: it stops at the first bad field
// and returns everything parsed so far. That keeps the app alive when ZET
// publishes a truncated feed.
import 'dart:convert';
import 'dart:typed_data';

class RtFeed {
  final List<RtEntity> entities;
  const RtFeed(this.entities);
}

class RtEntity {
  final String id;
  final RtVehiclePosition? vehicle;
  final RtTripUpdate? tripUpdate;
  const RtEntity({required this.id, this.vehicle, this.tripUpdate});
}

class RtTripDescriptor {
  final String tripId;
  final String routeId;
  const RtTripDescriptor({this.tripId = '', this.routeId = ''});
}

class RtPosition {
  final double latitude;
  final double longitude;
  final double bearing;
  const RtPosition({
    required this.latitude,
    required this.longitude,
    this.bearing = 0,
  });
}

class RtVehiclePosition {
  final RtTripDescriptor trip;
  final RtPosition position;
  final int currentStopSequence;
  final String currentStopId;
  const RtVehiclePosition({
    required this.trip,
    required this.position,
    this.currentStopSequence = 0,
    this.currentStopId = '',
  });
}

class RtStopTimeEvent {
  final int time; // absolute unix seconds, 0 when absent
  final int delay; // seconds relative to schedule
  final bool hasDelay;
  const RtStopTimeEvent({this.time = 0, this.delay = 0, this.hasDelay = false});
}

class RtStopTimeUpdate {
  final String stopId;
  final int stopSequence;
  final RtStopTimeEvent? arrival;
  final RtStopTimeEvent? departure;
  const RtStopTimeUpdate({
    this.stopId = '',
    this.stopSequence = 0,
    this.arrival,
    this.departure,
  });
}

class RtTripUpdate {
  final RtTripDescriptor trip;
  final List<RtStopTimeUpdate> stopTimeUpdates;
  const RtTripUpdate({required this.trip, required this.stopTimeUpdates});
}

// ── Cursor ──────────────────────────────────────────────────────────────────

class _Reader {
  final Uint8List b;
  int p = 0;

  _Reader(this.b);

  bool get more => p < b.length;
  bool _canRead(int n) => p + n <= b.length;

  int byte() => more ? b[p++] : 0;

  int varint() {
    var result = 0;
    var shift = 0;
    for (var i = 0; i < 10; i++) {
      if (!more) break;
      final x = byte();
      result |= (x & 0x7F) << shift;
      if ((x & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Protobuf int32 with negative values encoded as 10-byte varints.
  int svarint() {
    final v = varint();
    final low = v & 0xFFFFFFFF;
    if (low > 0x7FFFFFFF) return low - 0x100000000;
    return low;
  }

  Uint8List ld() {
    final len = varint();
    if (len == 0) return Uint8List(0);
    if (len < 0 || !_canRead(len)) {
      p = b.length;
      return Uint8List(0);
    }
    final slice = Uint8List.sublistView(b, p, p + len);
    p += len;
    return slice;
  }

  String str() {
    final bytes = ld();
    return bytes.isEmpty ? '' : utf8.decode(bytes, allowMalformed: true);
  }

  double f32() {
    if (!_canRead(4)) {
      p = b.length;
      return 0;
    }
    final v = ByteData.sublistView(b, p, p + 4).getFloat32(0, Endian.little);
    p += 4;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        p = _canRead(8) ? p + 8 : b.length;
      case 2:
        ld();
      case 5:
        p = _canRead(4) ? p + 4 : b.length;
    }
  }

  _Reader sub() => _Reader(ld());
}

// ── Messages ────────────────────────────────────────────────────────────────

RtTripDescriptor _trip(_Reader r) {
  var tripId = '';
  var routeId = '';
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        tripId = r.str();
      case 5:
        routeId = r.str();
      default:
        r.skip(wire);
    }
  }
  return RtTripDescriptor(tripId: tripId, routeId: routeId);
}

RtPosition _position(_Reader r) {
  var lat = 0.0;
  var lon = 0.0;
  var bearing = 0.0;
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        lat = r.f32();
      case 2:
        lon = r.f32();
      case 3:
        bearing = r.f32();
      default:
        r.skip(wire);
    }
  }
  return RtPosition(latitude: lat, longitude: lon, bearing: bearing);
}

RtVehiclePosition _vehicle(_Reader r) {
  var trip = const RtTripDescriptor();
  var position = const RtPosition(latitude: 0, longitude: 0);
  var sequence = 0;
  var stopId = '';
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        trip = _trip(r.sub());
      case 3:
        position = _position(r.sub());
      case 4:
        sequence = r.varint();
      case 5:
        stopId = r.str();
      default:
        r.skip(wire);
    }
  }
  return RtVehiclePosition(
    trip: trip,
    position: position,
    currentStopSequence: sequence,
    currentStopId: stopId,
  );
}

RtStopTimeEvent _event(_Reader r) {
  var time = 0;
  var delay = 0;
  var hasDelay = false;
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        delay = r.svarint();
        hasDelay = true;
      case 2:
        time = r.varint();
      default:
        r.skip(wire);
    }
  }
  return RtStopTimeEvent(time: time, delay: delay, hasDelay: hasDelay);
}

RtStopTimeUpdate _stopTimeUpdate(_Reader r) {
  var sequence = 0;
  var stopId = '';
  RtStopTimeEvent? arrival;
  RtStopTimeEvent? departure;
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        sequence = r.varint();
      case 2:
        arrival = _event(r.sub());
      case 3:
        departure = _event(r.sub());
      case 4:
        stopId = r.str();
      default:
        r.skip(wire);
    }
  }
  return RtStopTimeUpdate(
    stopId: stopId,
    stopSequence: sequence,
    arrival: arrival,
    departure: departure,
  );
}

RtTripUpdate _tripUpdate(_Reader r) {
  var trip = const RtTripDescriptor();
  final updates = <RtStopTimeUpdate>[];
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        trip = _trip(r.sub());
      case 2:
        updates.add(_stopTimeUpdate(r.sub()));
      default:
        r.skip(wire);
    }
  }
  return RtTripUpdate(trip: trip, stopTimeUpdates: updates);
}

RtEntity _entity(_Reader r) {
  var id = '';
  RtVehiclePosition? vehicle;
  RtTripUpdate? tripUpdate;
  while (r.more) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch (field) {
      case 1:
        id = r.str();
      case 3:
        tripUpdate = _tripUpdate(r.sub());
      case 4:
        vehicle = _vehicle(r.sub());
      default:
        r.skip(wire);
    }
  }
  return RtEntity(id: id, vehicle: vehicle, tripUpdate: tripUpdate);
}

/// Parses a GTFS-RT `FeedMessage` binary payload.
RtFeed parseRtFeed(Uint8List data) {
  final r = _Reader(data);
  final entities = <RtEntity>[];
  try {
    while (r.more) {
      final tag = r.varint();
      final field = tag >> 3;
      final wire = tag & 7;
      switch (field) {
        case 1:
          r.sub(); // FeedHeader — not needed
        case 2:
          entities.add(_entity(r.sub()));
        default:
          r.skip(wire);
      }
    }
  } catch (_) {
    // Return the entities parsed before the malformed field.
  }
  return RtFeed(entities);
}

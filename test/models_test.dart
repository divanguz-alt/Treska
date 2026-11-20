import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/models.dart';

void main() {
  group('geometry', () {
    test('haversine matches a known Zagreb distance', () {
      // Glavni kolodvor → Črnomerec, roughly 4.0 km.
      final d = haversineM(45.8049, 15.9785, 45.8150, 15.9349);
      expect(d, greaterThan(3000));
      expect(d, lessThan(5000));
    });

    test('bearing points east for a due-east pair', () {
      final b = bearingDeg(45.8, 15.9, 45.8, 16.1);
      expect(b, closeTo(90, 1));
    });
  });

  group('service day', () {
    test('schedule origin is local noon minus 12 h', () {
      final start = serviceDayStart(DateTime(2026, 10, 22, 17, 30));
      expect(start.add(const Duration(hours: 12)), DateTime(2026, 10, 22, 12));
    });

    test('a DST change day is not anchored at local midnight', () {
      // 25 Oct 2026 is the end of summer time in Europe. Only meaningful when
      // the test machine's zone observes it (CI may run in UTC).
      final dstDay =
          DateTime(2026, 10, 25, 12).timeZoneOffset !=
          DateTime(2026, 10, 24, 12).timeZoneOffset;
      final start = serviceDayStart(DateTime(2026, 10, 25, 8));
      final midnight = DateTime(2026, 10, 25);
      expect(start.difference(midnight).inMinutes.abs(), dstDay ? 60 : 0);
    });
  });

  group('arrival countdown', () {
    final now = DateTime(2026, 10, 22, 17, 30, 0);

    Arrival make(Duration offset) => Arrival(
      routeShortName: '17',
      headsign: 'Prečko',
      time: now.add(offset),
      source: ArrivalSource.realtime,
      routeType: kRouteTypeTram,
    );

    test('rounds up to the next minute', () {
      expect(make(const Duration(seconds: 61)).minutesUntil(now), 2);
      expect(make(const Duration(seconds: 60)).minutesUntil(now), 1);
      expect(make(const Duration(seconds: 1)).minutesUntil(now), 1);
    });

    test('never returns negative minutes', () {
      expect(make(const Duration(seconds: -30)).minutesUntil(now), 0);
    });
  });

  test('mode bit flags', () {
    const stop = StopInfo(
      id: '1',
      name: 'Test',
      lat: 45.8,
      lon: 15.9,
      modes: kModeTram | kModeBus,
    );
    expect(stop.serves(kModeTram), isTrue);
    expect(stop.serves(kModeBus), isTrue);

    const tramOnly = StopInfo(
      id: '2',
      name: 'Test 2',
      lat: 45.8,
      lon: 15.9,
      modes: kModeTram,
    );
    expect(tramOnly.serves(kModeTram), isTrue);
    expect(tramOnly.serves(kModeBus), isFalse);
  });

  test('formatting helpers', () {
    expect(two(7), '07');
    expect(hhmmss(DateTime(2026, 1, 2, 3, 4, 5)), '03:04:05');
    expect(hhmm(DateTime(2026, 1, 2, 23, 59)), '23:59');
    expect(distanceLabel(420), '420 m');
    expect(distanceLabel(1250), '1.3 km');
  });

  group('vehicle data age (like zet.skoljka.org)', () {
    final now = DateTime.utc(2026, 11, 20, 17, 0);
    final nowSec = now.millisecondsSinceEpoch ~/ 1000;
    Vehicle at(int ageSec, {bool estimated = false, int? ts}) => Vehicle(
      routeShortName: '17',
      routeType: kRouteTypeTram,
      lat: 45.8,
      lon: 15.9,
      bearing: 90,
      headsign: 'Prečko',
      positionTimestamp: ts ?? nowSec - ageSec,
      estimated: estimated,
    );

    test('fresh fixes stay in colour and say nothing', () {
      expect(at(20).staleness(now), 0);
      expect(at(75).staleness(now), 0);
      expect(staleLabel(at(75), now), isNull);
    });

    test('fades to grey between 75 and 90 s, smoothly', () {
      final mid = at(82).staleness(now);
      expect(mid, greaterThan(0.3));
      expect(mid, lessThan(0.7));
      expect(at(90).staleness(now), 1);
      expect(at(600).staleness(now), 1);
    });

    test('the card counts the age up', () {
      expect(staleLabel(at(130), now), 'Podaci kasne: 2 min 10 s');
      expect(staleLabel(at(3720), now), 'Podaci kasne: 1 h 2 min');
      expect(staleLabel(at(76), now), 'Podaci kasne: 1 min 16 s');
    });

    test('an unusable timestamp is grey and says so', () {
      final none = at(0, ts: 0);
      expect(none.staleness(now), 1);
      expect(staleLabel(none, now), 'Neispravno vrijeme podataka');
      final future = at(0, ts: nowSec + 60);
      expect(staleLabel(future, now), 'Neispravno vrijeme podataka');
      // A few seconds ahead is clock skew, not an error.
      expect(staleLabel(at(0, ts: nowSec + 5), now), isNull);
    });

    test('timetable-placed vehicles are left to their own dimming', () {
      final est = at(0, ts: 0, estimated: true);
      expect(est.staleness(now), 0);
      expect(staleLabel(est, now), isNull);
    });

    test('spans read like „2 min 10 s“', () {
      expect(spanLabel(0), '0 s');
      expect(spanLabel(45), '45 s');
      expect(spanLabel(120), '2 min');
      expect(spanLabel(90061), '1 d 1 h 1 min 1 s');
    });
  });
}

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
}

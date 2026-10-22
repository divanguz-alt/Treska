import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/ui/widgets/stop_card.dart';

void main() {
  final now = DateTime(2026, 10, 22, 17, 30, 0);

  NearbyStop sampleStop({required bool realtime}) => NearbyStop(
        stop: const StopInfo(
          id: '98_1',
          name: 'Črnomerec',
          lat: 45.815,
          lon: 15.934,
          modes: kModeTram,
        ),
        distanceM: 62,
        arrivals: [
          Arrival(
            routeShortName: '17',
            headsign: 'Prečko',
            time: now.add(Duration(seconds: realtime ? 20 : 600)),
            source: realtime ? ArrivalSource.realtime : ArrivalSource.scheduled,
            routeType: kRouteTypeTram,
          ),
        ],
      );

  Widget host(Widget child, Brightness brightness) => MaterialApp(
        theme: buildZetTheme(brightness),
        home: Scaffold(body: child),
      );

  test('theme exposes ZetColors in both brightnesses', () {
    for (final brightness in Brightness.values) {
      final theme = buildZetTheme(brightness);
      final colors = theme.extension<ZetColors>();
      expect(colors, isNotNull);
      expect(colors!.brightness, brightness);
      expect(theme.scaffoldBackgroundColor, colors.bg);
      expect(colors.tileUrl, contains(
          brightness == Brightness.dark ? 'arcgisonline' : 'openstreetmap'));
      expect(colors.tileAttribution, isNotEmpty);
      expect(colors.accent, isNot(colors.bg));
    }
    // The two themes must actually differ.
    expect(ZetColors.dark.bg, isNot(ZetColors.light.bg));
    expect(ZetColors.dark.accent, isNot(ZetColors.light.accent));
  });

  testWidgets('stop card shows stop, route, headsign and DOLAZI', (tester) async {
    await tester.pumpWidget(host(
      StopCard(stop: sampleStop(realtime: true), mode: kModeTram, now: now),
      Brightness.dark,
    ));
    await tester.pump();

    expect(find.text('ČRNOMEREC'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('PREČKO'), findsOneWidget);
    expect(find.text('DOLAZI'), findsOneWidget);
    expect(find.text('62 m'), findsOneWidget);
  });

  testWidgets('scheduled arrival shows clock time, not DOLAZI', (tester) async {
    await tester.pumpWidget(host(
      StopCard(stop: sampleStop(realtime: false), mode: kModeTram, now: now),
      Brightness.light,
    ));
    await tester.pump();

    expect(find.text('DOLAZI'), findsNothing);
    expect(find.text('~17:40'), findsOneWidget);
  });

  testWidgets('estimated arrival shows the delay and an approximate time', (
    tester,
  ) async {
    final stop = NearbyStop(
      stop: const StopInfo(
        id: '98_1',
        name: 'Črnomerec',
        lat: 45.815,
        lon: 15.934,
        modes: kModeTram,
      ),
      distanceM: 62,
      arrivals: [
        Arrival(
          routeShortName: '17',
          headsign: 'Prečko',
          time: now.add(const Duration(minutes: 4)),
          source: ArrivalSource.estimated,
          routeType: kRouteTypeTram,
          delaySec: 180,
        ),
      ],
    );

    await tester.pumpWidget(host(
      StopCard(stop: stop, mode: kModeTram, now: now),
      Brightness.dark,
    ));
    await tester.pump();

    expect(find.text('DOLAZI'), findsNothing);
    expect(find.text('≈'), findsOneWidget);
    expect(find.text('+3\''), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/feed_controller.dart';
import 'package:zet2/data/location_service.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/settings_controller.dart';
import 'package:zet2/ui/arrival_group.dart';
import 'package:zet2/ui/board_panel.dart';
import 'package:zet2/ui/led/led_clock.dart';
import 'package:zet2/ui/led/led_font.dart';
import 'package:zet2/ui/led/led_panel.dart';
import 'package:zet2/ui/widgets/arrival_row.dart';
import 'package:zet2/ui/widgets/zet_arrival_row.dart';

final _now = DateTime(2026, 11, 4, 9, 50);

Arrival _a(
  String route,
  String headsign,
  int seconds, {
  int type = kRouteTypeTram,
  ArrivalSource source = ArrivalSource.realtime,
}) => Arrival(
  routeShortName: route,
  headsign: headsign,
  time: _now.add(Duration(seconds: seconds)),
  source: source,
  routeType: type,
  delaySec: -60,
);

ArrivalGroup _group(List<Arrival> a) => ArrivalGroup(
  routeShortName: a.first.routeShortName,
  headsign: a.first.headsign,
  routeType: a.first.routeType,
  arrivals: a,
);

/// The painters that are listening to the shared clock right now.
LedClock _clock(WidgetTester tester) =>
    LedClockScope.of(tester.element(find.byType(LedPanel).first))!;

Future<void> _pumpRows(
  WidgetTester tester,
  List<ArrivalGroup> groups, {
  bool disableAnimations = false,
  bool marquee = true,
}) async {
  await tester.runAsync(LedFont.load);
  tester.view.physicalSize = const Size(412, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildZetTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(412, 900),
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: LedClockScope(
            child: ListView(
              children: [
                for (final g in groups)
                  ZetArrivalRow(
                    group: g,
                    now: _now,
                    style: ZetDisplayStyle(colorId: 'auto', marquee: marquee),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('spoken text is written out normally', () {
    final g = _group([
      _a('6', 'Črnomerec', 20),
      _a('6', 'Črnomerec', 8 * 60, source: ArrivalSource.scheduled),
    ]);
    expect(
      spokenZetRow(g, _now),
      'Tramvaj 6, Črnomerec, stiže. Zatim za 8 minuta. Uživo.',
    );
    final bus = _group([
      _a('234', 'Kajzerica', 3 * 60 - 10, type: kRouteTypeBus),
      _a('234', 'Kajzerica', 18 * 60, type: kRouteTypeBus),
      _a('234', 'Kajzerica', 21 * 60, type: kRouteTypeBus),
    ]);
    expect(
      spokenZetRow(bus, _now),
      'Autobus 234, Kajzerica, za 3 minute. Zatim za 18 i 21 minutu. Uživo.',
    );
  });

  testWidgets('row: board, status line and „zatim“', (tester) async {
    await _pumpRows(tester, [
      _group([_a('6', 'Črnomerec', 20), _a('6', 'Črnomerec', 8 * 60)]),
    ]);
    expect(find.byType(LedPanel), findsOneWidget);
    expect(find.byType(ArrivalStatusLine), findsOneWidget);
    expect(find.text('Tramvaj'), findsOneWidget);
    expect(find.text('1 min ranije'), findsOneWidget);
    expect(find.text('zatim 8 min'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Tramvaj 6, Črnomerec, stiže. Zatim za 8 minuta. Uživo.',
      ),
      findsOneWidget,
    );
    // The board fills the row: 412 - 2 × 12 row padding - 2 × 6 board padding.
    expect(tester.getSize(find.byType(LedPanel)).width, 376);
  });

  testWidgets('blinking and marquee run on the shared clock', (tester) async {
    await _pumpRows(tester, [
      _group([_a('6', 'Črnomerec', 20)]), // STIŽE blinks
      _group([
        _a(
          '132',
          'Savski most - Goli breg - Brezovica',
          30 * 60,
          type: kRouteTypeBus,
        ),
      ]),
      _group([_a('4', 'Savski most', 9 * 60, source: ArrivalSource.scheduled)]),
    ]);
    final clock = _clock(tester);
    expect(clock.enabled, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(
      tester.hasRunningAnimations,
      isFalse,
      reason: 'the ticker stops with the last sign',
    );
  });

  testWidgets('no animation when the system turns animations off', (
    tester,
  ) async {
    await _pumpRows(tester, [
      _group([_a('6', 'Črnomerec', 20)]),
      _group([
        _a(
          '132',
          'Savski most - Goli breg - Brezovica',
          30 * 60,
          type: kRouteTypeBus,
        ),
      ]),
    ], disableAnimations: true);
    expect(_clock(tester).enabled, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('no ticker for a row that has nothing to animate', (
    tester,
  ) async {
    await _pumpRows(tester, [
      _group([_a('4', 'Savski most', 9 * 60, source: ArrivalSource.scheduled)]),
      _group([
        _a(
          '132',
          'Savski most - Goli breg - Brezovica',
          30 * 60,
          type: kRouteTypeBus,
        ),
      ]),
    ], marquee: false);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('turning ZET zaslon on swaps the rows at once', (tester) async {
    await tester.runAsync(LedFont.load);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final feed = FeedController();
    feed.position.value = const PositionState(45.815, 15.934, true);
    feed.status.value = const FeedStatus(
      staticReady: true,
      loading: '',
      stopCount: 1,
    );
    final now = DateTime.now();
    feed.snapshot.value = FeedSnapshot(
      tramStops: [
        NearbyStop(
          stop: const StopInfo(
            id: 't',
            name: 'Črnomerec',
            lat: 45.8,
            lon: 15.9,
            modes: 1,
          ),
          distanceM: 100,
          arrivals: [
            Arrival(
              routeShortName: '6',
              headsign: 'Sopot',
              time: now.add(const Duration(minutes: 4)),
              source: ArrivalSource.realtime,
              routeType: kRouteTypeTram,
            ),
          ],
        ),
      ],
      updatedAt: now,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildZetTheme(Brightness.light),
        home: Scaffold(
          body: BoardPanel(
            feed: feed,
            settings: settings,
            onStopSelected: (_) {},
            onCollapse: () {},
          ),
        ),
      ),
    );
    expect(find.byType(ArrivalRowWidget), findsOneWidget);
    expect(find.byType(ZetArrivalRow), findsNothing);

    settings.setZetDisplay(true);
    await tester.pump();
    expect(find.byType(ZetArrivalRow), findsOneWidget);
    expect(find.byType(ArrivalRowWidget), findsNothing);
    settings.setZetDisplay(false);
    await tester.pump();
    expect(find.byType(ArrivalRowWidget), findsOneWidget);
  });
}

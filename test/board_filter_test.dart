import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/feed_controller.dart';
import 'package:zet2/data/location_service.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/settings_controller.dart';
import 'package:zet2/ui/board_panel.dart';

final _now = DateTime.now();

Arrival _a(String route, String headsign, int minutes, int type) => Arrival(
  routeShortName: route,
  headsign: headsign,
  time: _now.add(Duration(minutes: minutes, seconds: 30)),
  source: ArrivalSource.scheduled,
  routeType: type,
);

const _tramPlatform = StopInfo(
  id: 't1',
  name: 'Črnomerec',
  lat: 45.815,
  lon: 15.934,
  modes: kModeTram,
);
const _busPlatform = StopInfo(
  id: 'b1',
  name: 'Črnomerec',
  lat: 45.8152,
  lon: 15.9345,
  modes: kModeBus,
);
const _tramOnly = StopInfo(
  id: 't2',
  name: 'Mandaličina',
  lat: 45.808,
  lon: 15.94,
  modes: kModeTram,
);

NearbyStop _tramStop() => NearbyStop(
  stop: _tramPlatform,
  distanceM: 120,
  arrivals: [
    _a('6', 'Sopot', 4, kRouteTypeTram),
    _a('11', 'Dubec', 9, kRouteTypeTram),
  ],
);

NearbyStop _busStop() => NearbyStop(
  stop: _busPlatform,
  distanceM: 90,
  arrivals: [
    _a('101', 'Gornji Stenjevec', 2, kRouteTypeBus),
    _a('101', 'Gornji Stenjevec', 12, kRouteTypeBus),
    _a('119', 'Podsused', 7, kRouteTypeBus),
  ],
);

Future<SettingsController> _settings(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = SettingsController();
  await settings.load();
  return settings;
}

Future<void> _pumpBoard(
  WidgetTester tester,
  SettingsController settings, {
  required List<NearbyStop> trams,
  List<NearbyStop> buses = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final feed = FeedController();
  feed.position.value = const PositionState(45.815, 15.934, true);
  feed.status.value = const FeedStatus(
    staticReady: true,
    loading: '',
    stopCount: 2,
  );
  feed.snapshot.value = FeedSnapshot(
    tramStops: trams,
    busStops: buses,
    updatedAt: _now,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildZetTheme(Brightness.dark),
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
  await tester.pump();
}

/// Route labels of the rows, top to bottom.
List<String> _rows(WidgetTester tester) {
  final labels = <String>[];
  for (final e
      in find
          .byWidgetPredicate(
            (w) =>
                w is Semantics &&
                (w.properties.label ?? '').contains(' prema '),
          )
          .evaluate()) {
    labels.add((e.widget as Semantics).properties.label!.split(' ').first);
  }
  return labels;
}

void main() {
  test('tram and bus platforms of one stop become one board', () {
    final merged = combineModes([_tramStop()], [_busStop()]);
    expect(merged, hasLength(1));
    final stop = merged.single;
    expect(stop.stop.id, 'b1', reason: 'named after the closer platform');
    expect(stop.distanceM, 90);
    expect(stop.arrivalModes, kModeTram | kModeBus);
    expect(stop.lineCount(kModeTram), 2);
    expect(stop.lineCount(kModeBus), 2);
    final minutes = [for (final a in stop.arrivals) a.time];
    expect(minutes, [...minutes]..sort(), reason: 'one list, by time');
    expect(stop.onlyModes(kModeBus).arrivals.map((a) => a.routeShortName), [
      '101',
      '119',
      '101',
    ]);
  });

  test('different stops stay apart, nearest first', () {
    final far = NearbyStop(
      stop: _tramOnly,
      distanceM: 300,
      arrivals: [_a('2', 'Savski most', 3, kRouteTypeTram)],
    );
    final merged = combineModes([far, _tramStop()], [_busStop()]);
    expect([for (final s in merged) s.stop.name], ['Črnomerec', 'Mandaličina']);
  });

  test('the filter cannot turn both modes off and is remembered', () async {
    final settings = await _settings({});
    expect(settings.shownModes, kModeTram, reason: 'trams only by default');
    expect(
      settings.toggleShown(kModeTram),
      isFalse,
      reason: 'the only mode on stays on',
    );
    expect(settings.toggleShown(kModeBus), isTrue);
    expect(settings.shownModes, kModeTram | kModeBus);
    expect(settings.toggleShown(kModeTram), isTrue);
    expect(settings.shownModes, kModeBus);
    expect(
      settings.toggleShown(kModeBus),
      isFalse,
      reason: 'the last mode on stays on',
    );
    expect(settings.shownModes, kModeBus);
    await Future<void>.delayed(Duration.zero);

    final again = SettingsController();
    await again.load();
    expect(again.showTrams, isFalse);
    expect(again.showBuses, isTrue);
  });

  testWidgets('both chips on: one mixed list sorted by time', (tester) async {
    final settings = await _settings({'show_trams': true, 'show_buses': true});
    await _pumpBoard(
      tester,
      settings,
      trams: [_tramStop()],
      buses: [_busStop()],
    );
    expect(find.text('Tramvaji 2'), findsOneWidget);
    expect(find.text('Autobusi 2'), findsOneWidget);
    expect(_rows(tester), ['101', '6', '119', '11']);

    await tester.tap(find.text('Autobusi 2'));
    await tester.pump();
    expect(_rows(tester), ['6', '11']);

    // The only chip left on refuses to switch off.
    await tester.tap(find.text('Tramvaji 2'));
    await tester.pump();
    expect(_rows(tester), ['6', '11']);
    expect(settings.showTrams, isTrue);

    await tester.tap(find.text('Autobusi'));
    await tester.pump();
    await tester.tap(find.text('Tramvaji 2'));
    await tester.pump();
    expect(_rows(tester), ['101', '119']);
  });

  testWidgets('the chips are always there and pick the nearby stops', (
    tester,
  ) async {
    final settings = await _settings({});
    await _pumpBoard(
      tester,
      settings,
      trams: [_tramStop()],
      buses: [_busStop()],
    );
    // Default: trams only, and the bus chip is still there to switch on.
    expect(find.text('Tramvaji 2'), findsOneWidget);
    expect(find.text('Autobusi'), findsOneWidget);
    expect(_rows(tester), ['6', '11']);

    await tester.tap(find.text('Autobusi'));
    await tester.pump();
    expect(settings.showBuses, isTrue);
    expect(_rows(tester), ['101', '6', '119', '11']);

    await tester.tap(find.text('Tramvaji 2'));
    await tester.pump();
    expect(_rows(tester), ['101', '119']);
  });

  testWidgets('buses only with no bus stop near: chips stay, board is empty', (
    tester,
  ) async {
    final settings = await _settings({'show_trams': false, 'show_buses': true});
    await _pumpBoard(tester, settings, trams: [_tramStop()]);
    expect(find.text('Tramvaji'), findsOneWidget);
    expect(find.text('Autobusi'), findsOneWidget);
    expect(_rows(tester), isEmpty);

    await tester.tap(find.text('Tramvaji'));
    await tester.pump();
    expect(_rows(tester), ['6', '11']);
  });
}

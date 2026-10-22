import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/core/tokens.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/settings_controller.dart';
import 'package:zet2/ui/arrival_group.dart';
import 'package:zet2/ui/map_panel.dart';
import 'package:zet2/ui/widgets/arrival_row.dart';
import 'package:zet2/ui/widgets/stop_card.dart';

void main() {
  final now = DateTime(2026, 10, 22, 17, 30, 0);

  StopInfo tramStop() => const StopInfo(
        id: '98_1',
        name: 'Črnomerec',
        lat: 45.815,
        lon: 15.934,
        modes: kModeTram,
      );

  Arrival arrival({
    String route = '17',
    String headsign = 'Prečko',
    Duration after = const Duration(minutes: 10),
    ArrivalSource source = ArrivalSource.scheduled,
    int delaySec = 0,
    int type = kRouteTypeTram,
  }) =>
      Arrival(
        routeShortName: route,
        headsign: headsign,
        time: now.add(after),
        source: source,
        routeType: type,
        delaySec: delaySec,
      );

  Widget host(Widget child, Brightness brightness) => MaterialApp(
        theme: buildZetTheme(brightness),
        home: Scaffold(body: child),
      );

  group('theme', () {
    test('exposes ZetColors in both brightnesses', () {
      for (final brightness in Brightness.values) {
        final theme = buildZetTheme(brightness);
        final colors = theme.extension<ZetColors>();
        expect(colors, isNotNull);
        expect(colors!.brightness, brightness);
        expect(theme.scaffoldBackgroundColor, colors.bg);
        expect(
          colors.tileUrl,
          contains(brightness == Brightness.dark ? 'arcgisonline' : 'openstreetmap'),
        );
        expect(colors.tileAttribution, isNotEmpty);
        expect(colors.primary, isNot(colors.bg));
      }
      // The two themes must actually differ.
      expect(ZetColors.dark.bg, isNot(ZetColors.light.bg));
      expect(ZetColors.dark.primary, isNot(ZetColors.light.primary));
    });

    test('light primary is the ZET blue from the handoff', () {
      expect(ZetColors.light.primary, ZetPalette.lightPrimary);
      expect(ZetPalette.lightPrimary, const Color(0xFF1D5AB0));
    });

    test('inherits the device font instead of hardcoding one', () {
      for (final brightness in Brightness.values) {
        final theme = buildZetTheme(brightness);
        // The handoff's Roboto Flex is Android's system font, so no family is
        // pinned by us: text resolves to whatever the platform provides
        // (Roboto in the test environment) rather than a bundled face.
        for (final style in [
          theme.textTheme.bodyMedium,
          theme.textTheme.titleLarge,
        ]) {
          expect(style?.fontFamily, isNot('monospace'));
          expect(style?.fontFamily, anyOf(isNull, 'Roboto'));
        }
        // Ticking numbers still get tabular figures so they don't jitter.
        expect(kTabular, isNotEmpty);
      }
    });
  });

  group('groupArrivals', () {
    test('groups by route and headsign, sorted by first arrival', () {
      final groups = groupArrivals([
        arrival(route: '6', after: const Duration(minutes: 8)),
        arrival(route: '17', after: const Duration(minutes: 2)),
        arrival(route: '17', after: const Duration(minutes: 14)),
      ]);

      expect(groups.length, 2);
      expect(groups.first.routeShortName, '17');
      expect(groups.first.arrivals.length, 2);
      expect(groups.last.routeShortName, '6');
    });

    test('caps the number of groups', () {
      final many = [
        for (var i = 0; i < 20; i++)
          arrival(route: '$i', after: Duration(minutes: i + 1)),
      ];
      expect(groupArrivals(many, maxGroups: 5).length, 5);
    });

    test('bestSource prefers realtime over estimate over schedule', () {
      final g = groupArrivals([
        arrival(source: ArrivalSource.scheduled),
        arrival(source: ArrivalSource.realtime, after: const Duration(minutes: 5)),
      ]).first;
      expect(g.bestSource, ArrivalSource.realtime);
      expect(g.hasRealtime, isTrue);
    });
  });

  testWidgets('arrival row shows badge, headsign and minutes', (tester) async {
    final group = groupArrivals([
      arrival(after: const Duration(minutes: 4)),
      arrival(after: const Duration(minutes: 12)),
    ]).first;

    await tester.pumpWidget(
      host(
        ArrivalRowWidget(group: group, now: now),
        Brightness.dark,
      ),
    );
    await tester.pump();

    expect(find.text('17'), findsOneWidget);
    expect(find.text('Prečko'), findsOneWidget);
    expect(find.text('17:34'), findsOneWidget);
    expect(find.textContaining('Tramvaj'), findsOneWidget);
    expect(find.textContaining('zatim'), findsOneWidget);
  });

  testWidgets('live arrival inside 45 s shows the Stiže pill', (tester) async {
    final group = groupArrivals([
      arrival(after: const Duration(seconds: 20), source: ArrivalSource.realtime),
    ]).first;

    await tester.pumpWidget(
      host(ArrivalRowWidget(group: group, now: now), Brightness.light),
    );
    await tester.pump();

    expect(find.text('Stiže'), findsOneWidget);
  });

  testWidgets('scheduled arrival shows a clock time, not minutes', (tester) async {
    final group = groupArrivals([
      arrival(after: const Duration(minutes: 10)),
    ]).first;

    await tester.pumpWidget(
      host(ArrivalRowWidget(group: group, now: now), Brightness.light),
    );
    await tester.pump();

    expect(find.text('17:40'), findsOneWidget);
    expect(find.text('Stiže'), findsNothing);
  });

  testWidgets('estimated arrival is marked approximate with a delay',
      (tester) async {
    final group = groupArrivals([
      arrival(
        after: const Duration(minutes: 4),
        source: ArrivalSource.estimated,
        delaySec: 180,
      ),
    ]).first;

    await tester.pumpWidget(
      host(ArrivalRowWidget(group: group, now: now), Brightness.dark),
    );
    await tester.pump();

    expect(find.text('≈'), findsOneWidget);
    expect(find.textContaining('kasni 3 min'), findsOneWidget);
  });

  testWidgets('stop header shows name, distance and walking time',
      (tester) async {
    await tester.pumpWidget(
      host(
        StopHeader(
          stop: NearbyStop(stop: tramStop(), distanceM: 160, arrivals: const []),
        ),
        Brightness.light,
      ),
    );
    await tester.pump();

    expect(find.text('Črnomerec'), findsOneWidget);
    expect(find.textContaining('160 m'), findsOneWidget);
    expect(find.textContaining('2 min hoda'), findsOneWidget);
  });

  testWidgets('stop board renders every group and stays tappable',
      (tester) async {
    ArrivalGroup? opened;
    final stop = NearbyStop(
      stop: tramStop(),
      distanceM: 62,
      arrivals: [
        arrival(after: const Duration(minutes: 3)),
        arrival(route: '6', headsign: 'Sopot', after: const Duration(minutes: 6)),
      ],
    );

    await tester.pumpWidget(
      host(
        StopBoard(stop: stop, now: now, onOpen: (g) => opened = g),
        Brightness.dark,
      ),
    );
    await tester.pump();

    expect(find.text('Prečko'), findsOneWidget);
    expect(find.text('Sopot'), findsOneWidget);

    await tester.tap(find.text('Sopot'));
    await tester.pump();
    expect(opened?.routeShortName, '6');
  });

  group('SettingsController', () {
    test('starts at 800 m and accepts only the offered choices', () {
      final c = SettingsController();
      expect(c.radiusM, 800);
      expect(SettingsController.radiusChoices, [400, 800, 1200]);
    });
  });

  group('map geometry', () {
    // The initial zoom has to keep the whole nearby radius above the sheet, so
    // each radius step moves a zoom level (farther out as the radius grows).
    test('initial zoom tracks the nearby radius', () {
      expect(MapPanel.zoomForRadius(400), 15);
      expect(MapPanel.zoomForRadius(800), 14);
      expect(MapPanel.zoomForRadius(1200), 13);
      // Larger radii must never zoom *in*.
      expect(MapPanel.zoomForRadius(1200),
          lessThan(MapPanel.zoomForRadius(400)));
    });

    // Centring must offset the camera by half the hidden height, or the user
    // marker ends up behind the bottom sheet.
    test('sheet offset shifts the camera south by half the hidden height', () {
      final user = LatLng(45.815, 15.9819);
      final none = MapPanel.shiftForSheet(user, 14, 0);
      expect(none.latitude, user.latitude);

      final shifted = MapPanel.shiftForSheet(user, 14, 900);
      // Moving the camera down means a smaller latitude, same longitude.
      expect(shifted.latitude, lessThan(user.latitude));
      expect(shifted.longitude, user.longitude);
    });
  });
}

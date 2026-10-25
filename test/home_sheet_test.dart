import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/feed_controller.dart';
import 'package:zet2/data/location_service.dart';
import 'package:zet2/data/models.dart';
import 'package:zet2/settings_controller.dart';
import 'package:zet2/theme_controller.dart';
import 'package:zet2/ui/home_screen.dart';

void main() {
  testWidgets('the real home sheet collapses, restores and drags away',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    final feed = FeedController();
    final stop = const StopInfo(
      id: '98_1',
      name: 'Črnomerec',
      lat: 45.815,
      lon: 15.934,
      modes: kModeTram,
    );
    feed.stops.value = [stop];
    feed.position.value = const PositionState(45.815, 15.9819, true);
    feed.status.value = const FeedStatus(
      staticReady: true,
      loading: '',
      stopCount: 1,
    );
    feed.snapshot.value = FeedSnapshot(
      tramStops: [
        NearbyStop(stop: stop, distanceM: 120, arrivals: const []),
      ],
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildZetTheme(Brightness.light),
        home: HomeScreen(
          feed: feed,
          themeController: ThemeController(),
          settings: settings,
        ),
      ),
    );
    // The pulse animation repeats forever, so never pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tramvaji 0'), findsOneWidget);

    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(sheet.controller!.size, closeTo(0.43, 0.03));

    // Chevron: the sheet leaves the tree and the restore pill appears.
    final collapseButton =
        find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down);
    expect(collapseButton, findsOneWidget);
    await tester.tapAt(tester.getCenter(collapseButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(sheet.controller!.isAttached, isTrue);
    expect(sheet.controller!.size, lessThan(0.55));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Prikaži polaske'), findsOneWidget);
    expect(find.text('Tramvaji 0'), findsNothing);

    // Pill: a fresh sheet is inserted at the half height.
    await tester.tap(find.text('Prikaži polaske'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Tramvaji 0'), findsOneWidget);
    expect(find.text('Prikaži polaske'), findsNothing);

    // Dragging the sheet handle down must collapse it and surface the restore
    // pill. (This also proves didUpdateWidget is no longer cancelling drags.)
    final rowTop = tester.getTopLeft(find.text('Tramvaji 0')).dy;
    await tester.timedDragFrom(
      Offset(400, rowTop - 20),
      const Offset(0, 450),
      const Duration(milliseconds: 800),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Prikaži polaske'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/feed_controller.dart';
import 'package:zet2/settings_controller.dart';
import 'package:zet2/ui/widgets/arrow_preview.dart';
import 'package:zet2/ui/widgets/vehicle_marker.dart';
import 'package:zet2/theme_controller.dart';
import 'package:zet2/ui/settings_screen.dart';

void main() {
  test('ZET zaslon settings default and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SettingsController();
    await s.load();
    expect(s.zetDisplay, isFalse);
    expect(s.zetColor, 'auto');
    expect(s.zetMarquee, isTrue);

    s.setZetDisplay(true);
    s.setZetColor('orange');
    s.setZetColor('purple'); // unknown ids are ignored
    s.setZetMarquee(false);
    await Future<void>.delayed(Duration.zero);

    final again = SettingsController();
    await again.load();
    expect(again.zetDisplay, isTrue);
    expect(again.zetColor, 'orange');
    expect(again.zetMarquee, isFalse);
  });

  testWidgets('the section shows its options only while ZET zaslon is on', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildZetTheme(Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettings(
              context,
              feed: FeedController(),
              themeController: ThemeController(),
              settings: settings,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Izgled dolazaka'), findsOneWidget);
    expect(find.text('ZET zaslon'), findsOneWidget);
    expect(find.text('Boja zaslona'), findsNothing);
    expect(find.text('Pomicanje dugih natpisa'), findsNothing);

    await tester.tap(find.text('ZET zaslon'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(settings.zetDisplay, isTrue);
    for (final label in [
      'Boja zaslona',
      'Prema vozilu',
      'Tramvaj limeta, autobus jantar',
      'Limeta',
      'Crotram',
      'Jantar',
      'Novi tramvaji i autobusi',
      'Narančasta',
      'Mercedes',
      'Bijela',
      'MAN',
      'Pomicanje dugih natpisa',
      'Predugo odredište klizi ulijevo, kao na pravom zaslonu',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Bijela'));
    await tester.pump();
    expect(settings.zetColor, 'white');
    await tester.tap(find.text('Pomicanje dugih natpisa'));
    await tester.pump();
    expect(settings.zetMarquee, isFalse);
  });

  testWidgets('Strelica smjera: four animated choices, remembered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsController();
    await settings.load();
    expect(settings.vehicleArrow, VehicleArrow.contrast);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildZetTheme(Brightness.dark),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: settings,
            builder: (context, _) => VehicleArrowPicker(
              value: settings.vehicleArrow,
              onChanged: settings.setVehicleArrow,
            ),
          ),
        ),
      ),
    );
    for (final a in VehicleArrow.values) {
      expect(find.text(a.label), findsOneWidget, reason: a.label);
    }
    final markers = find.byType(VehicleMarkerWidget);
    expect(markers, findsNWidgets(8), reason: 'a tram and a bus per card');

    // The vehicles drive round the block.
    final before = tester.getCenter(markers.first);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getCenter(markers.first), isNot(before));

    await tester.tap(find.text('Klin smjera'));
    await tester.pump();
    expect(settings.vehicleArrow, VehicleArrow.beam);
    final again = SettingsController();
    await tester.runAsync(again.load);
    expect(again.vehicleArrow, VehicleArrow.beam);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zet2/core/theme.dart';
import 'package:zet2/data/feed_controller.dart';
import 'package:zet2/settings_controller.dart';
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
    await tester.pumpAndSettle();

    expect(find.text('Izgled dolazaka'), findsOneWidget);
    expect(find.text('ZET zaslon'), findsOneWidget);
    expect(find.text('Boja zaslona'), findsNothing);
    expect(find.text('Pomicanje dugih natpisa'), findsNothing);

    await tester.tap(find.text('ZET zaslon'));
    await tester.pumpAndSettle();
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
}

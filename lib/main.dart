import 'package:flutter/material.dart';

import 'app.dart';
import 'data/feed_controller.dart';
import 'data/update_service.dart';
import 'settings_controller.dart';
import 'theme_controller.dart';
import 'ui/led/led_font.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads the installed version from Android so the updater compares against
  // what is really on the device. Fire-and-forget: the Settings screen shows a
  // dash until it resolves.
  AppVersion.load();
  // The ZET zaslon font (5 KB); rows use the standard look until it is read.
  LedFont.load().ignore();
  runApp(ZetApp(
    feed: FeedController(),
    themeController: ThemeController(),
    settings: SettingsController(),
  ));
}

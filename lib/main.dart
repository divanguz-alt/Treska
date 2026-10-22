import 'package:flutter/material.dart';

import 'app.dart';
import 'data/feed_controller.dart';
import 'data/update_service.dart';
import 'theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Reads the installed version from Android so the updater compares against
  // what is really on the device. Fire-and-forget: the Settings screen shows a
  // dash until it resolves.
  AppVersion.load();
  runApp(ZetApp(
    feed: FeedController(),
    themeController: ThemeController(),
  ));
}

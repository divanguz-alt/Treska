import 'package:flutter/material.dart';

import 'app.dart';
import 'data/feed_controller.dart';
import 'theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ZetApp(
    feed: FeedController(),
    themeController: ThemeController(),
  ));
}

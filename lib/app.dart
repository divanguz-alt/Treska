import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'data/feed_controller.dart';
import 'settings_controller.dart';
import 'theme_controller.dart';
import 'ui/home_screen.dart';

class ZetApp extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;
  final SettingsController settings;

  const ZetApp({
    super.key,
    required this.feed,
    required this.themeController,
    required this.settings,
  });

  @override
  State<ZetApp> createState() => _ZetAppState();
}

class _ZetAppState extends State<ZetApp> {
  @override
  void initState() {
    super.initState();
    widget.themeController.load();
    // Load the saved radius, then hand it to the feed so the first refresh
    // already uses the right circle.
    widget.settings.load().then((_) {
      widget.feed.radiusM = widget.settings.radiusM;
    });
    widget.feed.start();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.themeController, widget.settings]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Treska',
          debugShowCheckedModeBanner: false,
          theme: buildZetTheme(Brightness.light),
          darkTheme: buildZetTheme(Brightness.dark),
          themeMode: widget.themeController.mode,
          home: Builder(
            builder: (context) {
              final brightness = Theme.of(context).brightness;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: zetSystemOverlay(brightness),
                child: HomeScreen(
                  feed: widget.feed,
                  themeController: widget.themeController,
                  settings: widget.settings,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

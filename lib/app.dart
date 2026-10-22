import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'data/feed_controller.dart';
import 'theme_controller.dart';
import 'ui/home_screen.dart';

class ZetApp extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;

  const ZetApp({
    super.key,
    required this.feed,
    required this.themeController,
  });

  @override
  State<ZetApp> createState() => _ZetAppState();
}

class _ZetAppState extends State<ZetApp> {
  @override
  void initState() {
    super.initState();
    widget.themeController.load();
    widget.feed.start();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.themeController,
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
                ),
              );
            },
          ),
        );
      },
    );
  }
}

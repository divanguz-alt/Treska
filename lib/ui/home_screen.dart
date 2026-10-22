import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../theme_controller.dart';
import 'board_panel.dart';
import 'map_panel.dart';
import 'widgets/pulse.dart';

class HomeScreen extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;

  const HomeScreen({
    super.key,
    required this.feed,
    required this.themeController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;
  int _mode = kModeTram;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: PulseScope(
          animation: _pulseCurve,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MapPanel(
                  feed: widget.feed,
                  themeController: widget.themeController,
                  mode: _mode,
                ),
              ),
              Container(height: 1, color: colors.borderStrong),
              Expanded(
                child: BoardPanel(
                  feed: widget.feed,
                  mode: _mode,
                  onModeChanged: (mode) {
                    if (mode == _mode) return;
                    setState(() => _mode = mode);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

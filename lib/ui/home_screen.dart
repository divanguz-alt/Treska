import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../settings_controller.dart';
import '../theme_controller.dart';
import 'board_panel.dart';
import 'map_panel.dart';
import 'widgets/pulse.dart';

/// The whole app is one screen: a full-bleed map with a bottom sheet over it.
///
/// The sheet has the three heights from the design handoff — peek / half / full
/// — and the map stays interactive behind it. Only two widgets rebuild on a
/// feed update: the map's vehicle layer and the board list.
class HomeScreen extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;
  final SettingsController settings;

  const HomeScreen({
    super.key,
    required this.feed,
    required this.themeController,
    required this.settings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;

  int _mode = kModeTram;

  /// Current sheet size as a fraction of the screen height, animated between
  /// the three snap points.
  late final DraggableScrollableController _sheet;

  @override
  void initState() {
    super.initState();
    _sheet = DraggableScrollableController();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: Curves.easeOut);
    widget.settings.addListener(_onRadius);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onRadius);
    _sheet.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onRadius() => widget.feed.setRadius(widget.settings.radiusM);

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final media = MediaQuery.of(context);
    final screen = media.size.height;

    // Convert the handoff's dp heights into fractions of this screen.
    final peek = (ZetSheetHeight.peek / screen).clamp(0.18, 0.32);
    final half = (ZetSheetHeight.half / screen).clamp(peek + 0.05, 0.72);
    final full = (ZetSheetHeight.full / screen).clamp(half + 0.05, 0.94);

    return Scaffold(
      backgroundColor: colors.bg,
      resizeToAvoidBottomInset: false,
      body: PulseScope(
        animation: _pulseCurve,
        child: AnimatedBuilder(
          animation: _sheet,
          builder: (context, _) {
            // Keep the FAB and zoom controls just above the sheet's top edge.
            final sheetPx = _sheet.isAttached
                ? _sheet.size * screen
                : half * screen;

            return Stack(
              children: [
                Positioned.fill(
                  child: MapPanel(
                    feed: widget.feed,
                    themeController: widget.themeController,
                    settings: widget.settings,
                    mode: _mode,
                    sheetFraction: _sheet.isAttached ? _sheet.size : half,
                    bottomInsetPx: sheetPx,
                  ),
                ),

                // Scrim under the status bar so the header text stays legible
                // over bright map tiles (handoff: 36 dp gradient).
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 36 + media.padding.top,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colors.bg.withValues(alpha: 0.92),
                            colors.bg.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                _BottomSheetHost(
                  controller: _sheet,
                  minChild: peek,
                  initialChild: half,
                  maxChild: full,
                  builder: (context, scrollController) => BoardPanel(
                    feed: widget.feed,
                    settings: widget.settings,
                    mode: _mode,
                    scrollController: scrollController,
                    onModeChanged: (mode) {
                      if (mode == _mode) return;
                      setState(() => _mode = mode);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Wraps [DraggableScrollableSheet] so the sheet keeps its own scroll view and
/// the map behind it keeps receiving touches outside the sheet.
class _BottomSheetHost extends StatelessWidget {
  final DraggableScrollableController controller;
  final double minChild;
  final double initialChild;
  final double maxChild;
  final Widget Function(BuildContext, ScrollController) builder;

  const _BottomSheetHost({
    required this.controller,
    required this.minChild,
    required this.initialChild,
    required this.maxChild,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return DraggableScrollableSheet(
      controller: controller,
      minChildSize: minChild,
      initialChildSize: initialChild,
      maxChildSize: maxChild,
      snap: true,
      snapSizes: [minChild, initialChild, maxChild],
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(ZetRadius.sheet),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Expanded(child: builder(context, scrollController)),
            ],
          ),
        );
      },
    );
  }
}

/// 32 × 4 drag handle in a 28 dp zone, as specified.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return SizedBox(
      height: 28,
      child: Center(
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: colors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

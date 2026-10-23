import 'dart:math' as math;

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
/// — plus a fully collapsed state: dragging it down (or the chevron in its
/// header) hands the screen back to the map, and a floating pill brings it back.
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

  /// Stop the board shows, owned here so the picker, the search screen and the
  /// map all point at the same place.
  String? _selectedStopId;

  /// Current sheet size as a fraction of the screen height, animated between
  /// the snap points.
  late final DraggableScrollableController _sheet;
  bool _sheetCollapsed = false;

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

  /// Snap points for the current screen. The collapsed sheet is 0, so a
  /// downward drag can hand the whole screen to the map.
  ({double peek, double half, double full}) _fractions(double screen) {
    final peek = (ZetSheetHeight.peek / screen).clamp(0.20, 0.38).toDouble();
    final half =
        (ZetSheetHeight.half / screen).clamp(peek + 0.05, 0.72).toDouble();
    final full =
        (ZetSheetHeight.full / screen).clamp(half + 0.05, 0.94).toDouble();
    return (peek: peek, half: half, full: full);
  }


  /// Shared by the stop dropdown and the search screen: select a stop, switch
  /// to the mode it actually serves, and make sure the sheet is open.
  void _selectStop(String id) {
    var mode = _mode;
    for (final stop in widget.feed.stops.value) {
      if (stop.id != id) continue;
      if (!stop.serves(mode)) {
        mode = mode == kModeTram ? kModeBus : kModeTram;
      }
      break;
    }
    setState(() {
      _selectedStopId = id;
      _mode = mode;
    });
    _expandSheet();
  }

  void _expandSheet() {
    if (!_sheet.isAttached) return;
    _sheetCollapsed = false;
    setState(() {});
    final screen = MediaQuery.of(context).size.height;
    final fractions = _fractions(screen);
    _sheet.animateTo(
      fractions.half,
      duration: ZetMotion.sheet,
      curve: ZetMotion.emphasized,
    );
  }

  void _collapseSheet() {
    if (!_sheet.isAttached) return;
    _sheetCollapsed = true;
    setState(() {});
    _sheet.animateTo(
      0.001,
      duration: ZetMotion.sheet,
      curve: ZetMotion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final media = MediaQuery.of(context);
    final screen = media.size.height;
    final fractions = _fractions(screen);

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
                : fractions.half * screen;
            final hidden = _sheet.isAttached && _sheet.size < 0.012 || _sheetCollapsed;

            return Stack(
              children: [
                Positioned.fill(
                  child: MapPanel(
                    feed: widget.feed,
                    themeController: widget.themeController,
                    settings: widget.settings,
                    mode: _mode,
                    sheetFraction:
                        _sheet.isAttached ? _sheet.size : fractions.half,
                    bottomInsetPx: hidden ? 0 : sheetPx,
                    selectedStopId: _selectedStopId,
                    onStopSelected: _selectStop,
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

                IgnorePointer(
                  ignoring: !hidden,
                  child: AnimatedOpacity(
                    opacity: hidden ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _sheetCollapsed = false;
                        setState(() {});
                        final screen = MediaQuery.of(context).size.height;
                        final fractions = _fractions(screen);
                        if (_sheet.isAttached) {
                          _sheet.animateTo(
                            fractions.half,
                            duration: ZetMotion.sheet,
                            curve: ZetMotion.emphasized,
                          );
                        }
                      },
                    ),
                  ),
                ),

                _BottomSheetHost(
                  controller: _sheet,
                  minChild: 0.001,
                  initialChild: fractions.half,
                  maxChild: fractions.full,
                  peek: fractions.peek,
                  bottomInset: math.max(
                    media.padding.bottom,
                    media.viewPadding.bottom,
                  ),
                  builder: (context, scrollController) => BoardPanel(
                    feed: widget.feed,
                    settings: widget.settings,
                    mode: _mode,
                    selectedStopId: _selectedStopId,
                    scrollController: scrollController,
                    onModeChanged: (mode) {
                      if (mode == _mode) return;
                      setState(() => _mode = mode);
                    },
                    onStopSelected: _selectStop,
                    onCollapse: _collapseSheet,
                  ),
                ),

                if (hidden)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: math.max(
                          media.padding.bottom,
                          media.viewPadding.bottom,
                        ) +
                        ZetSpace.lg,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: false,
                          child: _ShowBoardPill(onTap: () {
                            _sheetCollapsed = false;
                            setState(() {});
                            final screen = MediaQuery.of(context).size.height;
                            final fractions = _fractions(screen);
                            if (_sheet.isAttached) {
                              _sheet.animateTo(
                                fractions.half,
                                duration: ZetMotion.sheet,
                                curve: ZetMotion.emphasized,
                              );
                            }
                          }),
                        ),
                      ),
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

/// Floating restore control shown when the sheet is fully collapsed.
class _ShowBoardPill extends StatelessWidget {
  final VoidCallback onTap;

  const _ShowBoardPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Material(
      color: colors.primary,
      elevation: 4,
      borderRadius: BorderRadius.circular(ZetRadius.pill),
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZetRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZetSpace.lg,
            vertical: ZetSpace.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_up,
                  size: 20, color: colors.onPrimary),
              const SizedBox(width: 6),
              Text(
                'Prikaži polaske',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onPrimary,
                ),
              ),
            ],
          ),
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

  /// Intermediate snap point (the "peek" height).
  final double peek;

  /// Android navigation inset, kept inside the sheet's own background.
  final double bottomInset;

  final Widget Function(BuildContext, ScrollController) builder;

  const _BottomSheetHost({
    required this.controller,
    required this.minChild,
    required this.initialChild,
    required this.maxChild,
    required this.peek,
    required this.bottomInset,
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
      snapSizes: [minChild, peek, initialChild, maxChild],
      builder: (context, scrollController) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            return Container(
              clipBehavior: Clip.antiAlias,
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
              // The inset is padding *inside* the decorated box, so the sheet's
              // background reaches the bottom of the screen instead of letting
              // the map show through a gap below it.
              child: height < 90
                  ? const SizedBox.expand()
                  : Padding(
                      padding: EdgeInsets.only(bottom: bottomInset),
                      child: builder(context, scrollController),
                    ),
            );
          },
        );
      },
    );
  }
}

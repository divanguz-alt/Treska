import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

  /// Whether the sheet is part of the tree at all. When the user drags it all
  /// the way down (or taps the chevron) we remove it, which is the only state
  /// from which restoring is completely unambiguous: a fresh sheet is inserted
  /// at the half height.
  bool _sheetVisible = true;

  /// True while the collapse animation is running, so the size listener below
  /// does not remove the sheet halfway through the animation.
  bool _hiding = false;

  /// True while the restore animation is running. Without this the size
  /// listener sees the sheet passing through the "sliver" threshold and removes
  /// it before it can grow back to the half height.
  bool _expanding = false;

  /// Stable snap-size list. A fresh list on every build would make
  /// [DraggableScrollableSheet.didUpdateWidget] think the snap points changed
  /// and run a snap simulation that cancels the current drag/animation.
  List<double>? _snapSizes;

  @override
  void initState() {
    super.initState();
    _sheet = DraggableScrollableController()..addListener(_onSheetChanged);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: Curves.easeOut);
    widget.settings.addListener(_onRadius);
    _syncPinned();
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onRadius);
    _sheet.removeListener(_onSheetChanged);
    _sheet.dispose();
    _pulse.dispose();
    super.dispose();
  }

  /// Hand the screen back to the map as soon as the user parks the sheet at the
  /// bottom. Deferring to a post-frame callback keeps the removal out of the
  /// controller's own notification/build pass.
  void _onSheetChanged() {
    if (!mounted || !_sheetVisible || _hiding || _expanding) return;
    if (!_sheet.isAttached || _sheet.size > 0.08) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_sheetVisible || _hiding || _expanding) return;
      if (_sheet.isAttached && _sheet.size <= 0.08) {
        setState(() => _sheetVisible = false);
      }
    });
  }

  void _onRadius() {
    widget.feed.setRadius(widget.settings.radiusM);
    _syncPinned();
  }

  /// The worker computes boards for these even outside the nearby radius, so a
  /// stop picked far away (search, map star, favourite) still has departures.
  void _syncPinned() {
    widget.feed.setPinnedStops({
      ...widget.settings.favorites,
      ?_selectedStopId,
    });
  }

  void _setMode(int mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      // A stop that has nothing of the new mode would leave an empty board;
      // fall back to the nearest stop of that mode instead.
      final selected = _selectedStopId == null
          ? null
          : widget.feed.stopById[_selectedStopId];
      if (selected != null && !selected.serves(mode)) _selectedStopId = null;
    });
    _syncPinned();
  }

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

  List<double> _snapSizesFor(({double peek, double half, double full}) f) {
    final next = <double>[0, f.peek, f.half, f.full];
    final current = _snapSizes;
    if (current != null && listEquals(current, next)) return current;
    return _snapSizes = next;
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
    _syncPinned();
    _expandSheet();
  }

  /// Brings the board back. While the sheet is mounted this animates it to the
  /// half height; after it was thrown away we simply insert a fresh sheet at
  /// the half height, which cannot fail to restore it.
  void _expandSheet() {
    if (!_sheetVisible) {
      setState(() => _sheetVisible = true);
      return;
    }
    if (!_sheet.isAttached) {
      // The controller lost its client (the sheet is a sliver). Throw the
      // sliver away and insert a fresh sheet at the half height.
      setState(() => _sheetVisible = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sheetVisible = true);
      });
      return;
    }
    final screen = MediaQuery.of(context).size.height;
    final fractions = _fractions(screen);
    if (_sheet.size >= fractions.half - 0.01) return;
    _expanding = true;
    _sheet
        .animateTo(
          fractions.half,
          duration: ZetMotion.sheet,
          curve: ZetMotion.emphasized,
        )
        .whenComplete(() => _expanding = false);
  }

  Future<void> _collapseSheet() async {
    if (!_sheetVisible) return;
    _hiding = true;
    try {
      if (_sheet.isAttached) {
        await _sheet.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {}
    _hiding = false;
    if (!mounted) return;
    setState(() => _sheetVisible = false);
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
        child: Stack(
          children: [
            // Only the map follows the sheet height. The sheet itself must not
            // be rebuilt on every animation tick: a fresh snapSizes list would
            // make didUpdateWidget schedule a snap that cancels the drag or
            // the collapse animation.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sheet,
                builder: (context, _) {
                  final sheetSize = _sheetVisible
                      ? (_sheet.isAttached ? _sheet.size : fractions.half)
                      : 0.0;
                  return MapPanel(
                    feed: widget.feed,
                    themeController: widget.themeController,
                    settings: widget.settings,
                    mode: _mode,
                    sheetFraction: sheetSize,
                    bottomInsetPx: sheetSize * screen,
                    restingInsetPx: fractions.half * screen,
                    selectedStopId: _selectedStopId,
                    onStopSelected: _selectStop,
                  );
                },
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

            if (_sheetVisible)
              _BottomSheetHost(
                key: const ValueKey('board-sheet'),
                controller: _sheet,
                minChild: 0,
                initialChild: fractions.half,
                maxChild: fractions.full,
                snapSizes: _snapSizesFor(fractions),
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
                  onModeChanged: _setMode,
                  onStopSelected: _selectStop,
                  onCollapse: _collapseSheet,
                ),
              ),

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
                child: AnimatedBuilder(
                  animation: _sheet,
                  builder: (context, _) {
                    // Also treat a sliver of sheet at the bottom as collapsed:
                    // the snap can stop just above zero, leaving an empty
                    // rounded strip with no handle to grab.
                    final collapsed = !_sheetVisible ||
                        (_sheet.isAttached && _sheet.size <= 0.08);
                    if (!collapsed) return const SizedBox.shrink();
                    return Center(child: _ShowBoardPill(onTap: _expandSheet));
                  },
                ),
              ),
            ),
          ],
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

  /// Stable snap points, supplied by the screen. Recreating this list on every
  /// build makes the sheet snap and cancel drags.
  final List<double> snapSizes;

  /// Android navigation inset, kept inside the sheet's own background.
  final double bottomInset;

  final Widget Function(BuildContext, ScrollController) builder;

  const _BottomSheetHost({
    super.key,
    required this.controller,
    required this.minChild,
    required this.initialChild,
    required this.maxChild,
    required this.snapSizes,
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
      snapSizes: snapSizes,
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
              //
              // At sliver heights the full board would overflow, but the
              // scrollable must stay mounted: it owns the sheet's scroll
              // controller, and without a client the controller is detached and
              // the sheet can no longer be animated back up from the pill.
              child: height < 90
                  ? CustomScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                    )
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

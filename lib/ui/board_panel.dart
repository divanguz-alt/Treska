import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../settings_controller.dart';
import 'arrival_details.dart';
import 'diagnostics_sheet.dart';
import 'led/led_clock.dart';
import 'widgets/zet_arrival_row.dart';
import 'widgets/stop_card.dart';
import 'widgets/timer_builder.dart';

/// The sheet's content: the selected stop's board, a stop picker and the
/// legend.
///
/// Everything except the legend lives in one [CustomScrollView], including the
/// handle and the filters. That is what makes the sheet draggable: a
/// [DraggableScrollableSheet] resizes itself through its scroll controller, so a
/// fixed header would swallow every drag and leave the sheet feeling pinned.
class BoardPanel extends StatelessWidget {
  final FeedController feed;
  final SettingsController settings;

  /// Selected stop, owned by the screen so search and the board agree.
  final String? selectedStopId;

  final ScrollController? scrollController;
  final ValueChanged<String> onStopSelected;

  /// Hides the sheet, leaving the map full-screen.
  final VoidCallback onCollapse;

  const BoardPanel({
    super.key,
    required this.feed,
    required this.settings,
    required this.onStopSelected,
    required this.onCollapse,
    this.selectedStopId,
    this.scrollController,
  });

  /// Handle + mode row + stop picker. Also the pinned-header extent.
  static const double headerHeight = 124;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([feed.snapshot, feed.status, settings]),
      builder: (context, _) {
        final snapshot = feed.snapshot.value;
        final loading = snapshot == null;

        // Trams and buses share one board; the chips filter it below.
        final nearby = loading
            ? const <NearbyStop>[]
            : combineModes(snapshot.tramStops, snapshot.busStops);

        // Fall back to the nearest stop whenever the selection is gone.
        NearbyStop? selected;
        for (final s in nearby) {
          if (s.stop.id == selectedStopId) {
            selected = s;
            break;
          }
        }
        // Search and the map hand over a platform id; the nearby list names a
        // stop after its closest platform. Same stop, different id — match the
        // group so the board does not show the stop twice.
        final selectedInfo =
            selectedStopId == null ? null : feed.stopById[selectedStopId];
        if (selected == null && selectedInfo != null) {
          for (final s in nearby) {
            if (sameStopGroup(s.stop, selectedInfo)) {
              selected = s;
              break;
            }
          }
        }
        if (selectedStopId == null) {
          selected ??= nearby.isNotEmpty ? nearby.first : null;
        }

        // A stop picked in search, on the map or among the favourites can sit
        // outside the nearby radius. The worker computes a board for it anyway
        // (pinned stops, both modes in one list); show that board.
        NearbyStop? outside;
        if (selected == null && selectedStopId != null && !loading) {
          for (final p in snapshot.pinnedStops) {
            if (p.stop.id != selectedStopId) continue;
            outside = p;
            break;
          }
        }
        // Not computed yet (the first refresh after picking it is in flight):
        // show its header with an empty body rather than snapping back to the
        // nearest stop.
        if (selected == null && outside == null && selectedStopId != null) {
          for (final s in feed.stops.value) {
            if (s.id != selectedStopId) continue;
            final pos = feed.position.value;
            outside = NearbyStop(
              stop: s,
              distanceM: pos.gps
                  ? haversineM(pos.lat, pos.lon, s.lat, s.lon)
                  : 0,
              arrivals: const [],
            );
            break;
          }
        }
        final active = selected ?? outside;

        // The chips only matter where the stop has both modes. Elsewhere the
        // board shows what the stop has, whatever the saved filter says (the
        // saved filter itself is left alone).
        final available = active?.arrivalModes ?? 0;
        final both = available == kModeTram | kModeBus;
        final shown = both || available == 0 ? settings.shownModes : available;
        final board = active?.onlyModes(shown);

        // The picker lists the nearby stops plus an out-of-range selection so
        // its label always matches the board below.
        final picker = <NearbyStop>[...nearby];
        if (outside != null) picker.insert(0, outside);

        final header = _BoardHeader(
          showChips: both,
          showTrams: settings.showTrams,
          showBuses: settings.showBuses,
          tramCount: both ? active!.lineCount(kModeTram) : 0,
          busCount: both ? active!.lineCount(kModeBus) : 0,
          stops: picker,
          selectedStopId: active?.stop.id,
          onToggleMode: (m) {
            // The last mode left on cannot be switched off.
            if (!settings.toggleShown(m)) HapticFeedback.selectionClick();
          },
          onStopSelected: onStopSelected,
          onRefresh: feed.refreshNow,
          onCollapse: onCollapse,
        );

        return LedClockScope(
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _BoardScroll(
                feed: feed,
                settings: settings,
                scrollController: scrollController,
                header: header,
                stop: board,
                loading: loading,
                error: snapshot?.error ?? '',
                mode: shown,
                radiusM: settings.radiusM,
              ),
            ),
            if (!loading && active != null) const _BoardLegend(),
          ],
        ),
        );
      },
    );
  }
}

/// One scroll view for header, stop header and departures, so the sheet can be
/// dragged from anywhere in the panel and the filters stay pinned.
class _BoardScroll extends StatelessWidget {
  final FeedController feed;
  final SettingsController settings;
  final ScrollController? scrollController;
  final Widget header;
  final NearbyStop? stop;
  final bool loading;
  final String error;
  /// [kModeTram] / [kModeBus] bits on the board.
  final int mode;
  final double radiusM;

  const _BoardScroll({
    required this.feed,
    required this.settings,
    required this.scrollController,
    required this.header,
    required this.stop,
    required this.loading,
    required this.error,
    required this.mode,
    required this.radiusM,
  });

  @override
  Widget build(BuildContext context) {
    // The ETA counts down every second between refreshes, so re-render the list
    // on a 1 s tick while it is visible.
    return TimerBuilder(
      interval: const Duration(seconds: 1),
      builder: (context) {
        final now = DateTime.now();
        return CustomScrollView(
          controller: scrollController,
          physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                extent: BoardPanel.headerHeight,
                child: header,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: error.isNotEmpty ? ZetSpace.sm : 0),
            ),
            if (error.isNotEmpty)
              SliverToBoxAdapter(child: _ErrorBanner(feed: feed, message: error)),
            if (loading)
              SliverToBoxAdapter(child: _LoadingBody(feed: feed))
            else if (stop == null)
              SliverToBoxAdapter(
                child: _EmptyBody(radiusM: radiusM),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: ZetSpace.sm),
                  child: StopHeader(
                    stop: stop!,
                    settings: settings,
                    mode: mode,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: StopBoard(
                  stop: stop!,
                  now: now,
                  zet: settings.zetDisplay
                      ? ZetDisplayStyle(
                          colorId: settings.zetColor,
                          marquee: settings.zetMarquee,
                        )
                      : null,
                  onOpen: (group) => showArrivalDetails(
                    context,
                    feed: feed,
                    stop: stop!,
                    group: group,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: ZetSpace.sheet)),
          ],
        );
      },
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;

  const _HeaderDelegate({required this.extent, required this.child});

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(height: extent, child: child);
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate old) =>
      old.extent != extent || old.child != child;
}

/// Drag handle, the two mode filter chips and the stop picker.
class _BoardHeader extends StatelessWidget {
  /// False when the stop has only one mode: the chips are hidden then.
  final bool showChips;
  final bool showTrams;
  final bool showBuses;
  final int tramCount;
  final int busCount;
  final List<NearbyStop> stops;
  final String? selectedStopId;
  final ValueChanged<int> onToggleMode;
  final ValueChanged<String> onStopSelected;
  final Future<void> Function() onRefresh;
  final VoidCallback onCollapse;

  const _BoardHeader({
    required this.showChips,
    required this.showTrams,
    required this.showBuses,
    required this.tramCount,
    required this.busCount,
    required this.stops,
    required this.selectedStopId,
    required this.onToggleMode,
    required this.onStopSelected,
    required this.onRefresh,
    required this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return ColoredBox(
      color: colors.bg,
      child: Column(
        children: [
          const _SheetHandle(),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZetSpace.sheet),
              child: Row(
                children: [
                  if (showChips) ...[
                    _ModeChip(
                      label: 'Tramvaji $tramCount',
                      icon: Icons.tram,
                      selected: showTrams,
                      color: colors.tram,
                      onTap: () => onToggleMode(kModeTram),
                    ),
                    const SizedBox(width: ZetSpace.sm),
                    _ModeChip(
                      label: 'Autobusi $busCount',
                      icon: Icons.directions_bus,
                      selected: showBuses,
                      color: colors.bus,
                      onTap: () => onToggleMode(kModeBus),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    tooltip: 'Osvježi',
                    onPressed: onRefresh,
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    color: colors.textDim,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Skloni popis',
                    onPressed: onCollapse,
                    iconSize: 24,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints.tightFor(width: 40, height: 40),
                    padding: EdgeInsets.zero,
                    color: colors.textDim,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ZetSpace.sheet,
                0,
                ZetSpace.sheet,
                ZetSpace.sm,
              ),
              child: _StopDropdown(
                stops: stops,
                selectedStopId: selectedStopId,
                onChanged: onStopSelected,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 32 × 4 drag handle in a 24 dp zone.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return SizedBox(
      height: 24,
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

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    // A filter toggle, so screen readers hear „uključeno/isključeno“.
    return Semantics(
      toggled: selected,
      child: Material(
      color: selected ? colors.primaryContainer : colors.panel,
      borderRadius: BorderRadius.circular(ZetRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZetRadius.chip),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: ZetSpace.md),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? Colors.transparent : colors.border,
            ),
            borderRadius: BorderRadius.circular(ZetRadius.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check : icon,
                size: 16,
                color: selected ? colors.onPrimaryContainer : colors.textDim,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? colors.onPrimaryContainer : colors.text,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

/// Full-width stop picker. A dropdown is obvious at a glance and needs no
/// horizontal scrolling, unlike the old row of chips that ran off-screen.
class _StopDropdown extends StatelessWidget {
  final List<NearbyStop> stops;
  final String? selectedStopId;
  final ValueChanged<String> onChanged;

  const _StopDropdown({
    required this.stops,
    required this.selectedStopId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    NearbyStop? selected;
    for (final s in stops) {
      if (s.stop.id == selectedStopId) {
        selected = s;
        break;
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Odaberi stajalište',
      onSelected: onChanged,
      color: colors.panel,
      elevation: 6,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
      itemBuilder: (context) => [
        for (final s in stops)
          PopupMenuItem<String>(
            value: s.stop.id,
            child: Row(
              children: [
                Icon(
                  s.stop.id == selectedStopId
                      ? Icons.radio_button_checked
                      : Icons.location_on_outlined,
                  size: 18,
                  color: s.stop.id == selectedStopId
                      ? colors.primary
                      : colors.textDim,
                ),
                const SizedBox(width: ZetSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.stop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: colors.text),
                      ),
                      Text(
                        '${distanceLabel(s.distanceM)} · '
                        '${(s.distanceM / 80).round().clamp(1, 99)} min hoda',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textDim,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: ZetSpace.md),
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on_outlined, size: 18, color: colors.primary),
            const SizedBox(width: ZetSpace.sm),
            Expanded(
              child: Text(
                selected?.stop.name ?? 'Odaberi stajalište',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.text,
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(width: ZetSpace.sm),
              Text(
                distanceLabel(selected.distanceM),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDim,
                  fontFeatures: kTabular,
                ),
              ),
            ],
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 22, color: colors.textDim),
          ],
        ),
      ),
    );
  }
}

/// Teaches the three time formats once, without eating board space.
class _BoardLegend extends StatelessWidget {
  const _BoardLegend();

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final style = TextStyle(
      fontSize: 12,
      color: colors.textDim,
    );

    // The bottom safe area is handled by the sheet host, which keeps this row
    // above the Android gesture handle.
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: ZetSpace.sheet),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderStrong)),
      ),
      // Shrinks instead of overflowing on narrow phones or large text.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            _LegendItem(
              dot: Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: colors.ok),
              ),
              label: 'ZET prognoza',
              style: style,
            ),
            const SizedBox(width: ZetSpace.lg),
            _LegendItem(
              dot: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.textDim, width: 1.4),
                ),
              ),
              label: 'Procjena iz kašnjenja',
              style: style,
            ),
            const SizedBox(width: ZetSpace.lg),
            _LegendItem(
              dot: Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: colors.border),
              ),
              label: 'Raspored',
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Widget dot;
  final String label;
  final TextStyle style;

  const _LegendItem({
    required this.dot,
    required this.label,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final FeedController feed;
  final String message;

  const _ErrorBanner({required this.feed, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZetSpace.md, ZetSpace.sm, ZetSpace.md, 0),
      child: InkWell(
        onTap: () => showDiagnostics(context, feed),
        borderRadius: BorderRadius.circular(ZetRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: ZetSpace.md, vertical: ZetSpace.sm),
          decoration: BoxDecoration(
            color: colors.danger.withValues(alpha: 0.08),
            border: Border.all(color: colors.danger.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(ZetRadius.card),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: 16, color: colors.danger),
              const SizedBox(width: ZetSpace.sm),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.danger,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: colors.danger),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  final double radiusM;

  const _EmptyBody({required this.radiusM});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final radius = radiusM.round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZetSpace.lg, ZetSpace.xl, ZetSpace.lg, ZetSpace.lg),
      child: Column(
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 32, color: colors.textDim),
          const SizedBox(height: ZetSpace.md),
          Text(
            'Nema tramvaja ni autobusa u krugu od $radius m',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colors.textDim,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Osvježi gumbom iznad, povećaj radijus u postavkama ili '
            'provjeri GPS.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  final FeedController feed;
  const _LoadingBody({required this.feed});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final status = feed.status.value;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZetSpace.sheet,
        vertical: ZetSpace.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.staticError.isEmpty) ...[
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: ZetSpace.row),
          ] else
            Icon(Icons.error_outline, size: 32, color: colors.danger),
          Text(
            status.staticError.isEmpty
                ? (status.loading.isEmpty
                    ? 'Učitavam raspored…'
                    : status.loading)
                : status.staticError,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: status.staticError.isEmpty
                  ? colors.textDim
                  : colors.danger,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          if (status.staticError.isEmpty)
            Text(
              'Prvo pokretanje preuzima ~19 MB rasporeda.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textDim,
              ),
            ),
          const SizedBox(height: ZetSpace.lg),
          if (status.staticError.isNotEmpty)
            FilledButton(
              onPressed: feed.retryStatic,
              child: const Text('Pokušaj ponovno'),
            ),
        ],
      ),
    );
  }
}

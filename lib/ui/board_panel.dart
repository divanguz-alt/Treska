import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../settings_controller.dart';
import 'arrival_details.dart';
import 'diagnostics_sheet.dart';
import 'widgets/stop_card.dart';
import 'widgets/timer_builder.dart';

/// The sheet's content: nearby stops, the selected stop's grouped departures and
/// the legend.
///
/// Only the selected stop's board is built, with the other nearby stops offered
/// as suggestion chips — that keeps a busy tram stop from rendering five full
/// boards at once while still making the neighbours one tap away.
class BoardPanel extends StatefulWidget {
  final FeedController feed;
  final SettingsController settings;
  final int mode;
  final ScrollController? scrollController;
  final ValueChanged<int> onModeChanged;

  const BoardPanel({
    super.key,
    required this.feed,
    required this.settings,
    required this.mode,
    required this.onModeChanged,
    this.scrollController,
  });

  @override
  State<BoardPanel> createState() => _BoardPanelState();
}

class _BoardPanelState extends State<BoardPanel> {
  /// Stop the board is focused on; null means "the nearest one".
  String? _selectedStopId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.feed.snapshot, widget.feed.status]),
      builder: (context, _) {
        final snapshot = widget.feed.snapshot.value;
        final loading = snapshot == null;

        final stops = loading
            ? const <NearbyStop>[]
            : (widget.mode == kModeTram
                ? snapshot.tramStops
                : snapshot.busStops);

        // Fall back to the nearest stop whenever the selection is gone.
        NearbyStop? selected;
        for (final s in stops) {
          if (s.stop.id == _selectedStopId) {
            selected = s;
            break;
          }
        }
        selected ??= stops.isNotEmpty ? stops.first : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterChips(
              mode: widget.mode,
              tramCount: _lineCount(snapshot?.tramStops),
              busCount: _lineCount(snapshot?.busStops),
              stops: stops,
              selectedStopId: selected?.stop.id,
              radiusM: widget.settings.radiusM,
              onModeChanged: widget.onModeChanged,
              onStopChanged: (id) => setState(() => _selectedStopId = id),
            ),
            Expanded(
              child: loading
                  ? _LoadingState(feed: widget.feed)
                  : selected == null
                      ? _EmptyState(
                          feed: widget.feed,
                          mode: widget.mode,
                          error: snapshot.error,
                          radiusM: widget.settings.radiusM,
                        )
                      : _BoardBody(
                          feed: widget.feed,
                          stop: selected,
                          scrollController: widget.scrollController,
                          error: snapshot.error,
                        ),
            ),
            if (!loading && selected != null) const _BoardLegend(),
          ],
        );
      },
    );
  }

  int _lineCount(List<NearbyStop>? stops) {
    if (stops == null) return 0;
    final lines = <String>{};
    for (final s in stops) {
      for (final a in s.arrivals) {
        lines.add(a.routeShortName);
      }
    }
    return lines.length;
  }
}

/// M3 filter chips for the two modes plus the neighbouring stops.
class _FilterChips extends StatelessWidget {
  final int mode;
  final int tramCount;
  final int busCount;
  final List<NearbyStop> stops;
  final String? selectedStopId;
  final double radiusM;
  final ValueChanged<int> onModeChanged;
  final ValueChanged<String> onStopChanged;

  const _FilterChips({
    required this.mode,
    required this.tramCount,
    required this.busCount,
    required this.stops,
    required this.selectedStopId,
    required this.radiusM,
    required this.onModeChanged,
    required this.onStopChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final others =
        stops.where((s) => s.stop.id != selectedStopId).take(6).toList();

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ZetSpace.sheet,
          vertical: ZetSpace.md,
        ),
        children: [
          _ModeChip(
            label: 'Tramvaji $tramCount',
            icon: Icons.tram,
            selected: mode == kModeTram,
            color: colors.tram,
            onTap: () => onModeChanged(kModeTram),
          ),
          const SizedBox(width: ZetSpace.sm),
          _ModeChip(
            label: 'Autobusi $busCount',
            icon: Icons.directions_bus,
            selected: mode == kModeBus,
            color: colors.bus,
            onTap: () => onModeChanged(kModeBus),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(width: ZetSpace.md),
            Center(
              child: Container(width: 1, height: 24, color: colors.borderStrong),
            ),
            const SizedBox(width: ZetSpace.md),
            for (final s in others) ...[
              _StopChip(
                stop: s,
                onTap: () => onStopChanged(s.stop.id),
              ),
              const SizedBox(width: ZetSpace.sm),
            ],
          ],
        ],
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
    return Material(
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
    );
  }
}

class _StopChip extends StatelessWidget {
  final NearbyStop stop;
  final VoidCallback onTap;

  const _StopChip({required this.stop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Material(
      color: colors.panel,
      borderRadius: BorderRadius.circular(ZetRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZetRadius.chip),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: ZetSpace.md),
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(ZetRadius.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 15, color: colors.textDim),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  stop.stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.text,
                    ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                distanceLabel(stop.distanceM),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textDim,
                  fontFeatures: kTabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrolling content: stop header followed by the grouped board.
class _BoardBody extends StatelessWidget {
  final FeedController feed;
  final NearbyStop stop;
  final ScrollController? scrollController;
  final String error;

  const _BoardBody({
    required this.feed,
    required this.stop,
    required this.scrollController,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    // The ETA counts down every second between refreshes, so re-render the list
    // on a 1 s tick while it is visible.
    return TimerBuilder(
      interval: const Duration(seconds: 1),
      builder: (context) {
        final now = DateTime.now();
        return RefreshIndicator(
          onRefresh: feed.refreshNow,
          color: colors.primary,
          backgroundColor: colors.bg,
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: ZetSpace.sheet),
            children: [
              if (error.isNotEmpty)
                _ErrorBanner(feed: feed, message: error),
              Padding(
                padding: const EdgeInsets.only(top: ZetSpace.sm),
                child: StopHeader(stop: stop),
              ),
              StopBoard(
                stop: stop,
                now: now,
                onOpen: (group) => showArrivalDetails(
                  context,
                  feed: feed,
                  stop: stop,
                  group: group,
                ),
              ),
            ],
          ),
        );
      },
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

    // The bottom safe area is handled by the sheet host, which lifts the whole
    // sheet above the Android gesture handle, so the legend only needs its own
    // content height here.
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: ZetSpace.sheet),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderStrong)),
      ),
      child: Row(
        children: [
          _LegendItem(
            dot: Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: colors.ok),
            ),
            label: 'Uživo (GPS)',
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
            label: 'Procjena',
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

class _EmptyState extends StatelessWidget {
  final FeedController feed;
  final int mode;
  final String error;
  final double radiusM;

  const _EmptyState({
    required this.feed,
    required this.mode,
    required this.error,
    required this.radiusM,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final radius = radiusM.round();
    return RefreshIndicator(
      onRefresh: feed.refreshNow,
      color: colors.primary,
      backgroundColor: colors.bg,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            ZetSpace.lg, ZetSpace.xl, ZetSpace.lg, ZetSpace.lg),
        children: [
          if (error.isNotEmpty) _ErrorBanner(feed: feed, message: error),
          const SizedBox(height: ZetSpace.xl),
          Icon(Icons.filter_alt_off_outlined, size: 32, color: colors.textDim),
          const SizedBox(height: ZetSpace.md),
          Text(
            mode == kModeTram
                ? 'Nema tramvaja u krugu od $radius m'
                : 'Nema autobusa u krugu od $radius m',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: colors.textDim,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Povuci za osvježavanje, povećaj radijus u postavkama ili '
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

class _LoadingState extends StatelessWidget {
  final FeedController feed;
  const _LoadingState({required this.feed});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final status = feed.status.value;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZetSpace.sheet),
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
      ),
    );
  }
}

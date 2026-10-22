import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import 'diagnostics_sheet.dart';
import 'widgets/stop_card.dart';

/// Departure board for one mode (tram or bus).
///
/// The tab selector is hand-drawn instead of [TabBar]/[TabBarView]: only the
/// visible list is built, and switching tabs never rebuilds the map.
class BoardPanel extends StatelessWidget {
  final FeedController feed;
  final int mode;
  final ValueChanged<int> onModeChanged;

  const BoardPanel({
    super.key,
    required this.feed,
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    return ListenableBuilder(
      listenable: Listenable.merge([feed.snapshot, feed.status]),
      builder: (context, _) {
        final snapshot = feed.snapshot.value;
        final tramCount = snapshot?.tramStops.length ?? 0;
        final busCount = snapshot?.busStops.length ?? 0;
        final loading = snapshot == null;

        return Container(
          color: colors.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeTabs(
                mode: mode,
                tramCount: tramCount,
                busCount: busCount,
                enabled: !loading,
                onChanged: onModeChanged,
                onRefresh: feed.refreshNow,
              ),
              Expanded(
                child: loading
                    ? _LoadingState(feed: feed)
                    : _StopList(
                        feed: feed,
                        stops: mode == kModeTram
                            ? snapshot.tramStops
                            : snapshot.busStops,
                        mode: mode,
                        error: snapshot.error,
                      ),
              ),
              if (!loading) const _BoardLegend(),
            ],
          ),
        );
      },
    );
  }
}

class _ModeTabs extends StatelessWidget {
  final int mode;
  final int tramCount;
  final int busCount;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final Future<void> Function() onRefresh;

  const _ModeTabs({
    required this.mode,
    required this.tramCount,
    required this.busCount,
    required this.enabled,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(
          bottom: BorderSide(color: colors.border),
          top: BorderSide(color: colors.border),
        ),
      ),
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'TRAMVAJI',
              count: tramCount,
              selected: mode == kModeTram,
              color: colors.tram,
              onTap: enabled ? () => onChanged(kModeTram) : null,
            ),
          ),
          Container(width: 1, color: colors.border),
          Expanded(
            child: _TabButton(
              label: 'AUTOBUSI',
              count: busCount,
              selected: mode == kModeBus,
              color: colors.bus,
              onTap: enabled ? () => onChanged(kModeBus) : null,
            ),
          ),
          Container(width: 1, color: colors.border),
          IconButton(
            onPressed: () => onRefresh(),
            tooltip: 'Osvježi',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: colors.textDim,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  const _TabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.panelAlt : colors.panel,
          border: Border(
            bottom: BorderSide(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: selected ? colors.textHi : colors.textDim,
                fontFamily: kMono,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.18)
                    : colors.border.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : colors.textDim,
                  fontFamily: kMono,
                ),
              ),
            ),
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
      fontSize: 8,
      letterSpacing: 0.5,
      fontFamily: kMono,
      color: colors.textDim,
    );

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.textHi,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text('RT', style: style.copyWith(color: colors.textHi)),
          const SizedBox(width: 10),
          Text('≈', style: style.copyWith(color: colors.accent, fontSize: 10)),
          const SizedBox(width: 3),
          Text('PROCJENA', style: style.copyWith(color: colors.accentDim)),
          const SizedBox(width: 10),
          Text('~', style: style.copyWith(fontSize: 10)),
          const SizedBox(width: 3),
          Text('RASPORED', style: style),
          const Spacer(),
          Text('800 m', style: style),
        ],
      ),
    );
  }
}

class _StopList extends StatelessWidget {
  final FeedController feed;
  final List<NearbyStop> stops;
  final int mode;
  final String error;

  const _StopList({
    required this.feed,
    required this.stops,
    required this.mode,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final now = DateTime.now();
    final showError = error.isNotEmpty;

    if (stops.isEmpty) {
      return RefreshIndicator(
        onRefresh: feed.refreshNow,
        color: colors.accent,
        backgroundColor: colors.panel,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          children: [
            if (showError) _ErrorBanner(feed: feed, message: error),
            const SizedBox(height: 24),
            Icon(Icons.filter_alt_off_outlined,
                size: 30, color: colors.textDim),
            const SizedBox(height: 10),
            Text(
              mode == kModeTram
                  ? 'Nema tramvaja u krugu od 800 m'
                  : 'Nema autobusa u krugu od 800 m',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: colors.textDim,
                fontFamily: kMono,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Povuci za osvježavanje ili provjeri GPS.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: colors.textDim.withValues(alpha: 0.75),
                fontFamily: kMono,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: feed.refreshNow,
      color: colors.accent,
      backgroundColor: colors.panel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
        itemCount: stops.length + (showError ? 1 : 0),
        itemBuilder: (context, index) {
          if (showError && index == 0) {
            return _ErrorBanner(feed: feed, message: error);
          }
          final stop = stops[showError ? index - 1 : index];
          return StopCard(
            key: ValueKey('${mode}_${stop.stop.id}'),
            stop: stop,
            mode: mode,
            now: now,
          );
        },
      ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => showDiagnostics(context, feed),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.danger.withValues(alpha: 0.08),
            border: Border.all(color: colors.danger.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off, size: 14, color: colors.danger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.danger,
                    fontFamily: kMono,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 14, color: colors.danger),
            ],
          ),
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status.staticError.isEmpty) ...[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 14),
            ] else
              Icon(Icons.error_outline, size: 28, color: colors.danger),
            Text(
              status.staticError.isEmpty
                  ? (status.loading.isEmpty
                      ? 'Učitavam raspored…'
                      : status.loading)
                  : status.staticError,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: status.staticError.isEmpty
                    ? colors.textDim
                    : colors.danger,
                fontFamily: kMono,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            if (status.staticError.isEmpty)
              Text(
                'Prvo pokretanje preuzima ~19 MB rasporeda.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textDim.withValues(alpha: 0.7),
                  fontFamily: kMono,
                ),
              ),
            const SizedBox(height: 14),
            if (status.staticError.isNotEmpty)
              TextButton(
                onPressed: feed.retryStatic,
                child: Text(
                  'POKUŠAJ PONOVNO',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.accent,
                    letterSpacing: 1,
                    fontFamily: kMono,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

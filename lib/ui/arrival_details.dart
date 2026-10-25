import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import 'arrival_group.dart';
import 'widgets/timer_builder.dart';

/// Full arrival details for one line+direction at a stop.
///
/// Shows the ETA card, the vehicle's live status and — when the schedule knows
/// the trip — the ordered stop timeline with the user's stop highlighted.
Future<void> showArrivalDetails(
  BuildContext context, {
  required FeedController feed,
  required NearbyStop stop,
  required ArrivalGroup group,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Keep the handle and title clear of the status bar.
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: context.zet.bg,
    builder: (_) => _ArrivalDetails(
      feed: feed,
      stop: stop,
      group: group,
    ),
  );
}

class _ArrivalDetails extends StatefulWidget {
  final FeedController feed;
  final NearbyStop stop;
  final ArrivalGroup group;

  const _ArrivalDetails({
    required this.feed,
    required this.stop,
    required this.group,
  });

  @override
  State<_ArrivalDetails> createState() => _ArrivalDetailsState();
}

class _ArrivalDetailsState extends State<_ArrivalDetails> {
  List<TripStop>? _timeline;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stops = await widget.feed.tripStopsFor(
      routeShortName: widget.group.routeShortName,
      headsign: widget.group.headsign,
      stopId: widget.stop.stop.id,
      at: widget.group.next.time,
    );
    if (!mounted) return;
    setState(() {
      _timeline = stops;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final isTram = widget.group.isTram;
    final badgeColor = isTram ? colors.tram : colors.bus;
    final badgeInk = isTram ? colors.onTram : colors.onBus;

    return TimerBuilder(
      interval: const Duration(seconds: 1),
      builder: (context) {
        final now = DateTime.now();
        final next = widget.group.next;
        final seconds = next.secondsUntil(now);
        final live = next.isRealtime;
        final estimated = next.isEstimated;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: ZetSpace.sheet),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: badge + destination + vehicle line.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZetSpace.lg, 0, ZetSpace.lg, ZetSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius:
                            BorderRadius.circular(isTram ? 22 : 12),
                      ),
                      child: Text(
                        widget.group.routeShortName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: badgeInk,
                          ),
                      ),
                    ),
                    const SizedBox(width: ZetSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.group.headsign,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
                              height: 1.15,
                              ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isTram ? 'Tramvaj' : 'Autobus',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textDim,
                              ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ETA card.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ZetSpace.lg, 0, ZetSpace.lg, ZetSpace.md),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                      ZetSpace.lg, ZetSpace.lg, ZetSpace.lg, ZetSpace.xl),
                  decoration: BoxDecoration(
                    color: colors.panelAlt,
                    borderRadius: BorderRadius.circular(ZetRadius.etaCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Do stanice ${widget.stop.stop.name}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textDim,
                          ),
                      ),
                      const SizedBox(height: 6),
                      if (live && seconds <= 45)
                        Text(
                          'Stiže',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w600,
                            color: colors.live,
                            height: 1,
                            ),
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            if (estimated)
                              Text(
                                '≈ ',
                                style: TextStyle(
                                  fontSize: 22,
                                  color: colors.textDim,
                                  ),
                              ),
                            Text(
                              '${next.minutesUntil(now)}',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w600,
                                color: colors.text,
                                height: 1,
                                fontFeatures: kTabular,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'min',
                              style: TextStyle(
                                fontSize: 20,
                                color: colors.textDim,
                                ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 6),
                      Text(
                        _statusText(live, estimated, next.delaySec),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: live
                              ? (next.delaySec.abs() >= 60
                                  ? colors.warn
                                  : colors.ok)
                              : colors.textDim,
                          ),
                      ),
                    ],
                  ),
                ),
              ),

              // Timeline.
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(ZetSpace.xl),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_timeline != null && _timeline!.isNotEmpty)
                _Timeline(
                  stops: _timeline!,
                  myStopId: widget.stop.stop.id,
                  color: badgeColor,
                  now: now,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: ZetSpace.sheet, vertical: ZetSpace.md),
                  child: Text(
                    'Raspored stajališta za ovo vozilo nije dostupan.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textDim,
                      ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _statusText(bool live, bool estimated, int delaySec) {
    if (live) {
      final min = (delaySec.abs() / 60).round();
      if (min < 1) return 'Uživo · na vrijeme';
      return delaySec > 0
          ? 'Uživo · kasni $min min'
          : 'Uživo · $min min ranije';
    }
    if (estimated) return 'Procjena prema zadnjoj poziciji';
    return 'Po rasporedu, bez GPS-a';
  }
}

/// Vertical stop timeline with a coloured rail.
class _Timeline extends StatelessWidget {
  final List<TripStop> stops;
  final String myStopId;
  final Color color;
  final DateTime now;

  const _Timeline({
    required this.stops,
    required this.myStopId,
    required this.color,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final lastPassed = stops.lastIndexWhere((s) => s.passed);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZetSpace.sheet),
      child: Column(
        children: [
          for (var i = 0; i < stops.length; i++)
            _TimelineRow(
              stop: stops[i],
              isMine: stops[i].stopId == myStopId,
              isFirst: i == 0,
              isLast: i == stops.length - 1,
              passed: stops[i].passed,
              color: color,
              dotColor: colors.bg,
              showHereChip: i == lastPassed && i < stops.length - 1,
              lineColor: color,
            ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TripStop stop;
  final bool isMine;
  final bool isFirst;
  final bool isLast;
  final bool passed;
  final Color color;
  final Color dotColor;
  final bool showHereChip;
  final Color lineColor;

  const _TimelineRow({
    required this.stop,
    required this.isMine,
    required this.isFirst,
    required this.isLast,
    required this.passed,
    required this.color,
    required this.dotColor,
    required this.showHereChip,
    required this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final dotSize = isMine ? 20.0 : 14.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 4,
                  height: 8,
                  color: isFirst ? Colors.transparent : lineColor.withValues(
                    alpha: 0.3,
                  ),
                ),
                Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isMine ? color : dotColor,
                    border: Border.all(
                      color: color,
                      width: isMine ? 0 : 3,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 4,
                    color: isLast
                        ? Colors.transparent
                        : lineColor.withValues(alpha: passed ? 0.3 : 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: ZetSpace.row),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isMine ? '${stop.name} · tvoja stanica' : stop.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isMine ? 15 : 14,
                            fontWeight:
                                isMine ? FontWeight.w600 : FontWeight.w400,
                            color: passed ? colors.textDim : colors.text,
                            ),
                        ),
                      ),
                      const SizedBox(width: ZetSpace.sm),
                      Text(
                        passed ? 'prošao' : hhmm(stop.time),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.textDim,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ),
                  if (showHereChip) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: ZetSpace.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(ZetRadius.chip),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tram, size: 13, color: color),
                          const SizedBox(width: 4),
                          Text(
                            'Vozilo je ovdje',
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../arrival_group.dart';
import 'pulse.dart';

/// One grouped departure row: badge · destination + status · ETA.
///
/// Layout follows the handoff's `52dp | 1fr | auto` grid with a 14 dp gap: a
/// route badge, the headsign with a state dot and delay, then either the
/// „Stiže“ pill (ETA ≤ 45 s) or the minutes, with the following two departures
/// underneath.
class ArrivalRowWidget extends StatelessWidget {
  final ArrivalGroup group;
  final DateTime now;
  final bool isLast;
  final VoidCallback? onTap;

  const ArrivalRowWidget({
    super.key,
    required this.group,
    required this.now,
    this.isLast = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final next = group.next;
    final seconds = next.secondsUntil(now);
    final isTram = group.isTram;
    final badgeColor = isTram ? colors.tram : colors.bus;
    final badgeInk = isTram ? colors.onTram : colors.onBus;

    final spoken = _spokenTime(seconds, next.source);
    return Semantics(
      label: '${group.routeShortName} prema ${group.headsign}, $spoken',
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZetRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZetSpace.md,
            vertical: ZetSpace.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _RouteBadge(
                label: group.routeShortName,
                color: badgeColor,
                ink: badgeInk,
                isTram: isTram,
              ),
              const SizedBox(width: ZetSpace.row),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.headsign.isEmpty ? '—' : group.headsign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: colors.text,
                        ),
                    ),
                    const SizedBox(height: 2),
                    ArrivalStatusLine(group: group, now: now),
                  ],
                ),
              ),
              const SizedBox(width: ZetSpace.md),
              _EtaBlock(group: group, now: now),
            ],
          ),
        ),
      ),
    );
  }

  String _spokenTime(int seconds, ArrivalSource source) {
    final realtime = source == ArrivalSource.realtime;
    if (seconds <= 45 && realtime) return 'stiže';
    if (seconds < 60) return realtime ? 'dolazi' : 'sada';
    final estimate = source == ArrivalSource.estimated ? ', procjena' : '';
    return 'za ${(seconds / 60).ceil()} minuta$estimate';
  }
}

/// 52 × 40 badge: tram is a full pill, bus a rounded rectangle.
class _RouteBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color ink;
  final bool isTram;

  const _RouteBadge({
    required this.label,
    required this.color,
    required this.ink,
    required this.isTram,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isTram ? 20 : 10),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1,
          fontFeatures: kTabular,
        ),
      ),
    );
  }
}

/// „• Tramvaj · kasni 3 min“ — the state dot, mode name and (for live only) the
/// delay. Shared with the ZET zaslon row.
class ArrivalStatusLine extends StatelessWidget {
  final ArrivalGroup group;
  final DateTime now;

  const ArrivalStatusLine({super.key, required this.group, required this.now});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final source = group.bestSource;
    final mode = group.isTram ? 'Tramvaj' : 'Autobus';
    final delaySec = group.next.delaySec;

    return Row(
      children: [
        _StateDot(source: source),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            mode,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: colors.textDim,
              ),
          ),
        ),
        if (source != ArrivalSource.scheduled && delaySec != 0) ...[
          Text(
            ' · ',
            style: TextStyle(fontSize: 13, color: colors.textDim),
          ),
          Text(
            _delayLabel(delaySec),
            style: TextStyle(
              fontSize: 13,
              color: delaySec > 60 ? colors.warn : colors.ok,
              ),
          ),
        ],
      ],
    );
  }

  String _delayLabel(int delaySec) {
    final min = (delaySec.abs() / 60).round();
    if (min < 1) return 'na vrijeme';
    return delaySec > 0 ? 'kasni $min min' : '$min min ranije';
  }
}

/// Live = solid green, estimate = hollow ring, schedule = solid outline.
class _StateDot extends StatelessWidget {
  final ArrivalSource source;
  const _StateDot({required this.source});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return switch (source) {
      ArrivalSource.realtime => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colors.ok),
        ),
      ArrivalSource.estimated => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.textDim, width: 1.4),
          ),
        ),
      ArrivalSource.scheduled => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.border,
          ),
        ),
    };
  }
}

/// Right side: „Stiže“ pill, or minutes (with „≈“ for estimates), plus the
/// following two departures.
class _EtaBlock extends StatelessWidget {
  final ArrivalGroup group;
  final DateTime now;

  const _EtaBlock({required this.group, required this.now});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final next = group.next;
    final seconds = next.secondsUntil(now);
    final realtime = next.isRealtime;
    final estimated = next.isEstimated;

    final then = thenLabel(group, now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handoff: `min-width:72px` — the ETA column keeps a steady width so
        // short values ("4 min") and the „Stiže“ pill line up down the list.
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (realtime && seconds <= 45)
                const _ArrivingPill()
              else if (!realtime && !estimated)
                Text(
                  hhmm(next.time),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: colors.textDim,
                    height: 1.05,
                    fontFeatures: kTabular,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (estimated)
                      Text(
                        '≈',
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.textDim,
                        ),
                      ),
                    Text(
                      '${next.minutesUntil(now)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                        height: 1.05,
                        fontFeatures: kTabular,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'min',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textDim,
                        fontFeatures: kTabular,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (then != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              then,
              style: TextStyle(
                fontSize: 12,
                color: colors.textDim,
                fontFeatures: kTabular,
              ),
            ),
          ),
      ],
    );
  }
}

/// „zatim 8, 15 min“ for the departures after the next one, or null.
/// Shared with the ZET zaslon row.
String? thenLabel(ArrivalGroup group, DateTime now) {
  final untilNext = group.arrivals.skip(1).map((a) {
    final s = a.secondsUntil(now);
    return s <= 45 ? 'sada' : '${(s / 60).ceil()}';
  }).toList(growable: false);
  return untilNext.isEmpty ? null : 'zatim ${untilNext.join(', ')} min';
}

/// What the board shows for the next arrival, shared by both row styles:
/// „Stiže“ for a live vehicle at most 45 s away, the clock time for a
/// scheduled one, minutes otherwise.
enum EtaKind { arriving, minutes, clock }

EtaKind etaKind(Arrival next, DateTime now) {
  if (next.isRealtime && next.secondsUntil(now) <= 45) return EtaKind.arriving;
  if (!next.isRealtime && !next.isEstimated) return EtaKind.clock;
  return EtaKind.minutes;
}

/// Red „Stiže“ pill with a pulsing dot.
class _ArrivingPill extends StatelessWidget {
  const _ArrivingPill();

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: ZetSpace.md),
      decoration: BoxDecoration(
        color: colors.liveContainer,
        borderRadius: BorderRadius.circular(ZetRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(size: 7, color: colors.live, minOpacity: 0.2),
          const SizedBox(width: 6),
          Text(
            'Stiže',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colors.onLiveContainer,
              ),
          ),
        ],
      ),
    );
  }
}

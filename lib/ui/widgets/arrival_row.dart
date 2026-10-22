import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import 'pulse.dart';

class ArrivalRowWidget extends StatelessWidget {
  final Arrival arrival;
  final DateTime now;
  final bool isLast;

  const ArrivalRowWidget({
    super.key,
    required this.arrival,
    required this.now,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final seconds = arrival.secondsUntil(now);
    final isRealtime = arrival.isRealtime;
    final isEstimated = arrival.isEstimated;

    final routeColor = isRealtime
        ? colors.textHi
        : (isEstimated ? colors.accent : colors.textDim);
    final headsignColor = isRealtime
        ? colors.text
        : (isEstimated
            ? colors.text.withValues(alpha: 0.86)
            : colors.textDim);

    return Semantics(
      label: '${arrival.routeShortName} prema ${arrival.headsign}, '
          '${_spokenTime(seconds, arrival.source)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isLast ? Colors.transparent : colors.border,
              width: 1,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              child: Text(
                arrival.routeShortName,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: arrival.routeShortName.length > 2 ? 17 : 20,
                  fontWeight: FontWeight.w900,
                  color: routeColor,
                  height: 1.1,
                  fontFamily: kMono,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                arrival.headsign.isEmpty
                    ? '—'
                    : arrival.headsign.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: headsignColor,
                  height: 1.25,
                  letterSpacing: 0.2,
                  fontFamily: kMono,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _TimeLabel(
              seconds: seconds,
              source: arrival.source,
              minutes: arrival.minutesUntil(now),
              time: arrival.time,
              delaySec: arrival.delaySec,
            ),
          ],
        ),
      ),
    );
  }

  String _spokenTime(int seconds, ArrivalSource source) {
    final realtime = source == ArrivalSource.realtime;
    final estimate = source == ArrivalSource.estimated ? ', procjena' : '';
    if (seconds < 60) return realtime ? 'dolazi' : 'sada';
    return 'za ${(seconds / 60).ceil()} minuta$estimate';
  }
}

class _TimeLabel extends StatelessWidget {
  final int seconds;
  final int minutes;
  final ArrivalSource source;
  final DateTime time;
  final int delaySec;

  const _TimeLabel({
    required this.seconds,
    required this.source,
    required this.minutes,
    required this.time,
    required this.delaySec,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final realtime = source == ArrivalSource.realtime;
    final estimated = source == ArrivalSource.estimated;

    if (realtime && seconds < 60) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(size: 5, color: colors.danger),
          const SizedBox(width: 4),
          Text(
            'DOLAZI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: colors.danger,
              letterSpacing: 0.6,
              fontFamily: kMono,
            ),
          ),
        ],
      );
    }

    if (!realtime && !estimated && seconds < 90) {
      return Text(
        'SADA',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.accentDim,
          letterSpacing: 0.6,
          fontFamily: kMono,
        ),
      );
    }

    if (!realtime && !estimated) {
      return Text(
        '~${hhmm(time)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colors.textDim,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamily: kMono,
        ),
      );
    }

    final delayMin = (delaySec.abs() / 60).round();
    final showDelay = delayMin >= 1;
    final delayColor = delaySec > 0 ? colors.danger : colors.ok;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showDelay) ...[
          _DelayChip(
            label: '${delaySec > 0 ? '+' : '-'}$delayMin\'',
            color: delayColor,
          ),
          const SizedBox(width: 5),
        ],
        if (estimated)
          Text(
            '≈',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.accentDim,
              fontFamily: kMono,
            ),
          ),
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: estimated ? colors.accent : colors.textHi,
            height: 1,
            fontFamily: kMono,
          ),
        ),
        Text(
          ' MIN',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: colors.accentDim,
            letterSpacing: 0.4,
            fontFamily: kMono,
          ),
        ),
      ],
    );
  }
}

class _DelayChip extends StatelessWidget {
  final String label;
  final Color color;

  const _DelayChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1,
          fontFamily: kMono,
        ),
      ),
    );
  }
}

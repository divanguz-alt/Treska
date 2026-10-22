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
    final routeColor = isRealtime ? colors.textHi : colors.textDim;
    final headsignColor = isRealtime ? colors.text : colors.textDim;

    return Semantics(
      label: '${arrival.routeShortName} prema ${arrival.headsign}, '
          '${_spokenTime(seconds, isRealtime)}',
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
              realtime: isRealtime,
              minutes: arrival.minutesUntil(now),
              time: arrival.time,
            ),
          ],
        ),
      ),
    );
  }

  String _spokenTime(int seconds, bool realtime) {
    if (seconds < 60) return realtime ? 'dolazi' : 'sada';
    return 'za ${(seconds / 60).ceil()} minuta';
  }
}

class _TimeLabel extends StatelessWidget {
  final int seconds;
  final int minutes;
  final bool realtime;
  final DateTime time;

  const _TimeLabel({
    required this.seconds,
    required this.realtime,
    required this.minutes,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    if (seconds < 60 && realtime) {
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

    if (seconds < 90 && !realtime) {
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

    if (!realtime) {
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$minutes',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: colors.textHi,
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

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import 'arrival_row.dart';

class StopCard extends StatelessWidget {
  final NearbyStop stop;
  final int mode;
  final DateTime now;

  const StopCard({
    super.key,
    required this.stop,
    required this.mode,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final modeColor = mode == kModeTram ? colors.tram : colors.bus;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: colors.panel,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              color: colors.panelAlt,
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 14,
                    color: modeColor,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      stop.stop.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.textHi,
                        letterSpacing: 0.9,
                        fontFamily: kMono,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    distanceLabel(stop.distanceM),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textDim,
                      fontFamily: kMono,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.border),
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Text(
                      'LINIJA',
                      style: _labelStyle(colors),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('ODREDIŠTE', style: _labelStyle(colors)),
                  ),
                  Text('DOLAZAK', style: _labelStyle(colors)),
                ],
              ),
            ),
            for (var i = 0; i < stop.arrivals.length; i++)
              ArrivalRowWidget(
                arrival: stop.arrivals[i],
                now: now,
                isLast: i == stop.arrivals.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  TextStyle _labelStyle(ZetColors colors) => TextStyle(
        fontSize: 8,
        color: colors.textDim,
        letterSpacing: 1.1,
        fontFamily: kMono,
      );
}

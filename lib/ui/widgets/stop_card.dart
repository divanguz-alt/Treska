import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../arrival_group.dart';
import 'arrival_row.dart';

/// Header for the board: the stop name, walking time and a favourite star.
///
/// Part of the sheet's scroll view (not a fixed card) so the whole board scrolls
/// as one piece, as in the handoff.
class StopHeader extends StatelessWidget {
  final NearbyStop stop;
  final bool favourite;
  final VoidCallback? onToggleFavourite;

  const StopHeader({
    super.key,
    required this.stop,
    this.favourite = false,
    this.onToggleFavourite,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final walkMin = (stop.distanceM / 80).round().clamp(1, 99);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZetSpace.md,
        0,
        ZetSpace.sm,
        ZetSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stop.stop.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                    height: 1.15,
                    fontFamily: kMono,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.directions_walk,
                        size: 18, color: colors.textDim),
                    const SizedBox(width: 4),
                    Text(
                      '${distanceLabel(stop.distanceM)} · $walkMin min hoda',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.textDim,
                        fontFamily: kMono,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: favourite ? 'Uklonjeno iz spremljenih' : 'Spremi stanicu',
            onPressed: onToggleFavourite,
            icon: Icon(
              favourite ? Icons.star : Icons.star_border,
              size: 24,
              color: favourite ? colors.primary : colors.textDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grouped departure list for one stop.
class StopBoard extends StatelessWidget {
  final NearbyStop stop;
  final DateTime now;
  final void Function(ArrivalGroup) onOpen;

  const StopBoard({
    super.key,
    required this.stop,
    required this.now,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final groups = groupArrivals(stop.arrivals);

    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ZetSpace.sheet, vertical: ZetSpace.xxl),
        child: Text(
          'Nema dolazaka za odabrani filtar.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: colors.textDim,
            fontFamily: kMono,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++)
          ArrivalRowWidget(
            key: ValueKey(
              'g_${stop.stop.id}_${groups[i].routeShortName}_${groups[i].headsign}',
            ),
            group: groups[i],
            now: now,
            isLast: i == groups.length - 1,
            onTap: () => onOpen(groups[i]),
          ),
      ],
    );
  }
}

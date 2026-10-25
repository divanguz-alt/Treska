import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../../settings_controller.dart';
import '../arrival_group.dart';
import 'arrival_row.dart';

/// Header for the board: the stop name, walking time and a favourite star.
class StopHeader extends StatelessWidget {
  final NearbyStop stop;
  final SettingsController settings;
  final VoidCallback? onToggleFavourite;

  /// All stops by id, so a star saved on another platform of this stop still
  /// counts. Empty means "compare ids only".
  final Map<String, StopInfo> stopById;

  const StopHeader({
    super.key,
    required this.stop,
    required this.settings,
    this.onToggleFavourite,
    this.stopById = const {},
  });

  @override
  Widget build(BuildContext context) {
    // Rebuild on its own when the star is toggled, so the icon never lags
    // behind the saved state even if a parent forgets to listen.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final colors = context.zet;
        final walkMin = (stop.distanceM / 80).round().clamp(1, 99);
        final favourite = settings.isFavoriteStop(stop.stop, stopById);

        return Padding(
          // Handoff: `padding: 0 12px 10px 24px` — the stop name lines up with
          // the list's 24 dp gutter, not the rows' 12 dp one.
          padding: const EdgeInsets.fromLTRB(
            ZetSpace.sheet,
            0,
            ZetSpace.md,
            10,
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
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favourite ? 'Ukloni iz spremljenih' : 'Spremi stanicu',
                onPressed: onToggleFavourite ??
                    () {
                      final wasFavorite = favourite;
                      settings.toggleFavoriteStop(stop.stop, stopById);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            content: Text(
                              wasFavorite
                                  ? '${stop.stop.name} uklonjena iz spremljenih'
                                  : '${stop.stop.name} spremljena · označena zvjezdicom',
                            ),
                          ),
                        );
                    },
                icon: Icon(
                  favourite ? Icons.star : Icons.star_border,
                  size: 24,
                  color: favourite ? colors.primary : colors.textDim,
                ),
              ),
            ],
          ),
        );
      },
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

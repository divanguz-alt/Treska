import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/tokens.dart';
import '../../data/models.dart';
import '../arrival_group.dart';
import '../led/led_font.dart';
import '../led/led_palette.dart';
import '../led/led_panel.dart';
import 'arrival_row.dart';

/// How the ZET zaslon rows look, from the settings.
class ZetDisplayStyle {
  /// „Boja zaslona“ option id ([LedPalette.options]).
  final String colorId;

  /// „Pomicanje dugih natpisa“.
  final bool marquee;

  const ZetDisplayStyle({required this.colorId, required this.marquee});
}

/// Arrival row in the ZET zaslon look (handoff variant 1b): the whole sign,
/// line, destination and time, on a dark LED board, with the usual status
/// line underneath. Behaves like [ArrivalRowWidget] (tap, ripple).
class ZetArrivalRow extends StatelessWidget {
  final ArrivalGroup group;
  final DateTime now;
  final ZetDisplayStyle style;
  final VoidCallback? onTap;

  const ZetArrivalRow({
    super.key,
    required this.group,
    required this.now,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final font = LedFont.instance;
    // The font is read once at start-up; until then the standard row stands
    // in (the board re-renders every second anyway).
    if (font == null) {
      return ArrivalRowWidget(group: group, now: now, onTap: onTap);
    }
    final colors = context.zet;
    final next = group.next;
    final kind = etaKind(next, now);
    final time = switch (kind) {
      EtaKind.arriving => 'STIŽE',
      EtaKind.minutes => '${next.minutesUntil(now)} MIN',
      EtaKind.clock => hhmm(next.time),
    };
    final then = thenLabel(group, now);

    return Semantics(
      label: spokenZetRow(group, now),
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZetRadius.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LedBoard(
                font: font,
                line: group.routeShortName,
                dest: group.headsign.isEmpty ? '—' : group.headsign,
                time: time,
                blinkTime: kind == EtaKind.arriving,
                color: LedPalette.forVehicle(
                  style.colorId,
                  isTram: group.isTram,
                ),
                marquee: style.marquee,
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: ArrivalStatusLine(group: group, now: now),
                    ),
                    if (then != null) ...[
                      const SizedBox(width: ZetSpace.sm),
                      Text(
                        then,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textDim,
                          fontFeatures: kTabular,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen-reader text for a ZET zaslon row, written out normally:
/// „Tramvaj 6, Črnomerec, stiže. Zatim za 8 minuta. Uživo.“
String spokenZetRow(ArrivalGroup group, DateTime now) {
  final next = group.next;
  final seconds = next.secondsUntil(now);
  final mode = group.isTram ? 'Tramvaj' : 'Autobus';
  final dest = group.headsign.isEmpty ? '' : ', ${group.headsign}';
  final when = switch (etaKind(next, now)) {
    EtaKind.arriving => 'stiže',
    EtaKind.clock => 'u ${hhmm(next.time)}',
    EtaKind.minutes =>
      seconds < 60
          ? 'dolazi'
          : 'za ${next.minutesUntil(now)} ${_minutes(next.minutesUntil(now))}',
  };
  final later = [
    for (final a in group.arrivals.skip(1))
      a.secondsUntil(now) <= 45 ? null : (a.secondsUntil(now) / 60).ceil(),
  ];
  String then = '';
  if (later.isNotEmpty) {
    if (later.first == null) {
      then = ' Zatim još jedan odmah.';
    } else {
      final mins = later.whereType<int>().toList();
      final list = mins.length == 1
          ? '${mins.first}'
          : '${mins.sublist(0, mins.length - 1).join(', ')} i ${mins.last}';
      then = ' Zatim za $list ${_minutes(mins.last)}.';
    }
  }
  final source = switch (next.source) {
    ArrivalSource.realtime => 'Uživo',
    ArrivalSource.estimated => 'Procjena',
    ArrivalSource.scheduled => 'Raspored',
  };
  return '$mode ${group.routeShortName}$dest, $when.$then $source.';
}

/// „minuta“ / „minute“ / „minutu“ after a number, Croatian style.
String _minutes(int n) {
  final last2 = n % 100;
  final last = n % 10;
  if (last == 1 && last2 != 11) return 'minutu';
  if (last >= 2 && last <= 4 && (last2 < 12 || last2 > 14)) return 'minute';
  return 'minuta';
}

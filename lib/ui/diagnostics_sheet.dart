import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';

/// Diagnostics sheet: everything the old app printed permanently on the home
/// screen, moved out of the way but still one tap away.
Future<void> showDiagnostics(BuildContext context, FeedController feed) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _DiagnosticsSheet(feed: feed),
  );
}

class _DiagnosticsSheet extends StatelessWidget {
  final FeedController feed;
  const _DiagnosticsSheet({required this.feed});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final status = feed.status.value;
    final snapshot = feed.snapshot.value;
    final stats = snapshot?.stats ?? const FeedStats();
    final pos = feed.position.value;
    final age = stats.feedTimestamp > 0 ? stats.ageSecAt(DateTime.now()) : -1;

    final rows = <(String, String)>[
      ('Kanal', stats.streaming ? 'WS (stream)' : 'REST (poll)'),
      ('Raspored', status.staticReady ? 'učitan' : 'nije učitan'),
      ('Stajališta', '${status.stopCount}'),
      ('Aktivni polasci', '${status.tripCount}'),
      ('Parsiranje', '${status.parseMs} ms'),
      ('Osvježavanje', '${stats.refreshMs} ms'),
      ('Starost podataka', age < 0 ? '—' : '$age s'),
      ('RT entiteti', '${stats.rtEntities}'),
      ('RT dolasci', '${stats.rtArrivals}'),
      ('S kašnjenjem', '${stats.estimatedArrivals}'),
      ('Iz rasporeda', '${stats.scheduledArrivals}'),
      ('Vozila', '${stats.vehicles} (${stats.vehiclesTram} tram / '
          '${stats.vehiclesBus} bus)'),
      ('Lokacija', pos.gps
          ? '${pos.lat.toStringAsFixed(5)}, ${pos.lon.toStringAsFixed(5)}'
          : 'nema GPS-a (Zagreb centar)'),
      ('Zadnje', snapshot == null ? '—' : hhmmss(snapshot.updatedAt)),
      ('Interval', '${FeedController.pollInterval.inSeconds} s'),
      ('Karta', colors.isDark ? 'Esri Dark Gray' : 'OpenStreetMap'),
      ('Karta izvor', colors.tileAttribution),
      if (status.staticError.isNotEmpty) ('Greška', status.staticError),
      if (snapshot != null && snapshot.error.isNotEmpty)
        ('RT greška', snapshot.error),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DIJAGNOSTIKA',
              style: TextStyle(
                fontSize: 12,
                color: colors.accent,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                fontFamily: kMono,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (key, value) in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 118,
                              child: Text(
                                key.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colors.textDim,
                                  letterSpacing: 0.8,
                                  fontFamily: kMono,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                value,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.text,
                                  fontFamily: kMono,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'OSVJEŽI',
                    icon: Icons.refresh,
                    onTap: () {
                      Navigator.of(context).pop();
                      feed.refreshNow();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SheetButton(
                    label: 'RASPORED',
                    icon: Icons.cloud_download,
                    onTap: () {
                      Navigator.of(context).pop();
                      feed.retryStatic();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SheetButton(
                    label: 'LOKACIJA',
                    icon: Icons.my_location,
                    onTap: () {
                      Navigator.of(context).pop();
                      feed.retryLocation();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SheetButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: 1,
          fontFamily: kMono,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.borderStrong),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/models.dart';
import '../settings_controller.dart';

/// Full-screen stop/line search.
///
/// Matches stop names (case- and diacritic-insensitive) and route numbers that
/// appear in the current snapshot, so typing "6" surfaces the stops the 6 serves
/// near the user while "trg" surfaces stops by name.
///
/// Named `showStopSearch` rather than `showSearch` so it never collides with
/// Material's own `showSearch` when both are imported.
Future<String?> showStopSearch(
  BuildContext context, {
  required FeedController feed,
  required SettingsController settings,
}) {
  // The platform page transition, like Settings. The old custom fade drew the
  // half-transparent results list over the live map for a quarter second,
  // which read as a page that failed to load.
  return Navigator.of(context).push(
    MaterialPageRoute<String>(
      builder: (context) => _SearchScreen(feed: feed, settings: settings),
    ),
  );
}

class _SearchScreen extends StatefulWidget {
  final FeedController feed;
  final SettingsController settings;

  const _SearchScreen({required this.feed, required this.settings});

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  String _text = '';

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ZetSpace.lg, ZetSpace.sm, ZetSpace.lg, ZetSpace.md),
              child: _SearchField(
                controller: _query,
                focus: _focus,
                onChanged: (v) => setState(() => _text = v),
                onSubmitted: (_) => _selectFirst(),
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.feed.stops,
                  widget.feed.snapshot,
                  widget.feed.position,
                  widget.settings,
                ]),
                builder: (context, _) {
                  final results = _results();
                  final nearby = _text.trim().isEmpty;
                  final favorites = nearby ? _favorites() : const <_SearchResult>[];
                  final gps = widget.feed.position.value.gps;

                  return ListView(
                    padding: const EdgeInsets.only(bottom: ZetSpace.sheet),
                    children: [
                      if (favorites.isNotEmpty) ...[
                        _SectionLabel('Spremljene', color: colors.primary),
                        for (final r in favorites)
                          _StopResult(
                            stop: r.stop,
                            distanceM: r.distanceM,
                            lines: r.lines,
                            favorite: true,
                            onTap: () => Navigator.of(context).pop(r.stop.id),
                          ),
                        const SizedBox(height: ZetSpace.md),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            ZetSpace.sheet, 0, ZetSpace.sheet, ZetSpace.sm),
                        child: Text(
                          nearby
                              ? (gps
                                  ? 'Stanice u blizini'
                                  : 'Stanice u blizini centra (nema GPS-a)')
                              : 'Rezultati (${results.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.primary,
                            ),
                        ),
                      ),
                      if (results.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: ZetSpace.sheet,
                              vertical: ZetSpace.xxl),
                          child: Text(
                            'Nema rezultata za „$_text“.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.textDim,
                              ),
                          ),
                        )
                      else
                        for (final r in results)
                          _StopResult(
                            stop: r.stop,
                            distanceM: r.distanceM,
                            lines: r.lines,
                            onTap: () => Navigator.of(context).pop(r.stop.id),
                          ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Picking the keyboard's search key takes the first hit, so typing a line
  /// number and hitting enter is a one-step action.
  void _selectFirst() {
    final results = _results();
    if (results.isEmpty) return;
    Navigator.of(context).pop(results.first.stop.id);
  }

  /// Lines currently on the board per stop (group), so a number search can
  /// name the stop's lines without a second lookup.
  Map<String, Set<String>> _linesByGroup() {
    final snapshot = widget.feed.snapshot.value;
    final out = <String, Set<String>>{};
    for (final stop in [
      ...?snapshot?.tramStops,
      ...?snapshot?.busStops,
      ...?snapshot?.pinnedStops,
    ]) {
      out.putIfAbsent(stopGroupKey(stop.stop.name), () => <String>{}).addAll(
            stop.arrivals.map((a) => a.routeShortName),
          );
    }
    return out;
  }

  List<_SearchResult> _results() {
    final pos = widget.feed.position.value;
    final all = widget.feed.stops.value;
    final q = _normalize(_text.trim());
    final linesByGroup = _linesByGroup();

    // Distance always comes from the current position. Without a GPS fix that
    // is the city-centre fallback, which still orders results sensibly; the
    // old "infinity without GPS" left the list in file order (eleven
    // „Črnomerec“ rows as "nearby").
    final scored = <_SearchResult>[];
    for (final s in all) {
      final name = _normalize(s.name);
      final lines = linesByGroup[stopGroupKey(s.name)] ?? const <String>{};
      final lineMatch = q.isNotEmpty &&
          lines.any((l) => _normalize(l).startsWith(q));

      if (q.isNotEmpty && !name.contains(q) && !lineMatch) continue;

      final distance = haversineM(pos.lat, pos.lon, s.lat, s.lon);
      scored.add(_SearchResult(
        stop: s,
        distanceM: distance,
        lines: lines,
        // Names that start with the query beat names that merely contain it.
        rank: q.isEmpty || name.startsWith(q) ? 0 : 1,
      ));
    }

    scored.sort((a, b) {
      if (a.rank != b.rank) return a.rank - b.rank;
      return a.distanceM.compareTo(b.distanceM);
    });

    // One row per stop: its platforms share a name and sit next to each other,
    // and picking any of them opens the same merged board.
    final out = <_SearchResult>[];
    for (final r in scored) {
      if (out.any((o) => sameStopGroup(o.stop, r.stop))) continue;
      out.add(r);
      if (out.length >= (q.isEmpty ? 12 : 40)) break;
    }
    return out;
  }

  List<_SearchResult> _favorites() {
    final pos = widget.feed.position.value;
    final stopById = widget.feed.stopById;
    final linesByGroup = _linesByGroup();
    final out = <_SearchResult>[];
    for (final id in widget.settings.favorites) {
      final s = stopById[id];
      if (s == null) continue;
      if (out.any((o) => sameStopGroup(o.stop, s))) continue;
      out.add(_SearchResult(
        stop: s,
        distanceM: haversineM(pos.lat, pos.lon, s.lat, s.lon),
        lines: linesByGroup[stopGroupKey(s.name)] ?? const <String>{},
      ));
    }
    out.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return out;
  }

  /// Lowercase and strip Croatian diacritics so „črnomerec“ matches „Črnomerec“.
  static String _normalize(String s) {
    const map = {
      'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd',
      'Č': 'c', 'Ć': 'c', 'Š': 's', 'Ž': 'z', 'Đ': 'd',
    };
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onBack;

  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return Material(
      color: colors.panel,
      elevation: 2,
      borderRadius: BorderRadius.circular(ZetRadius.search),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              color: colors.text,
              tooltip: 'Natrag',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.text,
                  ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Traži stanicu ili liniju',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: colors.textDim,
                    ),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
                color: colors.textDim,
                tooltip: 'Očisti',
              ),
            const SizedBox(width: ZetSpace.xs),
          ],
        ),
      ),
    );
  }
}

class _SearchResult {
  final StopInfo stop;
  final double distanceM;
  final Set<String> lines;
  final int rank;

  const _SearchResult({
    required this.stop,
    required this.distanceM,
    required this.lines,
    this.rank = 0,
  });
}

class _StopResult extends StatelessWidget {
  final StopInfo stop;
  final double distanceM;
  final Set<String> lines;
  final VoidCallback onTap;
  final bool favorite;

  const _StopResult({
    required this.stop,
    required this.distanceM,
    required this.lines,
    required this.onTap,
    this.favorite = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final lineLabel = lines.isEmpty
        ? null
        : 'Linije ${(lines.toList()..sort()).join(', ')}';

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.panel,
          shape: BoxShape.circle,
        ),
        child: Icon(
          favorite ? Icons.star_rounded : Icons.location_on,
          size: 20,
          color: colors.primary,
        ),
      ),
      title: Text(
        stop.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          color: colors.text,
          ),
      ),
      subtitle: lineLabel == null
          ? null
          : Text(
              lineLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: colors.textDim,
                ),
            ),
      trailing: distanceM.isFinite
          ? Text(
              distanceLabel(distanceM),
              style: TextStyle(
                fontSize: 13,
                color: colors.textDim,
                fontFeatures: kTabular,
              ),
            )
          : null,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ZetSpace.sheet, 0, ZetSpace.sheet, ZetSpace.sm),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

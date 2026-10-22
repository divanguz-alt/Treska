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
Future<void> showStopSearch(
  BuildContext context, {
  required FeedController feed,
  required SettingsController settings,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: ZetMotion.quick,
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: ZetMotion.emphasized,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, _) =>
          _SearchScreen(feed: feed, settings: settings),
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
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.feed.stops,
                  widget.feed.snapshot,
                  widget.feed.position,
                ]),
                builder: (context, _) {
                  final results = _results();
                  final nearby = _text.trim().isEmpty;

                  return ListView(
                    padding: const EdgeInsets.only(bottom: ZetSpace.sheet),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            ZetSpace.sheet, 0, ZetSpace.sheet, ZetSpace.sm),
                        child: Text(
                          nearby
                              ? 'Stanice u blizini'
                              : 'Rezultati (${results.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.primary,
                            fontFamily: kMono,
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
                              fontFamily: kMono,
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

  List<_SearchResult> _results() {
    final pos = widget.feed.position.value;
    final all = widget.feed.stops.value;
    final snapshot = widget.feed.snapshot.value;
    final q = _normalize(_text.trim());

    // Lines currently on the board, so a number search can name the stop's
    // lines without a second lookup.
    final linesByStop = <String, Set<String>>{};
    for (final stop in [
      ...?snapshot?.tramStops,
      ...?snapshot?.busStops,
    ]) {
      linesByStop.putIfAbsent(stop.stop.id, () => <String>{}).addAll(
        stop.arrivals.map((a) => a.routeShortName),
      );
    }

    final scored = <_SearchResult>[];
    for (final s in all) {
      final name = _normalize(s.name);
      final lines = linesByStop[s.id] ?? const <String>{};
      final lineMatch = q.isNotEmpty &&
          lines.any((l) => _normalize(l).startsWith(q));

      if (q.isNotEmpty && !name.contains(q) && !lineMatch) continue;

      final distance = (pos.gps)
          ? haversineM(pos.lat, pos.lon, s.lat, s.lon)
          : double.infinity;
      scored.add(_SearchResult(stop: s, distanceM: distance, lines: lines));
    }

    scored.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return scored.take(q.isEmpty ? 12 : 40).toList(growable: false);
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
  final VoidCallback onBack;

  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
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
                textInputAction: TextInputAction.search,
                style: TextStyle(
                  fontSize: 16,
                  color: colors.text,
                  fontFamily: kMono,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Traži stanicu ili liniju',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    color: colors.textDim,
                    fontFamily: kMono,
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

  const _SearchResult({
    required this.stop,
    required this.distanceM,
    required this.lines,
  });
}

class _StopResult extends StatelessWidget {
  final StopInfo stop;
  final double distanceM;
  final Set<String> lines;
  final VoidCallback onTap;

  const _StopResult({
    required this.stop,
    required this.distanceM,
    required this.lines,
    required this.onTap,
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
        child: Icon(Icons.location_on, size: 20, color: colors.primary),
      ),
      title: Text(
        stop.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 16,
          color: colors.text,
          fontFamily: kMono,
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
                fontFamily: kMono,
              ),
            ),
      trailing: distanceM.isFinite
          ? Text(
              distanceLabel(distanceM),
              style: TextStyle(
                fontSize: 13,
                color: colors.textDim,
                fontFamily: kMono,
                fontFeatures: kTabular,
              ),
            )
          : null,
    );
  }
}

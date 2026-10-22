import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/feed_controller.dart';
import '../data/update_service.dart';
import '../theme_controller.dart';

/// Full-screen settings: appearance, data controls and self-update.
///
/// Kept deliberately plain (one scroll, few switches) so it can grow without
/// fighting the LED-board look of the map.
Future<void> showSettings(
  BuildContext context, {
  required FeedController feed,
  required ThemeController themeController,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _SettingsScreen(
        feed: feed,
        themeController: themeController,
      ),
    ),
  );
}

class _SettingsScreen extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;

  const _SettingsScreen({
    required this.feed,
    required this.themeController,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  final UpdateService _updates = UpdateService();
  final ScrollController _scroll = ScrollController();

  UpdateCheck? _check;
  bool _checking = false;
  bool _downloading = false;
  double _progress = -1;
  String? _status;

  @override
  void initState() {
    super.initState();
    // Check once on open so the user does not have to tap first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  @override
  void dispose() {
    _updates.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _runCheck() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = null;
    });
    final result = await _updates.check();
    if (!mounted) return;
    setState(() {
      _check = result;
      _checking = false;
    });
  }

  Future<void> _downloadAndInstall(ReleaseInfo release) async {
    setState(() {
      _downloading = true;
      _progress = -1;
      _status = 'Preuzimam ${release.apkName}…';
    });

    try {
      final file = await _updates.download(
        release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _status = 'Pokrećem instalaciju…');

      final started = await UpdateService.install(file);
      if (!mounted) return;
      if (!started) {
        setState(() {
          _status =
              'Android je blokirao instalaciju. Dopusti Treski "instalaciju '
              'nepoznatih aplikacija" pa pokušaj ponovno.';
        });
        await _offerUnknownSources();
      } else {
        setState(() => _status = 'Instalater je otvoren — potvrdi ažuriranje.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Greška: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _offerUnknownSources() async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dopusti instalaciju'),
        content: const Text(
          'Za ažuriranje Treska mora smjeti instalirati aplikacije. Otvoriti '
          'postavku "Instaliraj nepoznate aplikacije"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ne'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Otvori postavke'),
          ),
        ],
      ),
    );
    if (open == true) {
      await UpdateService.openUnknownSourcesSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    final stats = widget.feed.snapshot.value?.stats;
    final status = widget.feed.status.value;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.panel,
        foregroundColor: colors.textHi,
        elevation: 0,
        title: Text(
          'POSTAVKE',
          style: TextStyle(
            fontSize: 13,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
            fontFamily: kMono,
            color: colors.accent,
          ),
        ),
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _SectionLabel('IZGLED', colors: colors),
          _ThemeRow(controller: widget.themeController),
          const SizedBox(height: 18),

          _SectionLabel('PODACI', colors: colors),
          _InfoRow(
            'Raspored',
            status.staticReady ? 'učitan' : 'nije učitan',
            colors: colors,
          ),
          _InfoRow('Stajališta', '${status.stopCount}', colors: colors),
          _InfoRow('Aktivni polasci', '${status.tripCount}', colors: colors),
          _InfoRow(
            'Osvježavanje',
            '${stats?.refreshMs ?? 0} ms · '
                '${FeedController.pollInterval.inSeconds} s interval',
            colors: colors,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: 'OSVJEŽI RASPORED',
            icon: Icons.download,
            colors: colors,
            onTap: () {
              widget.feed.retryStatic();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ponovno preuzimam vozni red…'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Ponovno preuzima vozni red s ZET-a (~19 MB). Inače se raspored '
            'kešira 12 h i sam osvježava svakih 4 h.',
            style: TextStyle(
              fontSize: 10,
              height: 1.4,
              color: colors.textDim,
              fontFamily: kMono,
            ),
          ),
          const SizedBox(height: 22),

          _SectionLabel('AŽURIRANJE', colors: colors),
          _VersionRow(colors: colors),
          const SizedBox(height: 10),
          _UpdateBody(
            colors: colors,
            check: _check,
            checking: _checking,
            downloading: _downloading,
            progress: _progress,
            status: _status,
            onCheck: _runCheck,
            onInstall: _downloadAndInstall,
          ),
        ],
      ),
    );
  }
}

// ── Rows ─────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final ZetColors colors;
  const _SectionLabel(this.text, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          color: colors.accent,
          fontWeight: FontWeight.w700,
          fontFamily: kMono,
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final ThemeController controller;
  const _ThemeRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: colors.panel,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.brightness_6, size: 18, color: colors.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tema',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textHi,
                    fontFamily: kMono,
                  ),
                ),
              ),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 10, fontFamily: kMono),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto, size: 15),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Dan'),
                    icon: Icon(Icons.light_mode, size: 15),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Noć'),
                    icon: Icon(Icons.dark_mode, size: 15),
                  ),
                ],
                selected: {controller.mode},
                onSelectionChanged: (set) => controller.setMode(set.first),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ZetColors colors;
  const _InfoRow(this.label, this.value, {required this.colors});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: colors.textHi,
                fontFamily: kMono,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  final ZetColors colors;
  const _VersionRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    final installed = AppVersion.versionName.isEmpty
        ? '—'
        : '${AppVersion.versionName} (${AppVersion.versionCode})';
    return _InfoRow('Instalirano', installed, colors: colors);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final ZetColors colors;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1,
          fontFamily: kMono,
          fontWeight: FontWeight.w700,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.accent,
        side: BorderSide(color: colors.accent.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}

class _UpdateBody extends StatelessWidget {
  final ZetColors colors;
  final UpdateCheck? check;
  final bool checking;
  final bool downloading;
  final double progress;
  final String? status;
  final VoidCallback onCheck;
  final void Function(ReleaseInfo) onInstall;

  const _UpdateBody({
    required this.colors,
    required this.check,
    required this.checking,
    required this.downloading,
    required this.progress,
    required this.status,
    required this.onCheck,
    required this.onInstall,
  });

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final release = check?.release;
    final available = check?.updateAvailable ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                available ? Icons.new_releases : Icons.verified_outlined,
                size: 16,
                color: available ? colors.accent : colors.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  checking
                      ? 'Provjeravam…'
                      : available
                          ? 'Dostupna verzija ${release!.tag}'
                          : check?.error != null
                              ? 'Provjera nije uspjela'
                              : 'Treska je ažurna',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: available ? colors.accent : colors.textHi,
                    fontFamily: kMono,
                  ),
                ),
              ),
              if (available && release != null && release.apkSize > 0)
                Text(
                  _sizeLabel(release.apkSize),
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textDim,
                    fontFamily: kMono,
                  ),
                ),
            ],
          ),
          if (check?.error != null) ...[
            const SizedBox(height: 6),
            Text(
              check!.error!,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: colors.danger,
                fontFamily: kMono,
              ),
            ),
          ],
          if (available && release != null) ...[
            if (release.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 130),
                child: SingleChildScrollView(
                  child: Text(
                    release.body,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: colors.text,
                      fontFamily: kMono,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (downloading) ...[
              LinearProgressIndicator(
                value: progress >= 0 ? progress : null,
                minHeight: 4,
                backgroundColor: colors.panelAlt,
                color: colors.accent,
              ),
              const SizedBox(height: 6),
              Text(
                progress >= 0
                    ? '${(progress * 100).clamp(0, 100).toStringAsFixed(0)} %'
                    : 'Preuzimam…',
                style: TextStyle(
                  fontSize: 10,
                  color: colors.textDim,
                  fontFamily: kMono,
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => onInstall(release),
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: Text(
                        'PREUZMI I INSTALIRAJ',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1,
                          fontFamily: kMono,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Otvori na GitHubu',
                    onPressed: () => _openOnGithub(release.htmlUrl),
                    icon: Icon(Icons.open_in_new, size: 18,
                        color: colors.textDim),
                  ),
                ],
              ),
          ] else ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: checking ? null : onCheck,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(
                'PROVJERI AŽURIRANJA',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1,
                  fontFamily: kMono,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textHi,
                side: BorderSide(color: colors.borderStrong),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              status!,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ],
          if (release != null) ...[
            const SizedBox(height: 6),
            Text(
              'Izvor: github.com/${UpdateService.owner}/'
              '${UpdateService.repo}',
              style: TextStyle(
                fontSize: 9,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openOnGithub(String url) async {
    if (url.isEmpty) return;
    await UpdateService.openUrl(url);
  }
}

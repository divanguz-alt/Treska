import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/tokens.dart';
import '../data/feed_controller.dart';
import '../data/update_service.dart';
import '../settings_controller.dart';
import '../theme_controller.dart';

/// Full-screen settings: appearance, map radius, data controls and self-update.
Future<void> showSettings(
  BuildContext context, {
  required FeedController feed,
  required ThemeController themeController,
  required SettingsController settings,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _SettingsScreen(
        feed: feed,
        themeController: themeController,
        settings: settings,
      ),
    ),
  );
}

class _SettingsScreen extends StatefulWidget {
  final FeedController feed;
  final ThemeController themeController;
  final SettingsController settings;

  const _SettingsScreen({
    required this.feed,
    required this.themeController,
    required this.settings,
  });

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  final UpdateService _updates = UpdateService();

  UpdateCheck? _check;
  bool _checking = false;
  bool _downloading = false;
  double _progress = -1;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  @override
  void dispose() {
    _updates.dispose();
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
              'Android je blokirao instalaciju. Dopusti Treski „instalaciju '
              'nepoznatih aplikacija“ pa pokušaj ponovno.';
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
          'postavku „Instaliraj nepoznate aplikacije“?',
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
    final status = widget.feed.status.value;
    final stats = widget.feed.snapshot.value?.stats;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          'Postavke',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: colors.text,
            fontFamily: kMono,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: ZetSpace.xl),
        children: [
          _SectionLabel('IZGLED', colors: colors),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZetSpace.lg),
            child: _ThemeRow(controller: widget.themeController),
          ),
          const SizedBox(height: ZetSpace.xl),

          _SectionLabel('KARTA', colors: colors),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZetSpace.lg),
            child: _RadiusRow(controller: widget.settings),
          ),
          const SizedBox(height: ZetSpace.xl),

          _SectionLabel('PODACI', colors: colors),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZetSpace.lg),
            child: Column(
              children: [
                _InfoRow(
                  'Raspored',
                  status.staticReady ? 'učitan' : 'nije učitan',
                  colors: colors,
                ),
                _InfoRow('Stajališta', '${status.stopCount}', colors: colors),
                _InfoRow(
                    'Aktivni polasci', '${status.tripCount}', colors: colors),
                _InfoRow(
                  'Osvježavanje',
                  '${stats?.refreshMs ?? 0} ms · '
                      '${FeedController.pollInterval.inSeconds} s interval',
                  colors: colors,
                ),
                const SizedBox(height: ZetSpace.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      widget.feed.retryStatic();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ponovno preuzimam vozni red…'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Osvježi raspored'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ponovno preuzima vozni red s ZET-a (~19 MB). Inače se '
                  'raspored kešira 12 h i sam osvježava svakih 4 h.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.textDim,
                    fontFamily: kMono,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: ZetSpace.xl),

          _SectionLabel('AŽURIRANJE', colors: colors),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZetSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(
                  'Instalirano',
                  AppVersion.versionName.isEmpty
                      ? '—'
                      : '${AppVersion.versionName} '
                          '(${AppVersion.versionCode})',
                  colors: colors,
                ),
                const SizedBox(height: ZetSpace.md),
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
      padding: const EdgeInsets.fromLTRB(
          ZetSpace.sheet, ZetSpace.sm, ZetSpace.sheet, ZetSpace.sm),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colors.primary,
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tema',
              style: TextStyle(
                fontSize: 16,
                color: colors.text,
                fontFamily: kMono,
              ),
            ),
            const SizedBox(height: ZetSpace.md),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('Sustav'),
                  icon: Icon(Icons.brightness_auto, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Svijetla'),
                  icon: Icon(Icons.light_mode, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Tamna'),
                  icon: Icon(Icons.dark_mode, size: 18),
                ),
              ],
              selected: {controller.mode},
              onSelectionChanged: (set) => controller.setMode(set.first),
            ),
          ],
        );
      },
    );
  }
}

class _RadiusRow extends StatelessWidget {
  final SettingsController controller;
  const _RadiusRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = context.zet;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Radijus obližnjih stanica',
              style: TextStyle(
                fontSize: 16,
                color: colors.text,
                fontFamily: kMono,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Stanice unutar ovog radijusa prikazuju se u kartici.',
              style: TextStyle(
                fontSize: 13,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
            const SizedBox(height: ZetSpace.md),
            SegmentedButton<double>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                for (final r in SettingsController.radiusChoices)
                  ButtonSegment(
                    value: r,
                    label: Text('${r.round()} m'),
                  ),
              ],
              selected: {controller.radiusM},
              onSelectionChanged: (set) => controller.setRadius(set.first),
            ),
          ],
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
                fontSize: 14,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: colors.text,
                fontFamily: kMono,
                fontFeatures: kTabular,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.all(ZetSpace.md),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(ZetRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                available ? Icons.new_releases : Icons.verified_outlined,
                size: 18,
                color: available ? colors.primary : colors.textDim,
              ),
              const SizedBox(width: ZetSpace.sm),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: available ? colors.primary : colors.text,
                    fontFamily: kMono,
                  ),
                ),
              ),
              if (available && release != null && release.apkSize > 0)
                Text(
                  _sizeLabel(release.apkSize),
                  style: TextStyle(
                    fontSize: 13,
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
                fontSize: 13,
                height: 1.35,
                color: colors.danger,
                fontFamily: kMono,
              ),
            ),
          ],
          if (available && release != null) ...[
            if (release.body.isNotEmpty) ...[
              const SizedBox(height: ZetSpace.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Text(
                    release.body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.text,
                      fontFamily: kMono,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: ZetSpace.md),
            if (downloading) ...[
              LinearProgressIndicator(
                value: progress >= 0 ? progress : null,
                minHeight: 4,
                backgroundColor: colors.panelAlt,
                color: colors.primary,
              ),
              const SizedBox(height: 6),
              Text(
                progress >= 0
                    ? '${(progress * 100).clamp(0, 100).toStringAsFixed(0)} %'
                    : 'Preuzimam…',
                style: TextStyle(
                  fontSize: 13,
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
                      icon: const Icon(Icons.system_update_alt, size: 18),
                      label: const Text('Preuzmi i instaliraj'),
                    ),
                  ),
                  const SizedBox(width: ZetSpace.sm),
                  IconButton(
                    tooltip: 'Otvori na GitHubu',
                    onPressed: () => UpdateService.openUrl(release.htmlUrl),
                    icon: Icon(Icons.open_in_new,
                        size: 20, color: colors.textDim),
                  ),
                ],
              ),
          ] else ...[
            const SizedBox(height: ZetSpace.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: checking ? null : onCheck,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Provjeri ažuriranja'),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: ZetSpace.sm),
            Text(
              status!,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ],
          if (release != null) ...[
            const SizedBox(height: 6),
            Text(
              'Izvor: github.com/${UpdateService.owner}/${UpdateService.repo}',
              style: TextStyle(
                fontSize: 12,
                color: colors.textDim,
                fontFamily: kMono,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

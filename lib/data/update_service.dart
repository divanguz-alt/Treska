// In-app update check against GitHub Releases.
//
// The app ships its releases as GitHub Release assets with an `.apk` file
// attached. This service asks the public Releases API for the latest release,
// compares its tag (or its versionCode) with the running build and — when a
// newer one exists — downloads the APK and hands it to the Android package
// installer.
//
// No token is used: the repository (and its releases) are public. Every network
// call degrades to "check failed" instead of throwing, so an offline phone or a
// rate-limited API never blocks the Settings screen.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
/// Version of the running build, injected from the platform at startup so the
/// comparison uses exactly what the OS installed (no drift from pubspec).
class AppVersion {
  static const MethodChannel _channel =
      MethodChannel('hr.zet.zet2/updates');

  /// e.g. `2.0.0`; empty until [load] succeeds.
  static String versionName = '';

  /// e.g. `2`; -1 until [load] succeeds.
  static int versionCode = -1;

  static Future<void> load() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('version');
      versionName = '${result?['versionName'] ?? ''}';
      versionCode = (result?['versionCode'] as num?)?.toInt() ?? -1;
    } catch (_) {
      // Not on Android (tests) — leave the defaults and let the UI say so.
    }
  }
}

/// One downloadable release, already resolved to the asset we want.
class ReleaseInfo {
  final String tag;
  final String name;
  final String body;
  final String apkUrl;
  final String apkName;
  final int apkSize;
  final String htmlUrl;

  /// versionCode parsed from the tag, or -1 when the tag has no numeric part.
  final int versionCode;

  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.body,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    required this.htmlUrl,
    required this.versionCode,
  });
}

/// Outcome of a check: either a newer release, "you are current", or an error.
class UpdateCheck {
  final ReleaseInfo? release;
  final String? error;

  /// True when [release] is present and genuinely newer than this build.
  final bool updateAvailable;

  const UpdateCheck({
    this.release,
    this.error,
    this.updateAvailable = false,
  });
}

class UpdateService {
  /// The releases live here. Public repository, no auth.
  static const String owner = 'divanguz-alt';
  static const String repo = 'Treska';

  static const String _userAgent = 'Treska-updater/2.0 (Flutter; ZET timetable)';

  final http.Client _client;
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  Uri _latestUri() =>
      Uri.parse('https://api.github.com/repos/$owner/$repo/releases/latest');

  /// Asks GitHub for the newest release and decides whether it beats this build.
  Future<UpdateCheck> check() async {
    try {
      final response = await _client.get(
        _latestUri(),
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 404) {
        return const UpdateCheck(
          error: 'Repozitorij još nema objavljenih izdanja.',
        );
      }
      if (response.statusCode != 200) {
        return UpdateCheck(error: 'GitHub je vratio ${response.statusCode}.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const UpdateCheck(error: 'Neočekivan odgovor GitHuba.');
      }

      final release = _parseRelease(decoded);
      if (release == null) {
        return const UpdateCheck(error: 'Izdanje nema .apk datoteku.');
      }

      return UpdateCheck(
        release: release,
        updateAvailable: isNewer(release, AppVersion.versionCode,
            AppVersion.versionName),
      );
    } catch (e) {
      return UpdateCheck(error: 'Provjera nije uspjela: $e');
    }
  }

  /// True when [release] is newer than the installed build. The versionCode is
  /// authoritative; the tag/name is only a fallback for old releases without a
  /// numeric tag.
  static bool isNewer(ReleaseInfo release, int currentCode, String currentName) {
    if (release.versionCode >= 0 && currentCode >= 0) {
      return release.versionCode > currentCode;
    }
    return _compareNames(release.tag, currentName) > 0;
  }

  static ReleaseInfo? _parseRelease(Map<dynamic, dynamic> json) {
    final tag = '${json['tag_name'] ?? ''}';
    final name = '${json['name'] ?? tag}';
    final body = '${json['body'] ?? ''}';
    final htmlUrl = '${json['html_url'] ?? ''}';

    final assets = json['assets'];
    if (assets is! List) return null;

    Map<dynamic, dynamic>? apk;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final assetName = '${asset['name'] ?? ''}';
      if (assetName.toLowerCase().endsWith('.apk')) {
        apk = asset;
        break;
      }
    }
    if (apk == null) return null;

    return ReleaseInfo(
      tag: tag,
      name: name,
      body: body.trim(),
      apkUrl: '${apk['browser_download_url'] ?? ''}',
      apkName: '${apk['name'] ?? 'treska.apk'}',
      apkSize: (apk['size'] as num?)?.toInt() ?? 0,
      htmlUrl: htmlUrl,
      versionCode: _codeFromTag(tag),
    );
  }

  /// `v2.1.0` / `2.1.0+5` / `2.1.0` → 2, 1, 0 (major*10000 + minor*100 + patch);
  /// an explicit `+N` build number wins. Returns -1 when nothing numeric exists.
  static int debugCodeFromTag(String tag) => _codeFromTag(tag);

  static int _codeFromTag(String tag) {
    final cleaned = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final plus = cleaned.split('+');
    if (plus.length == 2) {
      final build = int.tryParse(plus[1].replaceAll(RegExp(r'[^0-9]'), ''));
      if (build != null) return build;
    }
    final core = plus.first.split('.');
    if (core.isEmpty) return -1;
    final major = int.tryParse(core[0].replaceAll(RegExp(r'[^0-9]'), ''));
    if (major == null) return -1;
    final minor = core.length > 1
        ? int.tryParse(core[1].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
        : 0;
    final patch = core.length > 2
        ? int.tryParse(core[2].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
        : 0;
    return major * 10000 + minor * 100 + patch;
  }

  static int _compareNames(String a, String b) {
    final pa = _numericParts(a);
    final pb = _numericParts(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static List<int> _numericParts(String value) => RegExp(r'\d+')
      .allMatches(value)
      .map((m) => int.tryParse(m.group(0)!) ?? 0)
      .toList();

  /// Downloads the release APK into the app cache and returns the file. Progress
  /// is reported as a 0..1 fraction (or -1 while the size is unknown).
  Future<File> download(
    ReleaseInfo release, {
    void Function(double progress)? onProgress,
  }) async {
    final response = await _client
        .send(http.Request('GET', Uri.parse(release.apkUrl))
          ..headers['User-Agent'] = _userAgent)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Preuzimanje nije uspjelo (${response.statusCode}).');
    }

    final total = response.contentLength ?? release.apkSize;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/treska-update.apk');
    if (await file.exists()) await file.delete();

    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          onProgress(total > 0 ? received / total : -1);
        }
      }
    } finally {
      await sink.close();
    }

    if (received < 1000) {
      throw Exception('Preuzeta datoteka je prazna.');
    }
    return file;
  }

  /// Hands the downloaded APK to Android's package installer. Requires the
  /// "install unknown apps" permission for Treska, which the OS asks for on the
  /// first attempt.
  static const MethodChannel _installer =
      MethodChannel('hr.zet.zet2/updates');

  static Future<bool> install(File apk) async {
    try {
      final result = await _installer.invokeMethod<bool>('install', {
        'path': apk.path,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the per-app "install unknown apps" screen so the user can grant the
  /// permission the installer needs.
  static Future<bool> openUnknownSourcesSettings() async {
    try {
      final result =
          await _installer.invokeMethod<bool>('unknownSourcesSettings');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens a URL in the system browser (used for the "open on GitHub" link).
  static Future<bool> openUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final result = await _installer
          .invokeMethod<bool>('openUrl', {'url': url});
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  void dispose() => _client.close();
}

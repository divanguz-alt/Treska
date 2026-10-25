import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zet2/data/update_service.dart';

ReleaseInfo _release({required String tag, int? size}) => ReleaseInfo(
      tag: tag,
      name: tag,
      body: '',
      apkUrl: 'https://example.com/a.apk',
      apkName: 'treska-$tag.apk',
      apkSize: size ?? 0,
      htmlUrl: 'https://example.com/release',
      versionCode: UpdateService.debugCodeFromTag(tag),
    );

void main() {
  group('tag -> versionCode', () {
    test('plain semver', () {
      expect(UpdateService.debugCodeFromTag('2.1.0'), 20100);
      expect(UpdateService.debugCodeFromTag('v1.2.3'), 10203);
    });

    test('build metadata wins', () {
      expect(UpdateService.debugCodeFromTag('2.1.0+7'), 7);
      expect(UpdateService.debugCodeFromTag('v3.0.0+build12'), 12);
    });

    test('garbage yields -1', () {
      expect(UpdateService.debugCodeFromTag('latest'), -1);
      expect(UpdateService.debugCodeFromTag(''), -1);
    });
  });

  group('isNewer', () {
    test('higher versionCode is an update', () {
      expect(
        UpdateService.isNewer(_release(tag: '2.0.1'), 20000, '2.0.0'),
        isTrue,
      );
    });

    test('same versionCode is not an update', () {
      expect(
        UpdateService.isNewer(_release(tag: '2.0.0'), 20000, '2.0.0'),
        isFalse,
      );
    });

    test('older versionCode is not an update', () {
      expect(
        UpdateService.isNewer(_release(tag: '1.0.0'), 20000, '2.0.0'),
        isFalse,
      );
    });

    test('installed build number never competes with a semver tag', () {
      // Regression: 2.1.6 installed (versionCode 16) was offered v2.1.6,
      // because the tag decoded to 20106.
      expect(
        UpdateService.isNewer(_release(tag: 'v2.1.6'), 16, '2.1.6'),
        isFalse,
      );
      expect(
        UpdateService.isNewer(_release(tag: 'v2.1.7'), 16, '2.1.6'),
        isTrue,
      );
      expect(
        UpdateService.isNewer(_release(tag: 'v2.1.5'), 16, '2.1.6'),
        isFalse,
      );
      expect(
        UpdateService.isNewer(_release(tag: 'v2.1.6+17'), 16, '2.1.6'),
        isTrue,
      );
    });

    test('falls back to name comparison when the tag has no numbers', () {
      // Realistic only when the running build could not report a versionCode.
      expect(
        UpdateService.isNewer(_release(tag: 'latest'), -1, '1.9.0'),
        isFalse,
      );
      expect(
        UpdateService.isNewer(_release(tag: 'v2.0.0'), -1, '1.9.0'),
        isTrue,
      );
      expect(
        UpdateService.isNewer(_release(tag: 'v2.0.0'), -1, '2.0.0'),
        isFalse,
      );
    });
  });

  group('check', () {
    test('parses a release with an apk asset and detects an update', () async {
      final body = jsonEncode({
        'tag_name': 'v2.1.0',
        'name': 'Treska 2.1.0',
        'body': 'Novosti',
        'html_url': 'https://github.com/divanguz-alt/Treska/releases/tag/v2.1.0',
        'assets': [
          {'name': 'notes.txt', 'size': 10, 'browser_download_url': 'x'},
          {
            'name': 'treska-2.1.0.apk',
            'size': 50000000,
            'browser_download_url': 'https://example.com/t.apk',
          },
        ],
      });
      final service = UpdateService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final result = await service.check();
      expect(result.error, isNull);
      expect(result.release!.apkName, 'treska-2.1.0.apk');
      expect(result.release!.apkSize, 50000000);
    });

    test('reports a friendly error on 404', () async {
      final service = UpdateService(
        client: MockClient((_) async => http.Response('nope', 404)),
      );
      final result = await service.check();
      expect(result.release, isNull);
      expect(result.error, contains('izdanja'));
    });

    test('reports an error when no apk asset exists', () async {
      final body = jsonEncode({
        'tag_name': 'v2.1.0',
        'assets': [
          {'name': 'source.zip', 'size': 1, 'browser_download_url': 'x'},
        ],
      });
      final service = UpdateService(
        client: MockClient((_) async => http.Response(body, 200)),
      );
      final result = await service.check();
      expect(result.error, contains('apk'));
    });
  });
}

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:Kelivo/core/providers/update_provider.dart';

const _repo = 'https://github.com/mishaqp/Moru';

Map<String, dynamic> _release({String tag = 'v0.1.4'}) => {
  'tag_name': tag,
  'html_url': '$_repo/releases/tag/$tag',
  'draft': false,
  'prerelease': false,
  'published_at': '2026-09-17T12:00:00Z',
  'body': 'Исправлен вход Codex.',
  'assets': [
    {
      'name': 'Moru-$tag-arm64-v8a-release.apk',
      'state': 'uploaded',
      'size': 12345,
      'browser_download_url':
          '$_repo/releases/download/$tag/Moru-$tag-arm64-v8a-release.apk',
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Moru',
      packageName: 'com.mishaqp.moru',
      version: '0.1.3',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  test(
    'Moru requests its own release feed and exposes the arm64 APK',
    () async {
      final urls = <Uri>[];
      final provider = UpdateProvider();
      addTearDown(provider.dispose);
      await http.runWithClient(
        provider.checkForUpdates,
        () => MockClient((request) async {
          urls.add(request.url);
          return http.Response(jsonEncode(_release()), 200);
        }),
      );
      expect(urls, hasLength(1));
      expect(urls.single.host, 'api.github.com');
      expect(urls.single.path, '/repos/mishaqp/Moru/releases/latest');
      expect(provider.available?.app, 'Moru');
      expect(provider.available?.version, '0.1.4');
      expect(
        provider.available?.downloads['android'],
        '$_repo/releases/download/v0.1.4/Moru-v0.1.4-arm64-v8a-release.apk',
      );
      expect(provider.error, isNull);
    },
  );

  for (final scenario in ['upstream', 'draft', 'prerelease', 'wrong-abi']) {
    test('does not advertise $scenario as a Moru update', () async {
      final data = _release();
      if (scenario == 'upstream') {
        data['html_url'] =
            'https://github.com/Chevey339/kelivo/releases/tag/v1.2.6';
      } else if (scenario == 'wrong-abi') {
        data['assets'] = [
          {
            'name': 'Moru-v0.1.4-x86_64-release.apk',
            'state': 'uploaded',
            'size': 12345,
            'browser_download_url':
                '$_repo/releases/download/v0.1.4/Moru-v0.1.4-x86_64-release.apk',
          },
        ];
      } else {
        data[scenario] = true;
      }
      final provider = UpdateProvider();
      addTearDown(provider.dispose);
      await http.runWithClient(
        provider.checkForUpdates,
        () => MockClient((_) async => http.Response(jsonEncode(data), 200)),
      );
      expect(provider.available, isNull);
    });
  }

  test('the installed version is not offered again', () async {
    final provider = UpdateProvider();
    addTearDown(provider.dispose);
    await http.runWithClient(
      provider.checkForUpdates,
      () => MockClient(
        (_) async => http.Response(jsonEncode(_release(tag: 'v0.1.3')), 200),
      ),
    );
    expect(provider.available, isNull);
    expect(provider.error, isNull);
  });
}

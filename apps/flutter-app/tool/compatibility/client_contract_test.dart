import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

const responsePath = String.fromEnvironment('APP_COMPATIBILITY_RESPONSES');
const sourceVersion = String.fromEnvironment('APP_COMPATIBILITY_VERSION');
const sourceBuild = String.fromEnvironment('APP_COMPATIBILITY_BUILD');
const sourceCommit = String.fromEnvironment('APP_COMPATIBILITY_COMMIT');
const folderId = '11111111-1111-4111-8111-111111111111';
const reservationId = '22222222-2222-4222-8222-222222222222';
const session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'contract-access',
  refreshToken: 'contract-refresh',
  anonymousId: 'compat-owner',
);

void main() => throw StateError(
  'Use pnpm test:app-compatibility to load the pinned client package',
);

void runClientContracts(String actualSourceCommit) {
  if (responsePath.isEmpty ||
      sourceVersion.isEmpty ||
      sourceBuild.isEmpty ||
      sourceCommit.isEmpty) {
    throw StateError(
      'Use pnpm test:app-compatibility; no synthetic fallback responses are permitted',
    );
  }
  final artifact =
      jsonDecode(File(responsePath).readAsStringSync()) as Map<String, dynamic>;
  if (artifact['schemaVersion'] != 1 ||
      artifact['producer'] != 'current-hono-api') {
    throw StateError('Expected responses from the current API contract tests');
  }
  final cases = artifact['cases'] as Map<String, dynamic>;
  Dio replay(String name, {void Function(Map<String, dynamic>)? mutate}) {
    final sample = jsonDecode(jsonEncode(cases[name])) as Map<String, dynamic>;
    if (mutate != null) mutate(sample);
    final adapter = _ContractAdapter(sample);
    final dio = Dio(BaseOptions(baseUrl: 'https://contract.invalid/api/v1'))
      ..httpClientAdapter = adapter;
    addTearDown(() {
      expect(
        adapter.calls,
        1,
        reason: 'Each old client call must exercise its recorded API contract',
      );
      dio.close();
    });
    return dio;
  }

  group('frozen App $sourceVersion ($sourceBuild)', () {
    test('uses the pinned client package instead of the current checkout', () {
      expect(actualSourceCommit, sourceCommit);
      expect(sourceCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
    });
    test(
      'C01 reads the old iOS fields and ignores build-only changes at the supported minimum',
      () async {
        final config = await HttpAppUpgradeRepository(
          replay('config-ios'),
          platform: 'ios',
        ).loadConfig();
        expect(config.upgradePrompt!.title, isNotEmpty);
        expect(config.upgradePrompt!.minVersion, '1.0.4');
        for (final version in [
          '1.0.4+161',
          '1.0.4+999',
          '$sourceVersion+$sourceBuild',
        ]) {
          expect(
            AppUpgradePolicy.evaluate(
              currentVersion: version,
              config: config,
            ).showUpdate,
            isFalse,
          );
        }
      },
    );
    test(
      'C01 disabled Google configuration is not converted into an iOS forced update',
      () async {
        final config = await HttpAppUpgradeRepository(
          replay('config-google'),
          platform: 'google',
        ).loadConfig();
        expect(config.upgradePrompt, isNull);
        expect(config.appStoreUrl, contains('play.google.com'));
        expect(
          AppUpgradePolicy.evaluate(
            currentVersion: '$sourceVersion+$sourceBuild',
            config: config,
          ).showUpdate,
          isFalse,
        );
      },
    );
    test(
      'C01 a newer recommendation cannot silently raise the supported marketing-version floor',
      () async {
        final config = await HttpAppUpgradeRepository(
          replay('config-recommended'),
        ).loadConfig();
        final decision = AppUpgradePolicy.evaluate(
          currentVersion: '$sourceVersion+$sourceBuild',
          config: config,
        );
        expect(decision.forceUpdate, isFalse);
        expect(decision.showUpdate, sourceVersion == '1.0.4');
      },
    );
    test(
      'C02 preserves the old authorization error instead of returning an empty folder list',
      () async {
        await expectLater(
          PortfolioApiClient(
            replay('folders-unauthorized'),
          ).listFolders(session),
          throwsA(
            isA<PortfolioApiException>()
                .having((e) => e.statusCode, 'status', 401)
                .having((e) => e.code, 'code', 'UNAUTHORIZED'),
          ),
        );
      },
    );
    test(
      'C04/C13 old clients read, rename and delete a folder created by the current API',
      () async {
        final listed = await PortfolioApiClient(
          replay('folders-new-write'),
        ).listFolders(session);
        expect(listed.single.id, folderId);
        expect(listed.single.name, 'Shared collection');
        expect(listed.single.isDefault, isFalse);
        final renamed = await PortfolioApiClient(
          replay('folder-old-rename'),
        ).renameFolder(session, folderId, 'Old client edit');
        expect(renamed.name, 'Old client edit');
        final reread = await PortfolioApiClient(
          replay('folders-after-old-edit'),
        ).listFolders(session);
        expect(reread.single.name, renamed.name);
        await PortfolioApiClient(
          replay('folder-old-delete'),
        ).deleteFolder(session, folderId);
        expect(
          await PortfolioApiClient(
            replay('folders-after-old-delete'),
          ).listFolders(session),
          isEmpty,
        );
      },
    );
    test(
      'C04 foreign-owner edits preserve the existing 404 contract',
      () async {
        await expectLater(
          PortfolioApiClient(
            replay('folder-foreign-rename'),
          ).renameFolder(session, folderId, 'Old client edit'),
          throwsA(
            isA<PortfolioApiException>().having(
              (e) => e.statusCode,
              'status',
              404,
            ),
          ),
        );
      },
    );
    test(
      'C06 old Free quota decoding and reservation replay cannot spend an extra slot',
      () async {
        final fresh = await ScanApiClient(
          replay('quota-fresh'),
        ).getQuota(session);
        expect(fresh.access, ScanQuotaAccess.free);
        expect(fresh.remaining, 10);
        expect(fresh.unlimited, isFalse);
        for (final name in ['quota-reserved', 'quota-replayed']) {
          final quota = await ScanApiClient(
            replay(name),
          ).reserveQuota(session, requestId: reservationId);
          expect(quota.reserved, 1);
          expect(quota.consumed, 0);
          expect(quota.remaining, 9);
        }
      },
    );
    test(
      'C06 client-only Premium never replaces trusted session entitlement',
      () async {
        await expectLater(
          ScanApiClient(
            replay('quota-premium-unverified'),
          ).getQuota(session, localPremiumVerified: true),
          throwsA(
            isA<ScanApiException>()
                .having((e) => e.code, 'code', 'ENTITLEMENT_SYNC_REQUIRED')
                .having((e) => e.statusCode, 'status', 409),
          ),
        );
      },
    );
    test(
      'optional response additions must not break old folder readers',
      () async {
        final folders = await PortfolioApiClient(
          replay(
            'folders-new-write',
            mutate: (sample) {
              sample['body']['data']['items'][0]['future_optional_field'] = {
                'badge': 'new',
              };
            },
          ),
        ).listFolders(session);
        expect(folders.single.id, folderId);
        expect(folders.single.name, 'Shared collection');
      },
    );
    test(
      'negative contract: an unknown quota access enum must not become trusted Free or Premium',
      () async {
        await expectLater(
          ScanApiClient(
            replay(
              'quota-fresh',
              mutate: (sample) {
                sample['body']['data']['access'] = 'future-access';
              },
            ),
          ).getQuota(session),
          throwsA(isA<ScanApiException>()),
        );
      },
    );
    test(
      'negative contract: incompatible upgrade field types must fail the old parser',
      () async {
        await expectLater(
          HttpAppUpgradeRepository(
            replay(
              'config-ios',
              mutate: (sample) {
                sample['body']['data']['upgrade_prompt']['force_update'] =
                    'true';
              },
            ),
          ).loadConfig(),
          throwsFormatException,
        );
      },
    );
    test(
      'negative contract: missing quota fields must not look like a successful empty response',
      () async {
        await expectLater(
          ScanApiClient(
            replay(
              'quota-fresh',
              mutate: (sample) {
                (sample['body']['data'] as Map).remove('remaining');
              },
            ),
          ).getQuota(session),
          throwsA(isA<ScanApiException>()),
        );
      },
    );
  });
}

class _ContractAdapter implements HttpClientAdapter {
  _ContractAdapter(this.sample);
  final Map<String, dynamic> sample;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final expected = Uri.parse(sample['route'] as String);
    expect(options.method, sample['method']);
    expect(options.path, expected.path);
    expect(
      options.queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      expected.queryParameters,
    );
    Object? body = options.data;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    expect(body, sample['requestBody']);
    if (expected.path != '/app-config') {
      expect(options.headers['Authorization'], 'Bearer contract-access');
    }
    if (expected.path == '/scan/quota/reserve') {
      expect(options.headers['Idempotency-Key'], reservationId);
    }
    return ResponseBody.fromString(
      jsonEncode(sample['body']),
      sample['status'] as int,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

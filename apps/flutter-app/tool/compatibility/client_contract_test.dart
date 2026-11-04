import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
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
      'C03 public game and set IDs remain strings usable by old navigation',
      () async {
        final games = await CardDataApiClient(
          replay('catalog-games'),
        ).listGames();
        expect(games.map((game) => game.id).toList(), ['25']);
        expect(games.single.name, 'Pokemon');
        final sets = await CardDataApiClient(
          replay('catalog-sets'),
        ).searchCatalogSets('', game: 'Pokemon');
        expect(sets.single.setId, '0010');
        expect(sets.single.setCode, 'C03');
        expect(sets.single.cardCount, 41);
        expect(sets.single.imageUrl, endsWith('/cards/0001.jpg'));
        final legacySets = await CardDataApiClient(
          replay('catalog-sets-legacy'),
        ).searchSets('Contract', game: 'Pokemon');
        expect(legacySets.single.setId, '0010');
        expect(legacySets.single.cardCount, 41);
      },
    );
    test(
      'C03 pagination reaches the last card without repeating the first page',
      () async {
        final first = await CardDataApiClient(
          replay('catalog-page-1'),
        ).searchCardPage('Contract Card', game: 'Pokemon', page: 1);
        final second = await CardDataApiClient(
          replay('catalog-page-2'),
        ).searchCardPage('Contract Card', game: 'Pokemon', page: 2);
        expect(first.length, 40);
        expect(first.first.cardRef, '0041');
        expect(first.last.cardRef, '0002');
        expect(first.last.priceUsd, isNull);
        expect(second.single.cardRef, '0001');
        expect(second.single.priceUsd, 0);
        expect(
          {
            ...first.map((card) => card.cardRef),
            ...second.map((card) => card.cardRef),
          }.length,
          41,
        );
        expect(
          await CardDataApiClient(
            replay('catalog-page-3'),
          ).searchCardPage('Contract Card', game: 'Pokemon', page: 3),
          isEmpty,
        );
        final setCards = await CardDataApiClient(
          replay('catalog-set-page-2'),
        ).cardsForSet('0010', game: 'Pokemon', page: 2);
        expect(setCards.single.cardRef, '0001');
      },
    );
    test(
      'C03 a published zero price is not unknown and a pending import is not a quote',
      () async {
        final zero = await CardDataApiClient(
          replay('card-zero'),
        ).getCard('0001');
        final unknown = await CardDataApiClient(
          replay('card-unknown'),
        ).getCard('0002');
        expect(zero.cardRef, '0001');
        expect(zero.cardNumber, '01');
        expect(zero.priceUsd, 0);
        expect(zero.previous7dPriceUsd, 1.5);
        expect(zero.priceAsOf, '2026-10-12');
        expect(zero.availableFinishes, contains('Normal'));
        expect(zero.imageUrl, endsWith('/cards/0001.jpg'));
        expect(unknown.cardRef, '0002');
        expect(unknown.priceUsd, isNull);
      },
    );
    test(
      'C03 market prices and partial history preserve USD zeroes without invented dates',
      () async {
        final prices = await CardDataApiClient(
          replay('prices-zero'),
        ).getMarketPrices('0001', finish: 'Normal', language: 'English');
        expect(prices.single.grader, 'Raw');
        expect(prices.single.grade, isNull);
        expect(prices.single.condition, 'Near Mint');
        expect(prices.single.price, 0);
        expect(prices.single.previous7dPriceUsd, 1.5);
        final history = await CardDataApiClient(replay('history-zero'))
            .getPriceSeries(
              '0001',
              days: 30,
              condition: 'Near Mint',
              finish: 'Normal',
            );
        expect(history.map((point) => point.date).toList(), [
          '2026-10-01',
          '2026-10-05',
          '2026-10-12',
        ]);
        expect(history.map((point) => point.price).toList(), [2, 1.5, 0]);
        expect(
          await CardDataApiClient(
            replay('prices-unknown'),
          ).getMarketPrices('0002'),
          isEmpty,
        );
        expect(
          await CardDataApiClient(
            replay('history-unknown'),
          ).getPriceSeries('0002', days: 30),
          isEmpty,
        );
      },
    );
    test(
      'C03 empty search stays distinct from validation, not-found and database errors',
      () async {
        expect(
          await CardDataApiClient(
            replay('catalog-empty'),
          ).searchCardPage('No matching contract', page: 1),
          isEmpty,
        );
        await expectLater(
          CardDataApiClient(
            replay('catalog-invalid'),
          ).searchCardPage('', page: 1),
          throwsA(
            isA<CardDataApiException>()
                .having((error) => error.statusCode, 'status', 422)
                .having((error) => error.code, 'code', 'VALIDATION_ERROR'),
          ),
        );
        await expectLater(
          CardDataApiClient(replay('card-not-found')).getCard('missing'),
          throwsA(
            isA<CardDataApiException>()
                .having((error) => error.statusCode, 'status', 404)
                .having((error) => error.code, 'code', 'NOT_FOUND'),
          ),
        );
        await expectLater(
          CardDataApiClient(
            replay('catalog-unavailable'),
          ).searchCardPage('Unavailable contract', page: 1),
          throwsA(
            isA<CardDataApiException>().having(
              (error) => error.statusCode,
              'status',
              500,
            ),
          ),
        );
      },
    );
    test(
      'C03 old currency requests keep USD conversion and reuse one valid response',
      () async {
        final rates = HttpCurrencyRateApi(replay('rates-available'));
        expect(await rates.loadUsdRate('EUR'), 0.92);
        expect(await rates.loadUsdRate('JPY'), 150);
        expect(await rates.loadUsdRate('USD'), 1);
      },
    );
    test(
      'C03 an unavailable rate must not become a successful zero conversion',
      () async {
        await expectLater(
          HttpCurrencyRateApi(replay('rates-unavailable')).loadUsdRate('EUR'),
          throwsA(isA<CurrencyRateApiException>()),
        );
      },
    );
    test(
      'C03 explicit unknown prices and optional additions stay readable',
      () async {
        final card = await CardDataApiClient(
          replay(
            'card-unknown',
            mutate: (sample) {
              sample['body']['data']['price_usd'] = null;
              sample['body']['data']['future_optional_field'] = 'added';
            },
          ),
        ).getCard('0002');
        expect(card.cardRef, '0002');
        expect(card.priceUsd, isNull);
      },
    );
    test(
      'negative C03 contract: numeric card refs cannot silently lose leading zeroes',
      () async {
        await expectLater(
          CardDataApiClient(
            replay(
              'card-zero',
              mutate: (sample) {
                sample['body']['data']['card_ref'] = 1;
              },
            ),
          ).getCard('0001'),
          throwsA(isA<CardDataApiException>()),
        );
      },
    );
    test(
      'negative C03 contract: absent items cannot become an empty catalog',
      () async {
        await expectLater(
          CardDataApiClient(
            replay(
              'catalog-page-1',
              mutate: (sample) {
                (sample['body']['data'] as Map).remove('items');
              },
            ),
          ).searchCardPage('Contract Card', game: 'Pokemon', page: 1),
          throwsA(isA<CardDataApiException>()),
        );
      },
    );
    test(
      'negative C03 contract: a foreign base must not be interpreted as a USD rate',
      () async {
        await expectLater(
          HttpCurrencyRateApi(
            replay(
              'rates-available',
              mutate: (sample) {
                sample['body']['data']['base'] = 'EUR';
              },
            ),
          ).loadUsdRate('EUR'),
          throwsA(isA<CurrencyRateApiException>()),
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
    if (expected.path.startsWith('/portfolio/') ||
        expected.path.startsWith('/scan/')) {
      expect(options.headers['Authorization'], 'Bearer contract-access');
    } else {
      expect(
        options.headers['Authorization'],
        isNull,
        reason:
            'Public catalog, rates and configuration work without a session',
      );
    }
    if (expected.path == '/scan/quota/reserve') {
      expect(options.headers['Idempotency-Key'], reservationId);
    }
    final contentType =
        sample['contentType'] as String? ?? Headers.jsonContentType;
    return ResponseBody.fromString(
      contentType.contains(Headers.jsonContentType)
          ? jsonEncode(sample['body'])
          : sample['body'] as String,
      sample['status'] as int,
      headers: {
        Headers.contentTypeHeader: [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

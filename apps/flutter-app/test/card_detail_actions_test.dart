import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/card_detail/card_detail_actions.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pluginChannel = MethodChannel('dev.fluttercommunity.plus/share');
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
  });

  test(
    'Android shares the confirmed PNG and encodes the same URL shown in preview',
    () async {
      ShareParams? shared;
      Uri? encodedUrl;
      final photo = Uint8List.fromList([1, 2, 3]);
      final poster = Uint8List.fromList([137, 80, 78, 71]);
      const origin = Rect.fromLTWH(12, 24, 44, 44);
      final actions = PluginCardDetailActions(
        const _FakeConfig(
          AppUpgradeConfig(
            cardShareBaseUrl: 'https://api-dev.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        loadThumbnail: (url) async {
          expect(
            url,
            'https://image.tcgcard.fun/cards/pokemon%3Asv3%3A125.jpg',
          );
          return XFile.fromData(photo, mimeType: 'image/jpeg');
        },
        buildPoster:
            ({
              required imageBytes,
              required name,
              required setName,
              required marketPrice,
              required cardUrl,
            }) async {
              expect(imageBytes, photo);
              expect(name, 'Charizard ex');
              expect(setName, 'Obsidian Flames');
              expect(marketPrice, r'$780.00');
              encodedUrl = cardUrl;
              return poster;
            },
        platform: TargetPlatform.android,
      );

      await actions.shareCard(
        cardRef: 'pokemon:sv3:125',
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
        sharePositionOrigin: origin,
        preview: ({required cardUrl, required posterBytes}) async {
          expect(shared, isNull);
          expect(await posterBytes, poster);
          expect(encodedUrl, cardUrl);
          expect(
            cardUrl.toString(),
            '${AppConfig.isTestEnvironment ? 'http://192.168.50.201:8080' : 'https://api-dev.tcgcard.fun'}/share/cards/pokemon:sv3:125',
          );
          return true;
        },
      );

      expect(shared?.text, isNull);
      expect(shared?.uri, isNull);
      expect(shared?.previewThumbnail, isNull);
      expect(shared?.files, hasLength(1));
      expect(shared?.files?.single.mimeType, 'image/png');
      expect(await shared!.files!.single.readAsBytes(), poster);
      expect(shared?.fileNameOverrides, ['card-ai-card.png']);
      expect(shared?.title, 'Share Charizard ex');
      expect(shared?.sharePositionOrigin, origin);
    },
  );

  test(
    'rapid taps share one poster job and allow a fresh job after closing',
    () async {
      final closed = Completer<bool>();
      var generations = 0;
      var previews = 0;
      final actions = _androidActions(
        share: (_) async => fail('Cancelled previews must not share'),
        buildPoster:
            ({
              required imageBytes,
              required name,
              required setName,
              required marketPrice,
              required cardUrl,
            }) async {
              generations++;
              return Uint8List.fromList([137, 80, 78, 71]);
            },
      );
      Future<bool> preview({
        required Uri cardUrl,
        required Future<Uint8List> posterBytes,
      }) async {
        previews++;
        await posterBytes;
        return closed.future;
      }

      final first = _shareSwitch(actions, preview: preview);
      final second = _shareSwitch(actions, preview: preview);
      await Future<void>.delayed(Duration.zero);
      expect(generations, 1);
      expect(previews, 1);
      closed.complete(false);
      await Future.wait([first, second]);
      await _shareSwitch(actions, preview: preview);
      expect(generations, 2);
      expect(previews, 2);
    },
  );

  test(
    'closing the poster preview never opens the system share sheet',
    () async {
      var shareCalls = 0;
      final actions = _androidActions(share: (_) async => shareCalls++);
      await _shareSwitch(
        actions,
        preview: ({required cardUrl, required posterBytes}) async {
          await posterBytes;
          return false;
        },
      );
      expect(shareCalls, 0);
    },
  );

  test(
    'poster failure leaves the URL available for copying without sharing broken content',
    () async {
      var shareCalls = 0;
      final actions = _androidActions(
        share: (_) async => shareCalls++,
        loadThumbnail: (_) async => throw StateError('Image unavailable'),
      );
      await _shareSwitch(
        actions,
        preview: ({required cardUrl, required posterBytes}) async {
          expect(cardUrl.toString(), '${AppConfig.cardShareBaseUrl}/560537');
          await expectLater(posterBytes, throwsStateError);
          return false;
        },
      );
      expect(shareCalls, 0);
    },
  );

  test(
    'a generation failure after cancellation is observed and cannot share',
    () async {
      final generation = Completer<Uint8List>();
      var shareCalls = 0;
      final actions = _androidActions(
        share: (_) async => shareCalls++,
        buildPoster:
            ({
              required imageBytes,
              required name,
              required setName,
              required marketPrice,
              required cardUrl,
            }) => generation.future,
      );
      await _shareSwitch(
        actions,
        preview: ({required cardUrl, required posterBytes}) async => false,
      );
      generation.completeError(StateError('Cancelled generation failed'));
      await Future<void>.delayed(Duration.zero);
      expect(shareCalls, 0);
    },
  );

  final unavailableImages = <String, CardShareThumbnailLoader>{
    'missing image': (_) async => null,
    'failed download': (_) async => throw StateError('Image unavailable'),
    'empty image': (_) async => XFile.fromData(Uint8List(0)),
    'unreadable image': (_) async =>
        XFile('card-share-image-that-does-not-exist.jpg'),
  };
  for (final scenario in unavailableImages.entries) {
    test(
      'Android never silently substitutes text for a poster with ${scenario.key}',
      () async {
        var shareCalls = 0;
        final actions = _androidActions(
          share: (_) async => shareCalls++,
          loadThumbnail: scenario.value,
        );
        await expectLater(_shareSwitch(actions), throwsA(anything));
        expect(shareCalls, 0);
      },
    );
  }

  test(
    'empty poster output is an error rather than a successful empty attachment',
    () async {
      var shareCalls = 0;
      final actions = _androidActions(
        share: (_) async => shareCalls++,
        buildPoster:
            ({
              required imageBytes,
              required name,
              required setName,
              required marketPrice,
              required cardUrl,
            }) async => Uint8List(0),
      );
      await expectLater(_shareSwitch(actions), throwsStateError);
      expect(shareCalls, 0);
    },
  );

  test(
    'an image-share error remains visible to the page error handler',
    () async {
      final actions = _androidActions(
        share: (_) async =>
            throw PlatformException(code: 'poster_share_failed'),
      );
      await expectLater(
        _shareSwitch(actions),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'poster_share_failed',
          ),
        ),
      );
    },
  );

  test(
    'iOS shares only the card URI and never generates or previews a poster',
    () async {
      ShareParams? shared;
      const origin = Rect.fromLTWH(12, 24, 44, 44);
      final actions = PluginCardDetailActions(
        const _FakeConfig(
          AppUpgradeConfig(
            cardShareBaseUrl: 'https://api.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        loadThumbnail: (_) async =>
            throw StateError('iOS must not load poster images'),
        platform: TargetPlatform.iOS,
      );
      await actions.shareCard(
        cardRef: '560537',
        name: 'Switch',
        setName: 'Deck Exclusives',
        marketPrice: r'$0.27',
        sharePositionOrigin: origin,
        preview: ({required cardUrl, required posterBytes}) async =>
            throw StateError('iOS must share directly'),
      );
      expect(
        shared?.uri,
        Uri.parse(
          '${AppConfig.isTestEnvironment ? 'http://192.168.50.201:8080' : 'https://api.tcgcard.fun'}/share/cards/560537',
        ),
      );
      expect(shared?.text, isNull);
      expect(shared?.files, isNull);
      expect(shared?.sharePositionOrigin, origin);
    },
  );

  test(
    'the iOS default launcher still sends its URI through share_plus',
    () async {
      MethodCall? call;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pluginChannel, (value) async {
            call = value;
            return '';
          });
      await _shareSwitch(
        PluginCardDetailActions(
          const _FakeConfig(AppUpgradeConfig()),
          platform: TargetPlatform.iOS,
        ),
      );
      expect(call?.method, 'share');
      expect(call?.arguments, {
        'uri': '${AppConfig.cardShareBaseUrl}/560537',
        'title': 'Share Switch',
        'subject': 'Switch',
      });
    },
  );

  test(
    'copied production settings cannot redirect test users to production',
    () async {
      ShareParams? shared;
      final actions = PluginCardDetailActions(
        const _FakeConfig(
          AppUpgradeConfig(
            cardShareBaseUrl: 'https://api.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        platform: TargetPlatform.windows,
      );
      await _shareSwitch(actions);
      expect(
        shared?.text,
        contains(
          '${AppConfig.isTestEnvironment ? 'http://192.168.50.201:8080' : 'https://api.tcgcard.fun'}/share/cards/560537',
        ),
      );
    },
  );

  test(
    'offline configuration keeps the environment share URL fallback',
    () async {
      ShareParams? shared;
      final actions = PluginCardDetailActions(
        const _FakeConfig(AppUpgradeConfig(), fail: true),
        share: (params) async => shared = params,
        platform: TargetPlatform.iOS,
      );
      await _shareSwitch(actions);
      expect(shared?.uri.toString(), '${AppConfig.cardShareBaseUrl}/560537');
    },
  );
}

PluginCardDetailActions _androidActions({
  required CardShareLauncher share,
  CardShareThumbnailLoader? loadThumbnail,
  CardSharePosterBuilder buildPoster = _buildTestPoster,
}) => PluginCardDetailActions(
  const _FakeConfig(AppUpgradeConfig()),
  share: share,
  loadThumbnail:
      loadThumbnail ?? (_) async => XFile.fromData(Uint8List.fromList([1])),
  buildPoster: buildPoster,
  platform: TargetPlatform.android,
);

Future<void> _shareSwitch(
  CardDetailActions actions, {
  CardSharePreviewPresenter? preview,
}) => actions.shareCard(
  cardRef: '560537',
  name: 'Switch',
  setName: 'Deck Exclusives',
  marketPrice: r'$0.27',
  preview: preview,
);

Future<Uint8List> _buildTestPoster({
  required Uint8List imageBytes,
  required String name,
  required String setName,
  required String marketPrice,
  required Uri cardUrl,
}) async => Uint8List.fromList([137, 80, 78, 71]);

class _FakeConfig implements AppUpgradeRepository {
  const _FakeConfig(this.config, {this.fail = false});
  final AppUpgradeConfig config;
  final bool fail;
  @override
  Future<AppUpgradeConfig> loadConfig() async {
    if (fail) throw StateError('Config is offline');
    return config;
  }
}

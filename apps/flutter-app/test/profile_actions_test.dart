import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/profile/profile_actions.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  const reviewChannel = MethodChannel('dev.britannio.in_app_review');

  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(reviewChannel, null);
  });

  test(
    'score requests the native prompt once then opens the configured review page',
    () async {
      var nativeReviewRequests = 0;
      final opened = <Uri>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reviewChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return true;
              case 'requestReview':
                nativeReviewRequests += 1;
                return null;
              default:
                throw MissingPluginException(call.method);
            }
          });
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            appStoreUrl: 'https://apps.apple.com/us/app/card-ai/id6793017224',
          ),
        ),
        launchExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await actions.requestScore();

      expect(nativeReviewRequests, 1);
      expect(opened, isEmpty);

      await actions.requestScore();

      expect(nativeReviewRequests, 1);
      expect(opened, [
        Uri.parse(
          'https://apps.apple.com/us/app/card-ai/id6793017224?action=write-review',
        ),
      ]);
    },
  );

  test(
    'score opens the review page when the native prompt is unavailable',
    () async {
      var nativeReviewRequests = 0;
      final opened = <Uri>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reviewChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return false;
              case 'requestReview':
                nativeReviewRequests += 1;
                return null;
              default:
                throw MissingPluginException(call.method);
            }
          });
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            appStoreUrl: 'https://apps.apple.com/us/app/card-ai/id6793017224',
          ),
        ),
        launchExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await actions.requestScore();

      expect(nativeReviewRequests, 0);
      expect(opened.single.queryParameters['action'], 'write-review');
    },
  );

  test(
    'score opens the review page when requesting the native prompt fails',
    () async {
      final opened = <Uri>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reviewChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return true;
              case 'requestReview':
                throw PlatformException(code: 'review-failed');
              default:
                throw MissingPluginException(call.method);
            }
          });
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            appStoreUrl: 'https://apps.apple.com/us/app/card-ai/id6793017224',
          ),
        ),
        launchExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await actions.requestScore();

      expect(opened.single.queryParameters['action'], 'write-review');
    },
  );

  test(
    'score coalesces taps while the native review request is in flight',
    () async {
      final nativeReviewStarted = Completer<void>();
      final finishNativeReview = Completer<void>();
      var nativeReviewRequests = 0;
      final opened = <Uri>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(reviewChannel, (call) async {
            switch (call.method) {
              case 'isAvailable':
                return true;
              case 'requestReview':
                nativeReviewRequests += 1;
                if (!nativeReviewStarted.isCompleted) {
                  nativeReviewStarted.complete();
                }
                await finishNativeReview.future;
                return null;
              default:
                throw MissingPluginException(call.method);
            }
          });
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            appStoreUrl: 'https://apps.apple.com/us/app/card-ai/id6793017224',
          ),
        ),
        launchExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      final firstTap = actions.requestScore();
      await nativeReviewStarted.future;
      final secondTap = actions.requestScore();
      await Future<void>.delayed(Duration.zero);

      expect(nativeReviewRequests, 1);
      expect(opened, isEmpty);

      finishNativeReview.complete();
      await Future.wait([firstTap, secondTap]);
    },
  );

  test('share uses the platform store URL from App Config', () async {
    ShareParams? shared;
    const origin = Rect.fromLTWH(10, 20, 120, 44);
    final actions = PluginProfileActions(
      _FakeAppUpgradeRepository(
        const AppUpgradeConfig(
          appStoreUrl:
              'https://play.google.com/store/apps/details?id=com.kando',
        ),
      ),
      share: (params) async => shared = params,
    );

    await actions.shareWithFriends(sharePositionOrigin: origin);

    expect(
      shared?.uri.toString(),
      'https://play.google.com/store/apps/details?id=com.kando',
    );
    expect(shared?.sharePositionOrigin, origin);
  });

  test(
    'share falls back to the public site when store URL is absent',
    () async {
      ShareParams? shared;
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
        share: (params) async => shared = params,
      );

      await actions.shareWithFriends();

      expect(shared?.uri, Uri.parse(profileShareFallbackUrl));
    },
  );

  test('legal actions prefer valid App Config URLs', () async {
    final opened = <Uri>[];
    final actions = PluginProfileActions(
      _FakeAppUpgradeRepository(
        const AppUpgradeConfig(
          termsUrl: 'https://legal.example.test/terms',
          privacyUrl: 'https://legal.example.test/privacy',
        ),
      ),
      launchExternal: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await actions.openTerms();
    await actions.openPrivacy();

    expect(opened.map((uri) => uri.toString()), [
      'https://legal.example.test/terms',
      'https://legal.example.test/privacy',
    ]);
  });

  test(
    'legal actions fall back to canonical URLs when App Config is unavailable',
    () async {
      final opened = <Uri>[];
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
        launchExternal: (uri) async {
          opened.add(uri);
          return true;
        },
      );

      await actions.openTerms();
      await actions.openPrivacy();

      expect(opened.map((uri) => uri.toString()), [
        'https://tcgcard.fun/terms',
        'https://tcgcard.fun/privacy',
      ]);
    },
  );

  test('legal actions ignore invalid App Config URLs', () async {
    final opened = <Uri>[];
    final actions = PluginProfileActions(
      _FakeAppUpgradeRepository(
        const AppUpgradeConfig(
          termsUrl: 'ftp://example.test/terms',
          privacyUrl: 'not-a-url',
        ),
      ),
      launchExternal: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await actions.openTerms();
    await actions.openPrivacy();

    expect(opened.map((uri) => uri.toString()), [
      'https://tcgcard.fun/terms',
      'https://tcgcard.fun/privacy',
    ]);
  });

  test(
    'legal action fails loudly when the operating system rejects the URL',
    () async {
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
        launchExternal: (_) async => false,
      );

      await expectLater(actions.openTerms(), throwsException);
    },
  );
}

class _FakeAppUpgradeRepository implements AppUpgradeRepository {
  const _FakeAppUpgradeRepository(this.config);

  final AppUpgradeConfig config;

  @override
  Future<AppUpgradeConfig> loadConfig() async => config;
}

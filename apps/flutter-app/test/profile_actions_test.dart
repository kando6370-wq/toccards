import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/profile/profile_actions.dart';
import 'package:share_plus/share_plus.dart';

void main() {
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

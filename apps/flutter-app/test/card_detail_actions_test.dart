import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/card_detail/card_detail_actions.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'card share sends its identity and market price to the system sheet',
    () async {
      ShareParams? shared;
      final thumbnail = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
        name: 'card.jpg',
      );
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            cardShareBaseUrl: 'https://api-dev.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        loadThumbnail: (imageUrl) async {
          expect(
            imageUrl,
            'https://image.tcgcard.fun/cards/pokemon%3Asv3%3A125.jpg',
          );
          return thumbnail;
        },
        platform: TargetPlatform.android,
      );

      await actions.shareCard(
        cardRef: 'pokemon:sv3:125',
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
      );

      expect(shared?.title, 'Share Charizard ex');
      expect(shared?.subject, 'Charizard ex');
      expect(shared?.previewThumbnail, same(thumbnail));
      expect(shared?.uri, isNull);
      expect(
        shared?.text,
        'Charizard ex\nObsidian Flames\nMarket price: \$780.00\n'
        'https://api-dev.tcgcard.fun/share/cards/pokemon:sv3:125',
      );
    },
  );

  test(
    'card share uses the production API origin in production builds',
    () async {
      ShareParams? shared;
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            cardShareBaseUrl: 'https://api.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        platform: TargetPlatform.windows,
      );

      await actions.shareCard(
        cardRef: 'pokemon:sv3:125',
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
      );

      expect(
        shared?.text,
        contains('https://api.tcgcard.fun/share/cards/pokemon:sv3:125'),
      );
    },
  );

  test(
    'iOS shares only the card URI because the system fetches web metadata',
    () async {
      ShareParams? shared;
      var thumbnailLoaded = false;
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            cardShareBaseUrl: 'https://api.tcgcard.fun/share/cards',
          ),
        ),
        share: (params) async => shared = params,
        loadThumbnail: (_) async {
          thumbnailLoaded = true;
          return null;
        },
        platform: TargetPlatform.iOS,
      );

      await actions.shareCard(
        cardRef: '560537',
        name: 'Switch',
        setName: 'Deck Exclusives',
        marketPrice: r'$0.27',
      );

      expect(
        shared?.uri,
        Uri.parse('https://api.tcgcard.fun/share/cards/560537'),
      );
      expect(shared?.text, isNull);
      expect(shared?.previewThumbnail, isNull);
      expect(thumbnailLoaded, isFalse);
    },
  );

  test(
    'card share fails before opening the system sheet when config is absent',
    () async {
      var shared = false;
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
        share: (_) async => shared = true,
        platform: TargetPlatform.android,
      );

      await expectLater(
        actions.shareCard(
          cardRef: 'pokemon:sv3:125',
          name: 'Charizard ex',
          setName: 'Obsidian Flames',
          marketPrice: r'$780.00',
        ),
        throwsStateError,
      );
      expect(shared, isFalse);
    },
  );
}

class _FakeAppUpgradeRepository implements AppUpgradeRepository {
  const _FakeAppUpgradeRepository(this.config);

  final AppUpgradeConfig config;

  @override
  Future<AppUpgradeConfig> loadConfig() async => config;
}

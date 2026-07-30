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
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(
            cardShareBaseUrl: 'https://api-dev.tcgcard.fun/api/v1/cards',
          ),
        ),
        share: (params) async => shared = params,
      );

      await actions.shareCard(
        cardRef: 'pokemon:sv3:125',
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
      );

      expect(shared?.title, 'Share Charizard ex');
      expect(shared?.subject, 'Charizard ex');
      expect(
        shared?.text,
        'Charizard ex\nObsidian Flames\nMarket price: \$780.00\n'
        'https://api-dev.tcgcard.fun/api/v1/cards/pokemon:sv3:125',
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
            cardShareBaseUrl: 'https://api.tcgcard.fun/api/v1/cards',
          ),
        ),
        share: (params) async => shared = params,
      );

      await actions.shareCard(
        cardRef: 'pokemon:sv3:125',
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
      );

      expect(
        shared?.text,
        contains('https://api.tcgcard.fun/api/v1/cards/pokemon:sv3:125'),
      );
    },
  );

  test(
    'card share fails before opening the system sheet when config is absent',
    () async {
      var shared = false;
      final actions = PluginCardDetailActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
        share: (_) async => shared = true,
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

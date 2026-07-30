import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/card_detail/card_detail_actions.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'card share sends its identity and market price to the system sheet',
    () async {
      ShareParams? shared;
      final actions = PluginCardDetailActions(
        share: (params) async => shared = params,
      );

      await actions.shareCard(
        name: 'Charizard ex',
        setName: 'Obsidian Flames',
        marketPrice: r'$780.00',
      );

      expect(shared?.title, 'Share Charizard ex');
      expect(shared?.subject, 'Charizard ex');
      expect(
        shared?.text,
        'Charizard ex\nObsidian Flames\nMarket price: \$780.00',
      );
    },
  );
}

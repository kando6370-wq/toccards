import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

final cardDetailActionsProvider = Provider<CardDetailActions>((ref) {
  return const PluginCardDetailActions();
});

abstract interface class CardDetailActions {
  Future<void> shareCard({
    required String name,
    required String setName,
    required String marketPrice,
  });
}

class PluginCardDetailActions implements CardDetailActions {
  const PluginCardDetailActions();

  @override
  Future<void> shareCard({
    required String name,
    required String setName,
    required String marketPrice,
  }) {
    return SharePlus.instance.share(
      ShareParams(
        text: '$name\n$setName\nMarket price: $marketPrice',
        subject: name,
      ),
    );
  }
}

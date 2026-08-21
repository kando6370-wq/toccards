import 'package:flutter_riverpod/flutter_riverpod.dart';

final pendingCollectionProvider =
    NotifierProvider<PendingCollectionController, List<PendingCollectionItem>>(
      PendingCollectionController.new,
    );

class PendingCollectionCard {
  const PendingCollectionCard({
    required this.id,
    required this.name,
    required this.game,
    required this.setName,
    required this.metadataLine,
    required this.variantLine,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String game;
  final String setName;
  final String metadataLine;
  final String variantLine;
  final String? imageUrl;
}

class PendingCollectionItem {
  const PendingCollectionItem({
    required this.card,
    required this.quantity,
    required this.unappliedQuantity,
  });

  final PendingCollectionCard card;
  final int quantity;
  final int unappliedQuantity;

  PendingCollectionItem copyWith({int? quantity, int? unappliedQuantity}) {
    return PendingCollectionItem(
      card: card,
      quantity: quantity ?? this.quantity,
      unappliedQuantity: unappliedQuantity ?? this.unappliedQuantity,
    );
  }
}

class PendingCollectionController
    extends Notifier<List<PendingCollectionItem>> {
  @override
  List<PendingCollectionItem> build() => const [];

  void add(PendingCollectionCard card) {
    final index = state.indexWhere((item) => item.card.id == card.id);
    if (index < 0) {
      state = [
        ...state,
        PendingCollectionItem(card: card, quantity: 1, unappliedQuantity: 1),
      ];
      return;
    }

    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index)
          state[i].copyWith(
            quantity: state[i].quantity + 1,
            unappliedQuantity: state[i].unappliedQuantity + 1,
          )
        else
          state[i],
    ];
  }

  int consumeUnappliedQuantity(String cardId) {
    final index = state.indexWhere((item) => item.card.id == cardId);
    if (index < 0) return 0;
    final quantity = state[index].unappliedQuantity;
    if (quantity == 0) return 0;
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) state[i].copyWith(unappliedQuantity: 0) else state[i],
    ];
    return quantity;
  }

  void remove(String cardId) {
    state = state.where((item) => item.card.id != cardId).toList();
  }

  void clear() {
    state = const [];
  }
}

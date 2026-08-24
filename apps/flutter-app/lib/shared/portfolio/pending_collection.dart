import 'package:flutter_riverpod/flutter_riverpod.dart';

const _pendingDraftUnset = Object();

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
    required this.id,
    required this.card,
    required this.quantity,
    this.draft,
  });

  final String id;
  final PendingCollectionCard card;
  final int quantity;
  final PendingCollectionDraft? draft;

  PendingCollectionItem copyWith({Object? draft = _pendingDraftUnset}) {
    return PendingCollectionItem(
      id: id,
      card: card,
      quantity: quantity,
      draft: draft == _pendingDraftUnset
          ? this.draft
          : draft as PendingCollectionDraft?,
    );
  }
}

class PendingCollectionDraft {
  const PendingCollectionDraft({
    required this.quantityText,
    required this.portfolioName,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.purchasePriceText,
    required this.notes,
  });

  final String quantityText;
  final String portfolioName;
  final String grader;
  final String condition;
  final String grade;
  final String language;
  final String finish;
  final String purchasePriceText;
  final String notes;
}

class PendingCollectionController
    extends Notifier<List<PendingCollectionItem>> {
  var _nextItemId = 0;

  @override
  List<PendingCollectionItem> build() {
    _nextItemId = 0;
    return const [];
  }

  void add(PendingCollectionCard card) {
    state = [
      ...state,
      PendingCollectionItem(
        id: '${card.id}:pending:${_nextItemId++}',
        card: card,
        quantity: 1,
      ),
    ];
  }

  void updateDraft(String itemId, PendingCollectionDraft draft) {
    state = [
      for (final item in state)
        if (item.id == itemId) item.copyWith(draft: draft) else item,
    ];
  }

  void remove(String itemId) {
    state = state.where((item) => item.id != itemId).toList();
  }

  void clear() {
    state = const [];
  }
}

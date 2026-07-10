import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'card_detail_models.dart';

abstract interface class CardDetailRepository {
  dynamic loadDetail(Object sessionOrCardId, [String? cardId]);
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  );
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  });
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  });
  Future<void> deleteCollectionItem(AuthSession session, String itemId);
  Future<String> addWishlist(AuthSession session, String cardRef);
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId);
}

class MockCardDetailRepository implements CardDetailRepository {
  const MockCardDetailRepository();

  @override
  dynamic loadDetail(Object sessionOrCardId, [String? cardId]) {
    final resolvedCardId = cardId ?? sessionOrCardId as String;
    final detail = _mockDetail(resolvedCardId);
    return cardId == null ? detail : Future<CardDetail>.value(detail);
  }

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) async {
    return CardCollectionItem(
      id: 'item-${detail.id}',
      cardRef: detail.id,
      folderId: 'main',
      portfolioName: 'Main',
      quantity: 1,
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: detail.language,
      finish: detail.finish,
      purchasePriceUsd: null,
      notes: 'Quick collected from CardDetail.',
    );
  }

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    return item.copyWith(cardRef: detail.id, folderId: item.folderId ?? 'main');
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    return item.copyWith(cardRef: detail.id);
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {}

  @override
  Future<String> addWishlist(AuthSession session, String cardRef) async {
    return 'wish-$cardRef';
  }

  @override
  Future<void> deleteWishlist(
    AuthSession session,
    String wishlistItemId,
  ) async {}
}

class HttpCardDetailRepository implements CardDetailRepository {
  const HttpCardDetailRepository({
    required PortfolioApi api,
    CardDetailRepository presentationRepository =
        const MockCardDetailRepository(),
  }) : _api = api,
       _presentationRepository = presentationRepository;

  final PortfolioApi _api;
  final CardDetailRepository _presentationRepository;

  @override
  Future<CardDetail> loadDetail(
    Object sessionOrCardId, [
    String? cardId,
  ]) async {
    if (sessionOrCardId is! AuthSession || cardId == null) {
      throw StateError('HttpCardDetailRepository requires an AuthSession.');
    }

    final session = sessionOrCardId;
    final detail = await _presentationRepository.loadDetail(session, cardId);
    final results = await Future.wait([
      _api.listFolders(session),
      _api.listCollectionItems(session),
      _api.listWishlistItems(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;
    return _mergeAssetState(detail, folders, items, wishlist);
  }

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) async {
    final dto = await _api.quickCollect(
      session,
      cardRef: detail.id,
      draft: _draftFromCardItem(
        detail,
        CardCollectionItem(
          id: '',
          cardRef: detail.id,
          folderId: _defaultFolderId,
          portfolioName: 'Main',
          quantity: 1,
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: detail.language,
          finish: detail.finish,
          purchasePriceUsd: null,
          notes: 'Quick collected from CardDetail.',
        ),
      ),
    );
    return _collectionItemFromDto(dto, const {});
  }

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    final dto = await _api.createCollectionItem(
      session,
      _draftFromCardItem(detail, item),
    );
    return _collectionItemFromDto(dto, {item.folderId: item.portfolioName});
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    final dto = await _api.updateCollectionItem(
      session,
      itemId: item.id,
      draft: _draftFromCardItem(detail, item),
    );
    return _collectionItemFromDto(dto, {item.folderId: item.portfolioName});
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) {
    return _api.deleteCollectionItem(session, itemId);
  }

  @override
  Future<String> addWishlist(AuthSession session, String cardRef) async {
    final dto = await _api.addWishlist(session, cardRef);
    return dto.id;
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId) {
    return _api.deleteWishlist(session, wishlistItemId);
  }
}

CardDetail _mockDetail(String cardId) {
  return switch (cardId) {
    'squirtle' => const CardDetail(
      id: 'squirtle',
      type: CardDetailType.tcg,
      name: 'Squirtle',
      game: 'Pokemon',
      setName: 'Mega Evolution Promos',
      identityLine: 'Promo #039',
      finish: 'Holofoil',
      language: 'English',
      quantity: 0,
      isWishlisted: false,
      marketPrices: [
        CardMarketPrice(
          label: 'Raw Near Mint (NM)',
          priceUsd: 32.13,
          previous30dPriceUsd: 30.67,
          previous7dPriceUsd: 31.44,
        ),
        CardMarketPrice(
          label: 'PSA 10',
          priceUsd: 124.5,
          previous30dPriceUsd: 117.2,
          previous7dPriceUsd: 121.3,
        ),
      ],
      priceSeriesByRange: {
        CardPriceRange.oneDay: [
          CardPricePoint(dateLabel: 'Yesterday', priceUsd: 31.92),
          CardPricePoint(dateLabel: 'Today', priceUsd: 32.13),
        ],
        CardPriceRange.sevenDays: [
          CardPricePoint(dateLabel: '7 days ago', priceUsd: 31.44),
          CardPricePoint(dateLabel: 'Today', priceUsd: 32.13),
        ],
        CardPriceRange.fifteenDays: [
          CardPricePoint(dateLabel: '15 days ago', priceUsd: 31.02),
          CardPricePoint(dateLabel: 'Today', priceUsd: 32.13),
        ],
        CardPriceRange.oneMonth: [
          CardPricePoint(dateLabel: '30 days ago', priceUsd: 30.67),
          CardPricePoint(dateLabel: 'Today', priceUsd: 32.13),
        ],
        CardPriceRange.threeMonths: [
          CardPricePoint(dateLabel: '90 days ago', priceUsd: 28.1),
          CardPricePoint(dateLabel: 'Today', priceUsd: 32.13),
        ],
      },
      gradedPriceSeriesByRange: {
        CardPriceRange.oneDay: [
          CardPricePoint(dateLabel: 'Yesterday', priceUsd: 123),
          CardPricePoint(dateLabel: 'Today', priceUsd: 124.5),
        ],
        CardPriceRange.sevenDays: [
          CardPricePoint(dateLabel: '7 days ago', priceUsd: 121.3),
          CardPricePoint(dateLabel: 'Today', priceUsd: 124.5),
        ],
        CardPriceRange.fifteenDays: [
          CardPricePoint(dateLabel: '15 days ago', priceUsd: 119.6),
          CardPricePoint(dateLabel: 'Today', priceUsd: 124.5),
        ],
        CardPriceRange.oneMonth: [
          CardPricePoint(dateLabel: '30 days ago', priceUsd: 117.2),
          CardPricePoint(dateLabel: 'Today', priceUsd: 124.5),
        ],
        CardPriceRange.threeMonths: [
          CardPricePoint(dateLabel: '90 days ago', priceUsd: 108),
          CardPricePoint(dateLabel: 'Today', priceUsd: 124.5),
        ],
      },
      soldListings: [
        CardSoldListing(
          dateText: '2026-07-02',
          title: 'Squirtle Promo Holofoil',
          priceUsd: 32.13,
          platform: 'eBay',
        ),
      ],
    ),
    'charizard-ex' => const CardDetail(
      id: 'charizard-ex',
      type: CardDetailType.tcg,
      name: 'Charizard ex',
      game: 'Pokemon',
      setName: 'Obsidian Flames',
      identityLine: 'Special Illustration Rare #223/197',
      finish: 'Holofoil',
      language: 'English',
      quantity: 1,
      isWishlisted: false,
      marketPrices: [
        CardMarketPrice(
          label: 'PSA 10',
          priceUsd: 780,
          previous30dPriceUsd: 721.58,
          previous7dPriceUsd: 760,
        ),
        CardMarketPrice(
          label: 'Raw Near Mint (NM)',
          priceUsd: 215,
          previous30dPriceUsd: 204.5,
          previous7dPriceUsd: 209,
        ),
      ],
      collectionItems: [
        CardCollectionItem(
          id: 'item-charizard',
          cardRef: 'charizard-ex',
          folderId: 'main',
          portfolioName: 'Main',
          quantity: 1,
          grader: 'PSA',
          condition: null,
          grade: '10',
          language: 'English',
          finish: 'Holofoil',
          purchasePriceUsd: 650,
          notes: 'Pulled from Obsidian Flames binder.',
        ),
      ],
      priceSeriesByRange: {
        CardPriceRange.oneDay: [
          CardPricePoint(dateLabel: 'Yesterday', priceUsd: 212),
          CardPricePoint(dateLabel: 'Today', priceUsd: 215),
        ],
        CardPriceRange.sevenDays: [
          CardPricePoint(dateLabel: '7 days ago', priceUsd: 209),
          CardPricePoint(dateLabel: 'Today', priceUsd: 215),
        ],
        CardPriceRange.fifteenDays: [
          CardPricePoint(dateLabel: '15 days ago', priceUsd: 207),
          CardPricePoint(dateLabel: 'Today', priceUsd: 215),
        ],
        CardPriceRange.oneMonth: [
          CardPricePoint(dateLabel: '30 days ago', priceUsd: 204.5),
          CardPricePoint(dateLabel: '14 days ago', priceUsd: 209),
          CardPricePoint(dateLabel: 'Today', priceUsd: 215),
        ],
        CardPriceRange.threeMonths: [
          CardPricePoint(dateLabel: '90 days ago', priceUsd: 180),
          CardPricePoint(dateLabel: 'Today', priceUsd: 215),
        ],
      },
      gradedPriceSeriesByRange: {
        CardPriceRange.oneDay: [
          CardPricePoint(dateLabel: 'Yesterday', priceUsd: 770),
          CardPricePoint(dateLabel: 'Today', priceUsd: 780),
        ],
        CardPriceRange.sevenDays: [
          CardPricePoint(dateLabel: '7 days ago', priceUsd: 760),
          CardPricePoint(dateLabel: 'Today', priceUsd: 780),
        ],
        CardPriceRange.fifteenDays: [
          CardPricePoint(dateLabel: '15 days ago', priceUsd: 744),
          CardPricePoint(dateLabel: 'Today', priceUsd: 780),
        ],
        CardPriceRange.oneMonth: [
          CardPricePoint(dateLabel: '30 days ago', priceUsd: 721.58),
          CardPricePoint(dateLabel: '14 days ago', priceUsd: 750),
          CardPricePoint(dateLabel: 'Today', priceUsd: 780),
        ],
        CardPriceRange.threeMonths: [
          CardPricePoint(dateLabel: '90 days ago', priceUsd: 690),
          CardPricePoint(dateLabel: 'Today', priceUsd: 780),
        ],
      },
      soldListings: [
        CardSoldListing(
          dateText: '2026-07-03',
          title: 'Charizard ex PSA 10',
          priceUsd: 780,
          platform: 'eBay',
        ),
        CardSoldListing(
          dateText: '2026-06-28',
          title: 'Charizard ex Raw Near Mint (NM)',
          priceUsd: 215,
          platform: 'TCGplayer',
        ),
      ],
    ),
    'mystery-promo' => const CardDetail(
      id: 'mystery-promo',
      type: CardDetailType.other,
      name: 'Mystery Promo',
      game: 'Pokemon',
      setName: 'Promo Vault',
      identityLine: 'Special Release',
      finish: 'Raw',
      language: 'English',
      quantity: 0,
      isWishlisted: false,
      marketPrices: [
        CardMarketPrice(
          label: 'Raw',
          priceUsd: null,
          previous30dPriceUsd: null,
        ),
      ],
    ),
    'one-piece-luffy' => const CardDetail(
      id: 'one-piece-luffy',
      type: CardDetailType.tcg,
      name: 'One Piece Manga Luffy',
      game: 'One Piece',
      setName: 'Romance Dawn',
      identityLine: 'Manga Rare #001',
      finish: 'Normal',
      language: 'Japanese',
      quantity: 0,
      isWishlisted: true,
      wishlistItemId: 'wish-one-piece-luffy',
      marketPrices: [
        CardMarketPrice(
          label: 'Raw Near Mint (NM)',
          priceUsd: 330,
          previous30dPriceUsd: 306.69,
        ),
      ],
    ),
    _ => throw StateError('Unknown card detail id: $cardId'),
  };
}

CardDetail _mergeAssetState(
  CardDetail detail,
  List<PortfolioFolderDto> folders,
  List<PortfolioItemDto> items,
  List<WishlistItemDto> wishlist,
) {
  final folderNames = {for (final folder in folders) folder.id: folder.name};
  final collectionItems = items
      .where((item) => item.cardRef == detail.id)
      .map((item) => _collectionItemFromDto(item, folderNames))
      .toList();
  WishlistItemDto? wishlistItem;
  for (final item in wishlist) {
    if (item.cardRef == detail.id) {
      wishlistItem = item;
      break;
    }
  }
  final quantity = collectionItems.fold<int>(
    0,
    (sum, item) => sum + item.quantity,
  );

  return detail.copyWith(
    quantity: quantity,
    collectionItems: collectionItems,
    isWishlisted: wishlistItem != null,
    wishlistItemId: wishlistItem?.id,
  );
}

CardCollectionItem _collectionItemFromDto(
  PortfolioItemDto dto,
  Map<String?, String> folderNames,
) {
  return CardCollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: dto.folderId,
    portfolioName: folderNames[dto.folderId] ?? dto.folderId,
    quantity: dto.quantity,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade?.toString(),
    language: dto.language,
    finish: dto.finish,
    purchasePriceUsd: dto.purchasePrice,
    notes: dto.notes ?? '',
  );
}

PortfolioItemDraftDto _draftFromCardItem(
  CardDetail detail,
  CardCollectionItem item,
) {
  return PortfolioItemDraftDto(
    folderId: item.folderId ?? _defaultFolderId,
    cardRef: item.cardRef.isEmpty ? detail.id : item.cardRef,
    objectType: _objectTypeFromDetail(detail),
    grader: item.grader,
    condition: item.condition,
    grade: double.tryParse(item.grade ?? ''),
    language: item.language,
    finish: item.finish,
    quantity: item.quantity,
    purchasePrice: item.purchasePriceUsd,
    purchaseCurrency: item.purchasePriceUsd == null ? null : 'USD',
    notes: item.notes.trim().isEmpty ? null : item.notes,
  );
}

String _objectTypeFromDetail(CardDetail detail) {
  return switch (detail.type) {
    CardDetailType.tcg => 'tcg',
    CardDetailType.sports => 'sports',
    CardDetailType.sealed => 'sealed',
    CardDetailType.other => 'other',
  };
}

const _defaultFolderId = 'main';

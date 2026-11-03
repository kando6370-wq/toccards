import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

void main() {
  test(
    'Search enriches each visible page without loading other owned cards',
    () async {
      final repository = _VisibleSearchRepository(
        cards: List.generate(80, _card),
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_ownerA),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      expect(repository.requestedCardRefs, hasLength(1));
      expect(repository.requestedCardRefs.single, {
        for (var index = 0; index < 40; index++) 'card-$index',
      });
      expect(
        container.read(searchControllerProvider).cardById('card-0').quantity,
        2,
      );
      expect(
        container.read(searchControllerProvider).isAssetReady('card-39'),
        isTrue,
      );
      expect(
        container.read(searchControllerProvider).isAssetReady('card-40'),
        isFalse,
      );

      await controller.loadNextCardPage();
      final state = container.read(searchControllerProvider);
      expect(repository.requestedCardRefs, hasLength(2));
      expect(repository.requestedCardRefs.last, {
        for (var index = 40; index < 80; index++) 'card-$index',
      });
      expect(state.cardById('card-40').quantity, 2);
      expect(state.isAssetReady('card-40'), isTrue);
    },
  );

  test(
    'Set cards load in batches of 100 and ignore unrequested asset rows',
    () async {
      final repository = _VisibleSearchRepository(cards: [_card(0)]);
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_ownerA),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      await controller.ensureCardAssets(
        List.generate(120, (index) => 'set-card-$index'),
      );

      final state = container.read(searchControllerProvider);
      expect(repository.requestedCardRefs.map((refs) => refs.length), [
        1,
        100,
        20,
      ]);
      expect(state.isAssetReady('set-card-119'), isTrue);
      expect(
        controller.resolveCard(_card(119, prefix: 'set-card')).quantity,
        2,
      );
      expect(state.isAssetReady('outside-request-0'), isFalse);
      expect(
        controller.resolveCard(_card(0, prefix: 'outside-request')).quantity,
        0,
      );
    },
  );

  test('a failed next-page asset load keeps existing card actions available', () async {
    final repository = _VisibleSearchRepository(
      cards: List.generate(80, _card),
      failCardRefs: {'card-40'},
    );
    final container = ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repository),
        searchSessionProvider.overrideWithValue(_ownerA),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);
    await controller.loadComplete;

    await controller.loadNextCardPage();
    var state = container.read(searchControllerProvider);
    expect(state.hasCardPageFailure, isTrue);
    expect(state.cardPage, 1);
    expect(state.isAssetReady('card-0'), isTrue);
    expect(state.isAssetReady('card-40'), isFalse);

    repository.failCardRefs.clear();
    await controller.retryNextCardPage();
    state = container.read(searchControllerProvider);
    expect(state.cardPage, 2);
    expect(state.isAssetReady('card-40'), isTrue);
  });

  test(
    'an old owner asset response cannot enter the next owner Search state',
    () async {
      final gate = Completer<SearchAssetSnapshot>();
      final repository = _VisibleSearchRepository(
        cards: [_card(0)],
        oldOwnerGate: gate,
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWith(
            (ref) => ref.watch(_testSessionProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      final oldLoad = controller.loadComplete;
      await Future<void>.delayed(Duration.zero);

      container.read(_testSessionProvider.notifier).switchOwner();
      container.read(searchControllerProvider);
      await controller.loadComplete;
      expect(
        container.read(searchControllerProvider).cardById('card-0').quantity,
        2,
      );

      gate.complete(
        _VisibleSearchRepository.snapshotFor(['card-0'], quantity: 9),
      );
      await oldLoad;
      final state = container.read(searchControllerProvider);
      expect(state.cardById('card-0').quantity, 2);
      expect(state.isAssetReady('card-0'), isTrue);
    },
  );

  test('an old owner Wishlist response cannot change the next account cards', () async {
    final wishlistGate = Completer<WishlistItemDto>();
    final repository = _VisibleSearchRepository(
      cards: [_card(0)],
      quantity: 0,
      wishlistGate: wishlistGate,
    );
    final container = ProviderContainer(
      overrides: [
        searchRepositoryProvider.overrideWithValue(repository),
        searchSessionProvider.overrideWith(
          (ref) => ref.watch(_testSessionProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);
    await controller.loadComplete;

    final oldMutation = controller.toggleWishlist('card-0');
    expect(
      container.read(searchControllerProvider).cardById('card-0').isWishlisted,
      isTrue,
    );
    container.read(_testSessionProvider.notifier).switchOwner();
    container.read(searchControllerProvider);
    await controller.loadComplete;

    wishlistGate.complete(
      WishlistItemDto(
        id: 'old-wish',
        cardRef: 'card-0',
        createdAt: DateTime.utc(2026, 11, 3),
      ),
    );
    expect(await oldMutation, isFalse);
    final state = container.read(searchControllerProvider);
    expect(state.cardById('card-0').isWishlisted, isFalse);
    expect(state.cardById('card-0').wishlistItemId, isNull);
  });
}

final _testSessionProvider =
    NotifierProvider<_TestSessionController, AuthSession?>(
      _TestSessionController.new,
    );

class _TestSessionController extends Notifier<AuthSession?> {
  @override
  AuthSession? build() => _ownerA;

  void switchOwner() => state = _ownerB;
}

const _ownerA = AuthSession(
  ownerType: OwnerType.user,
  userId: 'owner-a',
  accessToken: 'access-a',
  refreshToken: 'refresh-a',
);

const _ownerB = AuthSession(
  ownerType: OwnerType.user,
  userId: 'owner-b',
  accessToken: 'access-b',
  refreshToken: 'refresh-b',
);

SearchCard _card(int index, {String prefix = 'card'}) => SearchCard(
  id: '$prefix-$index',
  gameId: 'pokemon',
  type: SearchCardType.tcg,
  name: 'Card $index',
  priceUsd: null,
  previous30dPriceUsd: null,
  setName: 'Set',
  metadataLine: '$index',
  variantLine: 'Normal',
  quantity: 0,
  isWishlisted: false,
  changePercent: null,
);

class _VisibleSearchRepository extends Fake
    implements SearchVisibleAssetRepository, PaginatedSearchRepository {
  _VisibleSearchRepository({
    required this.cards,
    this.oldOwnerGate,
    this.quantity = 2,
    this.wishlistGate,
    Set<String> failCardRefs = const {},
  }) : failCardRefs = {...failCardRefs};

  final List<SearchCard> cards;
  final Completer<SearchAssetSnapshot>? oldOwnerGate;
  final int quantity;
  final Completer<WishlistItemDto>? wishlistGate;
  final Set<String> failCardRefs;
  final requestedCardRefs = <Set<String>>[];

  @override
  Future<SearchCatalog> loadCatalog() async => SearchCatalog(
    games: const [SearchGame(id: 'pokemon', label: 'Pokemon')],
    cards: cards.take(40).toList(),
    sets: const [],
  );

  @override
  Future<List<SearchCard>> searchCardPage(
    String query, {
    String? game,
    required int page,
  }) async => cards.skip((page - 1) * 40).take(40).toList();

  @override
  Future<SearchAssetSnapshot> loadVisibleAssets(
    AuthSession session,
    Iterable<String> cardRefs, {
    String? selectedFolderId,
  }) async {
    final requested = cardRefs.toSet();
    requestedCardRefs.add(requested);
    if (session.userId == 'owner-a' && oldOwnerGate != null) {
      return oldOwnerGate!.future;
    }
    if (requested.any(failCardRefs.contains)) {
      throw StateError('visible asset request failed');
    }
    return snapshotFor(requested, quantity: quantity);
  }

  @override
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef) =>
      wishlistGate!.future;

  static SearchAssetSnapshot snapshotFor(
    Iterable<String> cardRefs, {
    required int quantity,
  }) => SearchAssetSnapshot(
    folderId: 'main',
    statesByCardRef: {
      for (final cardRef in cardRefs)
        cardRef: SearchCardAssetState(
          quantity: quantity,
          collectionItemIds: quantity == 0 ? const [] : ['item-$cardRef'],
          wishlistItemId: null,
          collectionInfo: 'Near Mint (NM)',
        ),
      'outside-request-0': const SearchCardAssetState(
        quantity: 77,
        collectionItemIds: ['invalid'],
        wishlistItemId: null,
        collectionInfo: null,
      ),
    },
  );
}

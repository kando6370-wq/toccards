import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'support/in_memory_auth_storage.dart';
import 'support/in_memory_portfolio_amount_hidden_storage.dart';
import 'support/local_placeholder_auth_repository.dart';
import 'support/mock_collection_repository.dart';
import 'support/mock_card_detail_repository.dart';
import 'support/mock_home_repository.dart';

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
  });

  test(
    'http repository maps real portfolio rows into collection dashboard because Collection must show backend-owned assets',
    () async {
      final api = _FakePortfolioApiClient(
        folders: const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 100,
          ),
        ],
        items: [
          _portfolioItem(
            id: 'item-pikachu',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
          ),
          _portfolioItem(
            id: 'item-pikachu-psa',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
            grader: 'PSA',
            condition: null,
            grade: 10,
          ),
        ],
        wishlist: [
          WishlistItemDto(
            id: 'wish-luffy',
            cardRef: 'catalog:luffy-001',
            createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
          ),
        ],
      );
      final cardDataApi = _FakeCardDataApi(
        cards: const {
          'catalog:pikachu-025': CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            game: 'Pokemon',
            imageUrl: 'https://api.tcgcard.fun/api/v1/cards/25/image',
            rarity: 'Common',
          ),
          'catalog:luffy-001': CardDataCardDto(
            cardRef: 'catalog:luffy-001',
            name: 'Monkey D. Luffy',
            setName: 'Romance Dawn',
            setCode: 'OP01',
            cardNumber: '001',
            finish: 'Normal',
            language: 'Japanese',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Manga Rare',
          ),
        },
        prices: const {
          'catalog:pikachu-025': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint (NM)',
              price: 12.5,
            ),
            CardDataMarketPriceDto(
              grader: 'PSA',
              grade: 10,
              condition: null,
              price: 90,
            ),
          ],
          'catalog:luffy-001': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint (NM)',
              price: 330,
            ),
          ],
        },
        previous30dPrices: const {
          'catalog:pikachu-025': 10,
          'catalog:luffy-001': 300,
        },
      );

      final dashboard = await HttpCollectionRepository(
        api,
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.defaultFolder.id, 'main');
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
      expect(dashboard.portfolioItems.first.cardRef, 'catalog:pikachu-025');
      expect(dashboard.portfolioItems.first.name, 'Pikachu');
      expect(dashboard.portfolioItems.first.setName, 'Base Set');
      expect(dashboard.portfolioItems.first.number, '#025');
      expect(dashboard.portfolioItems.first.game, 'Pokemon');
      expect(dashboard.portfolioItems.first.marketValueUsd, 12.5);
      expect(dashboard.portfolioItems.first.previous30dPriceUsd, 10);
      expect(
        dashboard.portfolioItems.first.imageUrl,
        'https://image.tcgcard.fun/cards/catalog%3Apikachu-025.jpg',
      );
      expect(dashboard.portfolioItems.last.marketValueUsd, isNull);
      expect(dashboard.wishlistItems.single.cardRef, 'catalog:luffy-001');
      expect(dashboard.wishlistItems.single.name, 'Monkey D. Luffy');
      expect(dashboard.wishlistItems.single.marketValueUsd, 330);
    },
  );

  test(
    'http repository keeps server-enriched owned rows without calling card-data endpoints because dashboard is the source of truth',
    () async {
      final api = _FakePortfolioApiClient(
        folders: const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 100,
          ),
        ],
        items: [
          _portfolioItem(
            id: 'item-charizard',
            folderId: 'main',
            cardRef: 'charizard-ex',
          ),
          _portfolioItem(
            id: 'item-pikachu',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
          ),
        ],
        wishlist: const [],
      );
      final cardDataApi = _FakeCardDataApi(
        cards: const {
          'catalog:pikachu-025': CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Common',
          ),
        },
        prices: const {},
        cardFailures: {'charizard-ex'},
        priceFailures: {'catalog:pikachu-025'},
      );

      final dashboard = await HttpCollectionRepository(
        api,
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.portfolioItems.map((item) => item.name), [
        'charizard-ex',
        'Pikachu',
      ]);
      expect(dashboard.portfolioItems.first.marketValueUsd, isNull);
      expect(dashboard.portfolioItems.last.marketValueUsd, 12.5);
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
    },
  );

  test(
    'http repository does not substitute another condition because Collection Item value is state specific',
    () async {
      final api = _FakePortfolioApiClient(
        folders: const [
          PortfolioFolderDto(
            id: 'main',
            name: 'Main',
            isDefault: true,
            sortOrder: 100,
          ),
        ],
        items: [
          _portfolioItem(
            id: 'item-damaged',
            folderId: 'main',
            cardRef: 'catalog:pikachu-025',
            condition: 'Damaged (D)',
          ),
        ],
        wishlist: const [],
      );
      final cardDataApi = _FakeCardDataApi(
        cards: const {
          'catalog:pikachu-025': CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            imageUrl: null,
            rarity: 'Common',
          ),
        },
        prices: const {
          'catalog:pikachu-025': [
            CardDataMarketPriceDto(
              grader: 'Raw',
              grade: null,
              condition: 'Near Mint',
              price: 12.5,
            ),
          ],
        },
      );

      final dashboard = await HttpCollectionRepository(
        api,
        managementApi: api,
      ).loadDashboard(_session);

      expect(dashboard.portfolioItems.single.marketValueUsd, isNull);
      expect(dashboard.portfolioItems.single.previous30dPriceUsd, isNull);
      expect(cardDataApi.cardRefs, isEmpty);
      expect(cardDataApi.marketPriceRefs, isEmpty);
    },
  );

  test(
    'summary counts owned copies because quantity represents physical cards',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      final state = await _loadedState(container);

      expect(state.selectedTab, CollectionTab.portfolio);
      expect(state.selectedFolder.name, 'Main');
      expect(state.portfolioSummary.totalValueText, r'$1,245.00');
      expect(state.portfolioSummary.cardCount, 4);
      expect(state.portfolioSummary.gradedCount, 2);
      expect(state.visibleItems.map((item) => item.name), [
        'Charizard ex',
        'Umbreon VMAX',
        'Pikachu Promo',
      ]);
      expect(state.visibleItems.first.valueText, r'$780.00');
      expect(state.visibleItems.first.source.previous30dPriceUsd, 721.55);
      expect(state.visibleItems.first.changeText, '+8.10%');
    },
  );

  test(
    'holdings without PostgreSQL prices show an unknown total because missing values are not zero',
    () async {
      final container = _collectionContainer(
        repository: const _SingleMarketPriceCollectionRepository(null),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.portfolioSummary.totalValueText, '--');
      expect(state.visibleItems.single.valueText, '--');
      expect(state.portfolioSummary.cardCount, 2);
    },
  );

  test(
    'a published zero PostgreSQL price stays available because zero is a valid market value',
    () async {
      final container = _collectionContainer(
        repository: const _SingleMarketPriceCollectionRepository(0),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.portfolioSummary.totalValueText, r'$0.00');
      expect(state.visibleItems.single.valueText, r'$0.00');
    },
  );

  test(
    'graded summary counts graded copies rather than collection rows',
    () async {
      final container = _collectionContainer(
        repository: const _GradedQuantityCollectionRepository(),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.portfolioSummary.totalValueText, r'$1,245.00');
      expect(state.portfolioSummary.cardCount, 7);
      expect(state.portfolioSummary.gradedCount, 5);
    },
  );

  test(
    'collection preserves half grades because BGS 9.5 has its own price bucket',
    () {
      const item = CollectionItem(
        id: 'bgs-95',
        cardRef: 'card',
        folderId: 'main',
        name: 'Half Grade',
        setName: 'Set',
        number: '1',
        rarity: 'Rare',
        game: 'Pokemon',
        language: 'English',
        finish: 'Holofoil',
        grader: 'BGS',
        condition: null,
        grade: 9.5,
        quantity: 1,
        marketValueUsd: 10,
        previous30dPriceUsd: 9,
        addedAtSort: 0,
      );

      expect(item.statusText, 'BGS 9.5');
    },
  );

  test(
    'shared selected currency converts collection money while preserving percentages',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);

      expect(
        container
            .read(collectionControllerProvider)
            .portfolioSummary
            .totalValueText,
        r'$1,245.00',
      );

      container
          .read(selectedCurrencyProvider.notifier)
          .select(AppCurrency.eur.withUsdRate(0.91));
      await container.read(collectionControllerProvider.notifier).loadComplete;
      final state = container.read(collectionControllerProvider);

      expect(state.portfolioSummary.totalValueText, '€1,132.95');
      expect(state.visibleItems.first.valueText, '€709.80');
      expect(state.visibleItems.first.changeText, '+8.10%');
    },
  );

  test(
    'non-USD collection cards appear before exchange rate and do not show mislabeled USD values',
    () async {
      final rates = _PendingCurrencyRateApi();
      final container = _collectionContainer(
        repository: _CurrencyCollectionRepository(),
        currencyRateApi: rates,
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;
      for (var attempt = 0; attempt < 10; attempt++) {
        if (container.read(collectionControllerProvider).loadStatus ==
            KandoLoadStatus.content) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      final pending = container.read(collectionControllerProvider);
      expect(pending.loadStatus, KandoLoadStatus.content);
      expect(pending.currency.code, 'EUR');
      expect(pending.currency.usdRate, isNull);
      expect(pending.visibleItems, isNotEmpty);
      expect(pending.visibleItems.first.valueText, '--');
      expect(pending.portfolioSummary.totalValueText, '--');

      rates.complete(0.91);
      await container.read(collectionControllerProvider.notifier).loadComplete;
      final resolved = container.read(collectionControllerProvider);
      expect(resolved.currency.code, 'EUR');
      expect(resolved.visibleItems.first.valueText, startsWith('€'));
      expect(resolved.portfolioSummary.totalValueText, startsWith('€'));
    },
  );

  test(
    'paged collection shows the first cards before global totals without loading the legacy dashboard',
    () async {
      final repository = _PagedCollectionRepository(delaySummary: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(collectionControllerProvider.notifier);
      final firstPage = await _loadedPagedState(container);

      expect(repository.legacyLoads, 0);
      expect(repository.requestedPages, [1]);
      expect(firstPage.isPaged, isTrue);
      expect(firstPage.visibleItems, hasLength(40));
      expect(firstPage.summaryStatus, KandoLoadStatus.loading);
      expect(firstPage.portfolioSummary.totalValueText, '--');
      expect(firstPage.portfolioSummary.cardCount, isNull);

      repository.completeSummary();
      await Future<void>.delayed(Duration.zero);
      final resolved = container.read(collectionControllerProvider);
      expect(resolved.portfolioSummary.cardCount, 45);
      expect(resolved.portfolioSummary.totalValueText, r'$44.00');

      await controller.loadNextPage();
      final all = container.read(collectionControllerProvider);
      expect(repository.requestedPages, [1, 2]);
      expect(all.visibleItems, hasLength(45));
      expect(all.visibleItems.last.name, 'Item 44');
      expect(all.hasMore, isFalse);
    },
  );

  test(
    'paged collection treats summary zero and unavailable value differently',
    () async {
      final empty = _PagedCollectionRepository(
        itemCount: 0,
        totalValueUsd: 0,
        delaySummary: true,
      );
      final emptyContainer = _collectionContainer(repository: empty);
      addTearDown(emptyContainer.dispose);
      var state = await _loadedPagedState(emptyContainer);
      await Future<void>.delayed(Duration.zero);
      state = emptyContainer.read(collectionControllerProvider);
      expect(empty.requestedPages, [1]);
      expect(state.loadStatus, KandoLoadStatus.content);
      expect(state.isEmpty, isTrue);
      expect(state.portfolioSummary.totalValueText, '--');
      empty.completeSummary();
      await Future<void>.delayed(Duration.zero);
      state = emptyContainer.read(collectionControllerProvider);
      expect(state.portfolioSummary.totalValueText, r'$0.00');

      final unpriced = _PagedCollectionRepository(
        itemCount: 1,
        totalValueUsd: null,
      );
      final unpricedContainer = _collectionContainer(repository: unpriced);
      addTearDown(unpricedContainer.dispose);
      await _loadedPagedState(unpricedContainer);
      await Future<void>.delayed(Duration.zero);
      state = unpricedContainer.read(collectionControllerProvider);
      expect(state.isEmpty, isFalse);
      expect(state.portfolioSummary.totalValueText, '--');
    },
  );

  test(
    'empty filtered page shows no match before slow totals because the folder still owns cards',
    () async {
      final repository = _PagedCollectionRepository(delaySummary: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);
      controller.updateSearch('not-present');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await Future<void>.delayed(Duration.zero);

      final state = container.read(collectionControllerProvider);
      expect(state.summaryStatus, KandoLoadStatus.loading);
      expect(state.baseCount, 45);
      expect(state.total, 0);
      expect(state.isEmpty, isFalse);
      expect(state.isNoMatch, isTrue);
      expect(state.portfolioSummary.totalValueText, '--');
      repository.completeSummary();
    },
  );

  test(
    'paged collection changes tab and filter without treating one page as the whole folder',
    () async {
      final repository = _PagedCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      controller.updateSearch('Item 44');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await Future<void>.delayed(Duration.zero);
      var state = container.read(collectionControllerProvider);
      expect(state.total, 1);
      expect(state.visibleItems.single.name, 'Item 44');
      expect(state.isNoMatch, isFalse);
      expect(state.portfolioSummary.cardCount, 45);

      controller.updateSearch('missing');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await Future<void>.delayed(Duration.zero);
      state = container.read(collectionControllerProvider);
      expect(state.visibleItems, isEmpty);
      expect(state.isEmpty, isFalse);
      expect(state.isNoMatch, isTrue);

      controller.selectTab(CollectionTab.wishlist);
      await Future<void>.delayed(Duration.zero);
      state = container.read(collectionControllerProvider);
      expect(state.selectedTab, CollectionTab.wishlist);
      expect(state.visibleItems, hasLength(40));
      expect(state.total, 42);
      await controller.loadNextPage();
      expect(
        container.read(collectionControllerProvider).visibleItems,
        hasLength(42),
      );
    },
  );

  test(
    'paged collection keeps all owned Game filters when catalog games fail and another Game is on page two',
    () async {
      final repository = _PagedCollectionRepository(catalogFails: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(collectionControllerProvider.notifier);
      var state = container.read(collectionControllerProvider);

      expect(state.visibleItems, hasLength(40));
      expect(
        state.visibleItems.every((item) => item.game == 'Pokemon'),
        isTrue,
      );
      expect(state.availableGames, ['Pokemon', 'Magic: The Gathering']);

      controller.applySortAndFilters(
        sort: CollectionSort.newest,
        games: {'Magic: The Gathering'},
        languages: const {},
      );
      await Future<void>.delayed(Duration.zero);
      state = container.read(collectionControllerProvider);
      expect(state.visibleItems.single.name, 'Item 44');
      expect(state.total, 1);
    },
  );

  test(
    'paged collection preserves the initial Performance sort and retries the same second page',
    () async {
      final repository = _PagedCollectionRepository(failPageTwoOnce: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      container
          .read(collectionInitialSortProvider.notifier)
          .select(CollectionSort.performanceDesc);
      container.read(collectionPerformanceOrderProvider.notifier).select(const [
        'item-44',
        'item-0',
      ]);
      final state = await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      expect(state.selectedSort, CollectionSort.performanceDesc);
      expect(repository.requestedSorts.first, CollectionSort.performanceDesc);
      expect(repository.requestedPerformanceIds.first, ['item-44', 'item-0']);

      await controller.loadNextPage();
      expect(
        container.read(collectionControllerProvider).hasPageFailure,
        isTrue,
      );
      expect(
        container.read(collectionControllerProvider).visibleItems,
        hasLength(40),
      );
      await controller.retryNextPage();
      expect(repository.requestedPages, [1, 2, 2]);
      expect(
        container.read(collectionControllerProvider).visibleItems,
        hasLength(45),
      );
    },
  );

  test(
    'paged refresh keeps old cards visible without starting an old next page',
    () async {
      final repository = _PagedCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);
      repository.blockNextFirstPage();

      final refresh = controller.refreshPreservingContent();
      await repository.refreshPageStarted.future;
      expect(
        container.read(collectionControllerProvider).visibleItems,
        hasLength(40),
      );
      await controller.loadNextPage();
      expect(repository.requestedPages, [1, 1]);

      repository.releaseNextFirstPage();
      await refresh;
      await controller.loadNextPage();
      expect(repository.requestedPages, [1, 1, 2]);
      expect(
        container.read(collectionControllerProvider).visibleItems,
        hasLength(45),
      );
    },
  );

  test(
    'creating and deleting a folder refreshes paged totals and the selected folder page',
    () async {
      final repository = _PagedCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      final created = await controller.createFolder('New');
      expect(created.folder?.id, 'folder-new');
      await controller.loadComplete;
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(collectionControllerProvider)
            .summary
            ?.folders['folder-new']
            ?.itemCount,
        0,
      );

      await controller.selectFolder('sealed');
      expect(
        container.read(collectionControllerProvider).visibleItems,
        isEmpty,
      );
      await controller.deleteFolder('sealed');
      await controller.loadComplete;
      await Future<void>.delayed(Duration.zero);
      final state = container.read(collectionControllerProvider);
      expect(state.selectedFolderId, 'main');
      expect(state.visibleItems, hasLength(40));
      expect(state.summary?.folders.containsKey('sealed'), isFalse);
    },
  );

  test(
    'an older folder preference failure cannot roll back a later successful selection',
    () async {
      final repository = _PagedCollectionRepository(
        delaySealedPreference: true,
      );
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      final older = controller.selectFolder('sealed');
      final newer = controller.selectFolder('empty');
      await newer;
      repository.failSealedPreference();
      await older;

      expect(
        container.read(collectionControllerProvider).selectedFolderId,
        'empty',
      );
      expect(container.read(selectedPortfolioFolderProvider), 'empty');
    },
  );

  test(
    'a late exchange rate cannot switch the selected currency back after the user changes it',
    () async {
      final rates = _PendingCurrencyRateApi();
      final container = _collectionContainer(
        repository: _PagedCollectionRepository(currencyCode: 'EUR'),
        currencyRateApi: rates,
      );
      addTearDown(container.dispose);
      await _loadedPagedState(container);
      expect(container.read(collectionControllerProvider).currency.code, 'EUR');

      container
          .read(selectedCurrencyProvider.notifier)
          .select(AppCurrency.gbp.withUsdRate(1.2));
      rates.complete(0.91);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(collectionControllerProvider);
      expect(state.currency.code, 'GBP');
      expect(container.read(selectedCurrencyProvider).code, 'GBP');
    },
  );

  test(
    'paged reads from a signed-out owner cannot restore that owners cards',
    () async {
      final repository = _OwnerPagedCollectionRepository();
      final container = _collectionContainer(
        repository: repository,
        authController: _SwitchableCollectionAuthController.new,
      );
      addTearDown(container.dispose);
      container.read(collectionControllerProvider);
      expect(
        container.read(authControllerProvider).session?.accessToken,
        'old-access',
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.oldPageRequested.isCompleted, isTrue);

      (container.read(authControllerProvider.notifier)
              as _SwitchableCollectionAuthController)
          .setSession(null);
      repository.releaseOldPage();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(collectionControllerProvider).isLoading, isTrue);

      (container.read(authControllerProvider.notifier)
              as _SwitchableCollectionAuthController)
          .setSession(_newOwnerSession);
      await container.read(collectionControllerProvider.notifier).loadComplete;
      await Future<void>.delayed(Duration.zero);
      final current = container.read(collectionControllerProvider);
      expect(current.isPaged, isTrue);
      expect(current.portfolioSummary.totalValueText, r'$99.00');
    },
  );

  test(
    'late old-owner summary cannot overwrite the new owners totals',
    () async {
      final repository = _OwnerPagedCollectionRepository();
      final container = _collectionContainer(
        repository: repository,
        authController: _SwitchableCollectionAuthController.new,
      );
      addTearDown(container.dispose);
      container.read(collectionControllerProvider);
      expect(
        container.read(authControllerProvider).session?.accessToken,
        'old-access',
      );
      await Future<void>.delayed(Duration.zero);
      expect(repository.oldPageRequested.isCompleted, isTrue);
      repository.releaseOldPage();
      await container.read(collectionControllerProvider.notifier).loadComplete;

      (container.read(authControllerProvider.notifier)
              as _SwitchableCollectionAuthController)
          .setSession(_newOwnerSession);
      await container.read(collectionControllerProvider.notifier).loadComplete;
      await Future<void>.delayed(Duration.zero);
      repository.releaseOldSummary();
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(collectionControllerProvider)
            .portfolioSummary
            .totalValueText,
        r'$99.00',
      );
    },
  );

  test(
    'repository failure shows page failure and refresh restores collection',
    () async {
      final repository = _FailingThenSuccessfulCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);

      final failed = await _loadedState(container);

      expect(failed.loadStatus, KandoLoadStatus.failure);
      expect(failed.isUnavailable, isTrue);
      expect(repository.calls, 1);

      await container.read(collectionControllerProvider.notifier).refresh();
      final restored = container.read(collectionControllerProvider);

      expect(restored.loadStatus, KandoLoadStatus.content);
      expect(restored.isUnavailable, isFalse);
      expect(restored.portfolioSummary.totalValueText, r'$1,245.00');
      expect(repository.calls, 2);
    },
  );

  test('switching folders changes only Portfolio scoped items', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    await controller.selectFolder('sealed');
    final sealed = container.read(collectionControllerProvider);

    expect(sealed.selectedFolder.name, 'Sealed');
    expect(sealed.visibleItems.map((item) => item.name), [
      'Evolving Skies Booster Box',
    ]);

    controller.selectTab(CollectionTab.wishlist);
    final wishlist = container.read(collectionControllerProvider);

    expect(wishlist.visibleItems.map((item) => item.name), [
      'Lorcana Elsa',
      'One Piece Manga Luffy',
    ]);
  });

  test(
    'folder selection stays remote while amount visibility persists locally',
    () async {
      final repository = _RecordingCollectionRepository();
      final amountStorage = InMemoryPortfolioAmountHiddenStorage();
      final container = _collectionContainer(
        repository: repository,
        amountStorage: amountStorage,
      );
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      expect(await controller.selectFolder('sealed'), isTrue);
      expect(await controller.toggleAmountHidden(), isTrue);

      expect(repository.selectedFolderIds, ['sealed']);
      expect(repository.amountHiddenValues, isEmpty);
      expect(amountStorage.writes, [true]);
      final state = container.read(collectionControllerProvider);
      expect(state.selectedFolder.id, 'sealed');
      expect(state.amountHidden, isTrue);
    },
  );

  test(
    'folder selection updates shared UI before preference persistence because network latency must not block switching',
    () async {
      final repository = _DelayedPreferenceCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);

      final selection = container
          .read(collectionControllerProvider.notifier)
          .selectFolder('sealed');

      expect(
        container.read(collectionControllerProvider).selectedFolder.id,
        'sealed',
      );
      expect(container.read(selectedPortfolioFolderProvider), 'sealed');

      repository.preferenceWrite.complete();
      expect(await selection, isTrue);
    },
  );

  test(
    'folder management updates backend state and falls back to the default after deleting the selection',
    () async {
      final repository = _RecordingCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      final createResult = await controller.createFolder('Trade');
      expect(createResult.status, CreateFolderStatus.success);
      final created = createResult.folder!;
      expect(created.name, 'Trade');
      expect(await controller.renameFolder(created.id, 'Trade Binder'), isTrue);
      expect(await controller.setDefaultFolder(created.id), isTrue);
      expect(
        await controller.reorderFolders([
          created.id,
          'main',
          'sealed',
          'empty',
        ]),
        isTrue,
      );
      await controller.selectFolder('sealed');
      expect(await controller.deleteFolder('sealed'), isTrue);

      final state = container.read(collectionControllerProvider);
      expect(state.dashboard.folders.map((folder) => folder.name), [
        'Trade Binder',
        'Main',
        'Empty',
      ]);
      expect(state.dashboard.defaultFolder.id, created.id);
      expect(state.selectedFolder.id, created.id);
      expect(repository.deletedFolderIds, ['sealed']);
      expect(
        repository.selectedFolderIds,
        ['sealed'],
        reason:
            'Workers clears a deleted selected folder, so Flutter must not issue a second preference write after deletion.',
      );
    },
  );

  test(
    'folder management keeps Home loaded because the selected portfolio did not change',
    () async {
      final repository = _RecordingCollectionRepository();
      final homeRepository = _CountingHomeRepository();
      final container = _collectionContainer(
        repository: repository,
        includeFolderConsumers: true,
        homeRepository: homeRepository,
      );
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);
      container.read(homeControllerProvider);
      final detailProvider = cardDetailControllerProvider('squirtle');
      await container.read(detailProvider.notifier).loadComplete;
      final detailState = container.read(detailProvider);

      final createResult = await controller.createFolder('Trade');
      expect(createResult.status, CreateFolderStatus.success);
      final created = createResult.folder!;
      expect(await controller.renameFolder(created.id, 'Trade Binder'), isTrue);
      expect(await controller.setDefaultFolder(created.id), isTrue);
      expect(
        await controller.reorderFolders([
          created.id,
          'main',
          'sealed',
          'empty',
        ]),
        isTrue,
      );
      expect(await controller.deleteFolder('empty'), isTrue);

      expect(homeRepository.calls, 1);
      expect(container.read(detailProvider), isNot(same(detailState)));
    },
  );

  test(
    'successful folder mutations invalidate the Review editor folder source',
    () async {
      var editorFolderLoads = 0;
      final container = _collectionContainer(
        repository: _RecordingCollectionRepository(),
        loadEditorFolders: () async {
          editorFolderLoads += 1;
          return const <CardPortfolioFolder>[];
        },
      );
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 1);

      final created = (await controller.createFolder('Trade')).folder!;
      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 2);

      expect(await controller.renameFolder(created.id, 'Trade Binder'), isTrue);
      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 3);

      expect(await controller.setDefaultFolder(created.id), isTrue);
      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 4);

      expect(
        await controller.reorderFolders([
          created.id,
          'main',
          'sealed',
          'empty',
        ]),
        isTrue,
      );
      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 5);

      expect(await controller.deleteFolder('sealed'), isTrue);
      await container.read(collectionEditorFoldersProvider.future);
      expect(editorFolderLoads, 6);
    },
  );

  test(
    'server Folder limit refreshes the dashboard because another device may have consumed the final Free slot',
    () async {
      final repository = _FolderCreateFailureRepository(
        code: 'PREMIUM_REQUIRED',
      );
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);

      final result = await container
          .read(collectionControllerProvider.notifier)
          .createFolder('Trade');

      expect(result.status, CreateFolderStatus.premiumRequired);
      expect(repository.loadCalls, 2);
      expect(
        container.read(collectionControllerProvider).dashboard.folders.length,
        2,
      );
    },
  );

  test(
    'entitlement sync and ordinary failures remain distinct so the create form can preserve user input',
    () async {
      for (final entry in {
        'ENTITLEMENT_SYNC_REQUIRED': CreateFolderStatus.entitlementSyncRequired,
        'INTERNAL_ERROR': CreateFolderStatus.failed,
      }.entries) {
        final repository = _FolderCreateFailureRepository(code: entry.key);
        final container = _collectionContainer(repository: repository);
        addTearDown(container.dispose);
        await _loadedState(container);

        final result = await container
            .read(collectionControllerProvider.notifier)
            .createFolder('Trade');

        expect(result.status, entry.value);
        expect(repository.loadCalls, 1);
      }
    },
  );

  test(
    'an expired entitlement turns Folder sync rejection into the current Free limit',
    () async {
      final repository = _FolderCreateFailureRepository(
        code: 'ENTITLEMENT_SYNC_REQUIRED',
      );
      final container = _collectionContainer(
        repository: repository,
        subscriptionController: _FreeReconciliationSubscriptionController.new,
      );
      addTearDown(container.dispose);
      await _loadedState(container);

      final result = await container
          .read(collectionControllerProvider.notifier)
          .createFolder('Trade');

      expect(result.status, CreateFolderStatus.premiumRequired);
      expect(repository.loadCalls, 2);
      expect(
        container.read(subscriptionControllerProvider).premiumState,
        AppPremiumState.free,
      );
    },
  );

  test(
    'remote preference failure only rolls back settings that still use the backend',
    () async {
      final repository = _RecordingCollectionRepository(failPreferences: true);
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      expect(await controller.selectFolder('sealed'), isFalse);
      expect(await controller.toggleAmountHidden(), isTrue);

      final state = container.read(collectionControllerProvider);
      expect(state.selectedFolder.id, 'main');
      expect(state.amountHidden, isTrue);
      expect(container.read(selectedPortfolioFolderProvider), 'main');
    },
  );

  test(
    'leaving a tab resets its search and filters before returning',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      controller.updateSearch('umbreon');
      controller.applySortAndFilters(
        sort: CollectionSort.valueDesc,
        games: {'Pokemon'},
        languages: {'English'},
      );
      expect(
        container.read(collectionControllerProvider).visibleItems.single.name,
        'Umbreon VMAX',
      );

      controller.selectTab(CollectionTab.wishlist);
      expect(container.read(collectionControllerProvider).searchText, '');

      controller.updateSearch('luffy');
      expect(
        container.read(collectionControllerProvider).visibleItems.single.name,
        'One Piece Manga Luffy',
      );

      controller.selectTab(CollectionTab.portfolio);
      final portfolio = container.read(collectionControllerProvider);
      expect(portfolio.searchText, '');
      expect(portfolio.selectedSort, CollectionSort.newest);
      expect(portfolio.selectedGames, isEmpty);
      expect(portfolio.selectedLanguages, isEmpty);
      expect(portfolio.visibleItems, hasLength(3));
    },
  );

  test('sort and filters combine for the selected tab', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.applySortAndFilters(
      sort: CollectionSort.valueDesc,
      games: {'Pokemon'},
      languages: {'English'},
    );
    final filtered = container.read(collectionControllerProvider);

    expect(filtered.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
    ]);
  });

  test(
    'price ascending keeps missing values last for the Figma filter',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      controller.applySortAndFilters(
        sort: CollectionSort.valueAsc,
        games: {'Pokemon'},
        languages: {'English'},
      );

      expect(
        container
            .read(collectionControllerProvider)
            .visibleItems
            .map((item) => item.name),
        ['Umbreon VMAX', 'Charizard ex'],
      );
    },
  );

  test('amount hiding masks only the portfolio total', () async {
    final container = _collectionContainer();
    addTearDown(container.dispose);
    await _loadedState(container);
    final controller = container.read(collectionControllerProvider.notifier);

    await controller.toggleAmountHidden();
    final state = container.read(collectionControllerProvider);

    expect(state.portfolioSummary.totalValueText, hiddenMoneyText);
    expect(state.visibleItems.first.valueText, r'$780.00');
    expect(state.visibleItems.first.changeText, '+8.10%');
  });

  test(
    'empty and no-match states are distinct while Portfolio total remains the full folder value',
    () async {
      final container = _collectionContainer();
      addTearDown(container.dispose);
      await _loadedState(container);
      final controller = container.read(collectionControllerProvider.notifier);

      await controller.selectFolder('empty');
      expect(container.read(collectionControllerProvider).isEmpty, isTrue);
      expect(container.read(collectionControllerProvider).isNoMatch, isFalse);
      expect(
        container
            .read(collectionControllerProvider)
            .portfolioSummary
            .totalValueText,
        r'$0.00',
      );

      await controller.selectFolder('main');
      controller.updateSearch('missing');
      final state = container.read(collectionControllerProvider);
      expect(state.isEmpty, isFalse);
      expect(state.isNoMatch, isTrue);
      expect(state.portfolioSummary.totalValueText, r'$1,245.00');
      expect(state.portfolioSummary.cardCount, 4);
      expect(state.portfolioSummary.gradedCount, 2);
    },
  );

  test(
    'collection renders owned items before slow game filters because filters are supplemental',
    () async {
      final repository = _SlowGameCatalogCollectionRepository();
      final container = _collectionContainer(repository: repository);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      container.read(collectionControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      var state = container.read(collectionControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.visibleItems, isNotEmpty);
      expect(state.availableGames, ['Lorcana', 'One Piece', 'Pokemon']);

      repository.games.complete(['Pokemon', 'Lorcana']);
      await container.read(collectionControllerProvider.notifier).loadComplete;
      state = container.read(collectionControllerProvider);
      expect(state.availableGames, ['Pokemon', 'Lorcana']);
    },
  );

  test(
    'game filters use the database catalog order so Collection stays aligned with Search',
    () async {
      final container = _collectionContainer(
        repository: const _GameCatalogCollectionRepository([
          'Magic: The Gathering',
          'Pokemon',
          'Flesh and Blood TCG',
        ]),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.availableGames, [
        'Magic: The Gathering',
        'Pokemon',
        'Flesh and Blood TCG',
      ]);
    },
  );

  test(
    'a failed game catalog falls back to owned assets without failing Collection',
    () async {
      final container = _collectionContainer(
        repository: const _GameCatalogCollectionRepository(null),
      );
      addTearDown(container.dispose);

      final state = await _loadedState(container);

      expect(state.isUnavailable, isFalse);
      expect(state.availableGames, ['Lorcana', 'One Piece', 'Pokemon']);
    },
  );
}

ProviderContainer _collectionContainer({
  CollectionRepository repository = const MockCollectionRepository(),
  bool includeFolderConsumers = false,
  HomeRepository homeRepository = const MockHomeRepository(),
  InMemoryPortfolioAmountHiddenStorage? amountStorage,
  Future<List<CardPortfolioFolder>> Function()? loadEditorFolders,
  SubscriptionController Function()? subscriptionController,
  CurrencyRateApi? currencyRateApi,
  _SwitchableCollectionAuthController Function()? authController,
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      appCommercialPolicyProvider.overrideWithValue(
        const AppCommercialPolicy(isAndroidFreeLaunch: false),
      ),
      authStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      if (authController != null)
        authControllerProvider.overrideWith(authController),
      if (authController == null)
        authControllerProvider.overrideWith(_ReadyCollectionAuthController.new),
      collectionRepositoryProvider.overrideWithValue(repository),
      if (currencyRateApi != null)
        currencyRateApiProvider.overrideWithValue(currencyRateApi),
      subscriptionControllerProvider.overrideWith(
        subscriptionController ??
            _UnavailableReconciliationSubscriptionController.new,
      ),
      portfolioAmountHiddenStorageProvider.overrideWithValue(
        amountStorage ?? InMemoryPortfolioAmountHiddenStorage(),
      ),
      if (loadEditorFolders != null)
        collectionEditorFoldersProvider.overrideWith(
          (ref) => loadEditorFolders(),
        ),
      if (includeFolderConsumers) ...[
        homeRepositoryProvider.overrideWithValue(homeRepository),
        cardDetailRepositoryProvider.overrideWithValue(
          const MockCardDetailRepository(),
        ),
      ],
    ],
  );
}

class _ReadyCollectionAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.ready(
    session: AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'collection-access',
      refreshToken: 'collection-refresh',
      userId: 'collection-user',
      platform: AppPlatform.ios,
      dataSpaceId: 'collection-space',
    ),
  );
}

class _CurrencyCollectionRepository extends MockCollectionRepository {
  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    return (await super.loadDashboard(session)).copyWith(currencyCode: 'EUR');
  }
}

class _PendingCurrencyRateApi implements CurrencyRateApi {
  final _rate = Completer<double>();

  @override
  Future<double> loadUsdRate(String targetCurrency) {
    expect(targetCurrency, 'EUR');
    return _rate.future;
  }

  void complete(double value) => _rate.complete(value);
}

class _PagedCollectionRepository extends MockCollectionRepository
    implements CollectionPagedRepository, CollectionGameCatalogRepository {
  _PagedCollectionRepository({
    this.delaySummary = false,
    this.itemCount = 45,
    this.totalValueUsd = 44,
    this.currencyCode = 'USD',
    this.failPageTwoOnce = false,
    this.delaySealedPreference = false,
    this.catalogFails = false,
  });

  final bool delaySummary;
  final int itemCount;
  final double? totalValueUsd;
  final String currencyCode;
  final bool failPageTwoOnce;
  final bool delaySealedPreference;
  final bool catalogFails;
  final requestedPages = <int>[];
  final requestedSorts = <CollectionSort>[];
  final requestedPerformanceIds = <List<String>>[];
  final _pendingSummary = Completer<CollectionSummaryResult>();
  final _sealedPreference = Completer<void>();
  final refreshPageStarted = Completer<void>();
  Completer<void>? _nextFirstPage;
  var legacyLoads = 0;
  var _failedPageTwo = false;
  CollectionFolder? _createdFolder;
  final deletedFolderIds = <String>{};

  @override
  bool get supportsPaging => true;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) {
    legacyLoads += 1;
    throw StateError('paged collection must not download the full dashboard');
  }

  @override
  Future<CollectionPageResult> loadPage(
    AuthSession session, {
    required CollectionTab tab,
    String? folderId,
    String query = '',
    CollectionSort sort = CollectionSort.newest,
    int page = 1,
    Set<String> games = const {},
    Set<String> languages = const {},
    List<String> performanceItemIds = const [],
  }) async {
    requestedPages.add(page);
    if (page == 1 && _nextFirstPage != null) {
      if (!refreshPageStarted.isCompleted) refreshPageStarted.complete();
      await _nextFirstPage!.future;
    }
    requestedSorts.add(sort);
    requestedPerformanceIds.add(performanceItemIds);
    if (page == 2 && failPageTwoOnce && !_failedPageTwo) {
      _failedPageTwo = true;
      throw StateError('second page unavailable');
    }
    final source = await const MockCollectionRepository().loadDashboard(
      session,
    );
    final folders = [
      ...source.folders.where(
        (folder) => !deletedFolderIds.contains(folder.id),
      ),
      if (_createdFolder case final folder?) folder,
    ];
    final selectedFolder = folderId ?? 'main';
    final all = List.generate(
      tab == CollectionTab.portfolio ? itemCount : 42,
      (index) => CollectionItem(
        id: 'item-$index',
        cardRef: 'card-$index',
        folderId: tab == CollectionTab.portfolio ? 'main' : null,
        name: 'Item $index',
        setName: 'Set',
        number: '#$index',
        rarity: 'Rare',
        game: index == 44 ? 'Magic: The Gathering' : 'Pokemon',
        language: index == 0 ? 'Japanese' : 'English',
        finish: 'Normal',
        grader: 'Raw',
        condition: 'Near Mint',
        grade: null,
        quantity: 1,
        marketValueUsd: index == 0 ? 0 : 1,
        previous30dPriceUsd: 1,
        addedAtSort: 100 - index,
      ),
    );
    final filtered = all.where((item) {
      return (tab == CollectionTab.wishlist || selectedFolder == 'main') &&
          item.name.toLowerCase().contains(query.toLowerCase()) &&
          (games.isEmpty || games.contains(item.game)) &&
          (languages.isEmpty || languages.contains(item.language));
    }).toList();
    final start = (page - 1) * 40;
    final rows = start < filtered.length
        ? filtered.skip(start).take(40).toList()
        : <CollectionItem>[];
    return CollectionPageResult(
      dashboard: CollectionDashboard(
        folders: folders,
        portfolioItems: tab == CollectionTab.portfolio ? rows : const [],
        wishlistItems: tab == CollectionTab.wishlist ? rows : const [],
        currencyCode: currencyCode,
      ),
      folderId: tab == CollectionTab.portfolio ? selectedFolder : null,
      total: filtered.length,
      baseCount: tab == CollectionTab.wishlist
          ? 42
          : selectedFolder == 'main'
          ? itemCount
          : 0,
      page: page,
      pageSize: 40,
    );
  }

  @override
  Future<CollectionSummaryResult> loadSummary(AuthSession session) {
    return delaySummary ? _pendingSummary.future : Future.value(_summary());
  }

  CollectionSummaryResult _summary() => CollectionSummaryResult(
    folders: {
      'main': CollectionFolderTotals(
        folderId: 'main',
        itemCount: itemCount,
        cardCount: itemCount,
        gradedCount: 0,
        totalValueUsd: totalValueUsd,
        languages: const ['English', 'Japanese'],
      ),
      if (!deletedFolderIds.contains('sealed'))
        'sealed': const CollectionFolderTotals(
          folderId: 'sealed',
          itemCount: 0,
          cardCount: 0,
          gradedCount: 0,
          totalValueUsd: 0,
          languages: [],
        ),
      if (_createdFolder case final folder?)
        folder.id: CollectionFolderTotals(
          folderId: folder.id,
          itemCount: 0,
          cardCount: 0,
          gradedCount: 0,
          totalValueUsd: 0,
          languages: const [],
        ),
    },
    wishlistCount: 42,
    wishlistLanguages: const ['English', 'Japanese'],
    games: const ['Pokemon', 'Magic: The Gathering'],
  );

  void completeSummary() => _pendingSummary.complete(_summary());

  @override
  Future<List<String>> loadGameOptions() => catalogFails
      ? Future.error(StateError('games unavailable'))
      : Future.value(const ['Pokemon', 'Magic: The Gathering']);

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) async {
    _createdFolder = CollectionFolder(
      id: 'folder-${name.toLowerCase()}',
      name: name,
      isDefault: false,
    );
    return _createdFolder!;
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) async {
    deletedFolderIds.add(folderId);
  }

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) {
    if (lastSelectedFolderId == 'sealed' && delaySealedPreference) {
      return _sealedPreference.future;
    }
    return Future<void>.value();
  }

  void failSealedPreference() =>
      _sealedPreference.completeError(StateError('old folder switch failed'));

  void blockNextFirstPage() => _nextFirstPage = Completer<void>();

  void releaseNextFirstPage() {
    _nextFirstPage?.complete();
    _nextFirstPage = null;
  }
}

const _oldOwnerSession = AuthSession(
  ownerType: OwnerType.user,
  userId: 'old-owner',
  accessToken: 'old-access',
  refreshToken: 'old-refresh',
);

const _newOwnerSession = AuthSession(
  ownerType: OwnerType.user,
  userId: 'new-owner',
  accessToken: 'new-access',
  refreshToken: 'new-refresh',
);

class _SwitchableCollectionAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.ready(session: _oldOwnerSession);

  void setSession(AuthSession? session) {
    state = session == null
        ? const AuthState.loading()
        : AuthState.ready(session: session);
  }
}

class _OwnerPagedCollectionRepository extends _PagedCollectionRepository {
  final oldPageRequested = Completer<void>();
  final _oldPage = Completer<void>();
  final _oldSummary = Completer<CollectionSummaryResult>();

  @override
  Future<CollectionPageResult> loadPage(
    AuthSession session, {
    required CollectionTab tab,
    String? folderId,
    String query = '',
    CollectionSort sort = CollectionSort.newest,
    int page = 1,
    Set<String> games = const {},
    Set<String> languages = const {},
    List<String> performanceItemIds = const [],
  }) async {
    if (session.accessToken == 'old-access') {
      if (!oldPageRequested.isCompleted) oldPageRequested.complete();
      await _oldPage.future;
    }
    return super.loadPage(
      session,
      tab: tab,
      folderId: folderId,
      query: query,
      sort: sort,
      page: page,
      games: games,
      languages: languages,
      performanceItemIds: performanceItemIds,
    );
  }

  @override
  Future<CollectionSummaryResult> loadSummary(AuthSession session) {
    if (session.accessToken == 'old-access') return _oldSummary.future;
    return Future.value(
      const CollectionSummaryResult(
        folders: {
          'main': CollectionFolderTotals(
            folderId: 'main',
            itemCount: 45,
            cardCount: 45,
            gradedCount: 0,
            totalValueUsd: 99,
            languages: ['English', 'Japanese'],
          ),
        },
        wishlistCount: 42,
        wishlistLanguages: ['English', 'Japanese'],
      ),
    );
  }

  void releaseOldPage() => _oldPage.complete();

  void releaseOldSummary() => _oldSummary.complete(
    const CollectionSummaryResult(
      folders: {
        'main': CollectionFolderTotals(
          folderId: 'main',
          itemCount: 45,
          cardCount: 45,
          gradedCount: 0,
          totalValueUsd: 44,
          languages: ['English', 'Japanese'],
        ),
      },
      wishlistCount: 42,
      wishlistLanguages: ['English', 'Japanese'],
    ),
  );
}

class _UnavailableReconciliationSubscriptionController
    extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() async {
    return EntitlementReconciliationResult.verificationUnavailable;
  }
}

class _FreeReconciliationSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.premium);

  @override
  Future<EntitlementReconciliationResult> reconcileServerEntitlement() async {
    state = state.copyWith(premiumState: AppPremiumState.free);
    return EntitlementReconciliationResult.freeConfirmed;
  }
}

class _CountingHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    return const MockHomeRepository().loadDashboard();
  }
}

Future<CollectionState> _loadedState(ProviderContainer container) async {
  await container.read(authControllerProvider.notifier).startupComplete;
  await container.read(collectionControllerProvider.notifier).loadComplete;
  return container.read(collectionControllerProvider);
}

Future<CollectionState> _loadedPagedState(ProviderContainer container) async {
  container.read(collectionControllerProvider);
  await container.read(authControllerProvider.notifier).startupComplete;
  for (var attempt = 0; attempt < 20; attempt++) {
    await container.read(collectionControllerProvider.notifier).loadComplete;
    final state = container.read(collectionControllerProvider);
    if (!state.isLoading) return state;
    await Future<void>.delayed(Duration.zero);
  }
  return container.read(collectionControllerProvider);
}

class _RecordingCollectionRepository extends MockCollectionRepository {
  _RecordingCollectionRepository({this.failPreferences = false});

  final bool failPreferences;
  final List<String> selectedFolderIds = [];
  final List<bool> amountHiddenValues = [];
  final List<String> deletedFolderIds = [];

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) async {
    return CollectionFolder(
      id: 'folder-${name.toLowerCase()}',
      name: name,
      isDefault: false,
    );
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) async {
    deletedFolderIds.add(folderId);
  }

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    if (failPreferences) throw StateError('preferences unavailable');
    if (amountHidden != null) amountHiddenValues.add(amountHidden);
    if (lastSelectedFolderId != null) {
      selectedFolderIds.add(lastSelectedFolderId);
    }
  }
}

class _DelayedPreferenceCollectionRepository extends MockCollectionRepository {
  final preferenceWrite = Completer<void>();

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) {
    return preferenceWrite.future;
  }
}

class _FolderCreateFailureRepository extends MockCollectionRepository {
  _FolderCreateFailureRepository({required this.code});

  final String code;
  var loadCalls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    loadCalls += 1;
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(folders: dashboard.folders.take(2).toList());
  }

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name, {
    bool localPremiumVerified = false,
  }) {
    throw PortfolioApiException(
      'rejected',
      code: code,
      statusCode: code == 'ENTITLEMENT_SYNC_REQUIRED' ? 409 : null,
    );
  }
}

class _GameCatalogCollectionRepository extends MockCollectionRepository
    implements CollectionGameCatalogRepository {
  const _GameCatalogCollectionRepository(this.games);

  final List<String>? games;

  @override
  Future<List<String>> loadGameOptions() async {
    final values = games;
    if (values == null) throw StateError('game catalog unavailable');
    return values;
  }
}

class _SlowGameCatalogCollectionRepository extends MockCollectionRepository
    implements CollectionGameCatalogRepository {
  final games = Completer<List<String>>();

  @override
  Future<List<String>> loadGameOptions() => games.future;
}

class _FailingThenSuccessfulCollectionRepository
    implements CollectionRepository {
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock collection unavailable');
    }
    return const MockCollectionRepository().loadDashboard(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GradedQuantityCollectionRepository extends MockCollectionRepository {
  const _GradedQuantityCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(
      portfolioItems: [
        ...dashboard.portfolioItems,
        const CollectionItem(
          id: 'item-graded-copies',
          cardRef: 'graded-copies',
          folderId: 'main',
          name: 'Graded copies',
          setName: 'Test Set',
          number: '#001',
          rarity: 'Rare',
          game: 'Pokemon',
          language: 'English',
          finish: 'Holofoil',
          grader: 'PSA',
          condition: null,
          grade: 10,
          quantity: 3,
          marketValueUsd: null,
          previous30dPriceUsd: null,
          addedAtSort: 5,
        ),
      ],
    );
  }
}

class _SingleMarketPriceCollectionRepository extends MockCollectionRepository {
  const _SingleMarketPriceCollectionRepository(this.marketValueUsd);

  final double? marketValueUsd;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    return CollectionDashboard(
      folders: const [
        CollectionFolder(id: 'main', name: 'Main', isDefault: true),
      ],
      portfolioItems: [
        CollectionItem(
          id: 'item-price-state',
          cardRef: 'price-state',
          folderId: 'main',
          name: 'Price State',
          setName: 'PostgreSQL Set',
          number: '#001',
          rarity: 'Rare',
          game: 'Pokemon',
          language: 'English',
          finish: 'Normal',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          quantity: 2,
          marketValueUsd: marketValueUsd,
          previous30dPriceUsd: null,
          addedAtSort: 1,
        ),
      ],
      wishlistItems: const [],
    );
  }
}

class _FakePortfolioApiClient
    implements PortfolioApi, PortfolioManagementApi, CollectionDashboardApi {
  const _FakePortfolioApiClient({
    required this.folders,
    required this.items,
    required this.wishlist,
  });

  final List<PortfolioFolderDto> folders;
  final List<PortfolioItemDto> items;
  final List<WishlistItemDto> wishlist;

  @override
  Future<CollectionDashboardDto> getCollectionDashboard(
    AuthSession session,
  ) async {
    return CollectionDashboardDto(
      folders: folders,
      portfolioItems: items.map((item) {
        final pikachu = item.cardRef == 'catalog:pikachu-025';
        return CollectionDashboardItemDto(
          id: item.id,
          cardRef: item.cardRef,
          folderId: item.folderId,
          name: pikachu ? 'Pikachu' : item.cardRef,
          setName: pikachu ? 'Base Set' : 'Card data unavailable',
          cardNumber: pikachu ? '025' : '',
          rarity: pikachu ? 'Common' : '',
          game: pikachu ? 'Pokemon' : 'Unknown',
          language: item.language ?? 'Unknown',
          finish: item.finish ?? 'Unknown',
          grader: item.grader,
          condition: item.condition,
          grade: item.grade,
          quantity: item.quantity,
          marketPriceUsd:
              pikachu &&
                  item.grader == 'Raw' &&
                  item.condition == 'Near Mint (NM)'
              ? 12.5
              : null,
          previous30dPriceUsd:
              pikachu &&
                  item.grader == 'Raw' &&
                  item.condition == 'Near Mint (NM)'
              ? 10
              : null,
          folderJoinedAt: item.createdAt,
          createdAt: item.createdAt,
          imageUrl: pikachu
              ? 'https://api.tcgcard.fun/api/v1/cards/25/image'
              : null,
        );
      }).toList(),
      wishlistItems: wishlist.map((item) {
        final luffy = item.cardRef == 'catalog:luffy-001';
        return CollectionDashboardItemDto(
          id: item.id,
          cardRef: item.cardRef,
          folderId: null,
          name: luffy ? 'Monkey D. Luffy' : item.cardRef,
          setName: luffy ? 'Romance Dawn' : 'Card data unavailable',
          cardNumber: luffy ? '001' : '',
          rarity: luffy ? 'Manga Rare' : '',
          game: 'Unknown',
          language: luffy ? 'Japanese' : 'Unknown',
          finish: luffy ? 'Normal' : 'Unknown',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketPriceUsd: luffy ? 330 : null,
          previous30dPriceUsd: luffy ? 300 : null,
          folderJoinedAt: item.createdAt,
          createdAt: item.createdAt,
          imageUrl: null,
        );
      }).toList(),
      preference: const UserPreferenceDto(
        currency: 'USD',
        amountHidden: false,
        lastSelectedFolderId: null,
      ),
    );
  }

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    return folders;
  }

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async {
    return items;
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    return wishlist;
  }

  @override
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    return const UserPreferenceDto(
      currency: 'USD',
      amountHidden: false,
      lastSelectedFolderId: null,
    );
  }

  @override
  Future<WishlistItemDto> addWishlist(
    AuthSession session,
    String cardRef,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft, {
    String? idempotencyKey,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  }) async {
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCardDataApi implements CardDataApi {
  _FakeCardDataApi({
    required this.cards,
    required this.prices,
    this.cardFailures = const {},
    this.priceFailures = const {},
    this.previous30dPrices = const {},
  });

  final Map<String, CardDataCardDto> cards;
  final Map<String, List<CardDataMarketPriceDto>> prices;
  final Set<String> cardFailures;
  final Set<String> priceFailures;
  final Map<String, double> previous30dPrices;
  final List<String> cardRefs = [];
  final List<String> marketPriceRefs = [];

  @override
  Future<List<CardDataCardDto>> searchCards(
    String query, {
    String? game,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query, {String? game}) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataCardDto>> trendingCards() async {
    throw UnimplementedError();
  }

  @override
  Future<CardDataCardDto> getCard(String cardRef) async {
    cardRefs.add(cardRef);
    if (cardFailures.contains(cardRef)) {
      throw StateError('card-data card unavailable');
    }
    return cards[cardRef]!;
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) async {
    marketPriceRefs.add(cardRef);
    if (priceFailures.contains(cardRef)) {
      throw StateError('card-data prices unavailable');
    }
    return prices[cardRef] ?? const [];
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
    String? finish,
  }) async {
    final previous = previous30dPrices[cardRef];
    if (previous == null) {
      throw StateError('card-data series unavailable');
    }
    final current = prices[cardRef]!
        .firstWhere(
          (price) =>
              price.grader == grader &&
              (grade == null || price.grade == grade) &&
              (condition == null || price.condition == condition),
        )
        .price!;
    return [
      CardDataPricePointDto(date: '2026-06-15', price: previous),
      CardDataPricePointDto(date: '2026-07-15', price: current),
    ];
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    throw UnimplementedError();
  }
}

PortfolioItemDto _portfolioItem({
  required String id,
  required String folderId,
  required String cardRef,
  String grader = 'Raw',
  String? condition = 'Near Mint (NM)',
  double? grade,
}) {
  final now = DateTime.parse('2026-01-01T00:00:00.000Z');
  return PortfolioItemDto(
    id: id,
    folderId: folderId,
    cardRef: cardRef,
    objectType: 'tcg',
    grader: grader,
    condition: condition,
    grade: grade,
    language: 'English',
    finish: 'Holofoil',
    quantity: 1,
    purchasePrice: null,
    purchaseCurrency: null,
    notes: null,
    createdAt: now,
    updatedAt: now,
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'owner-access',
  refreshToken: 'owner-refresh',
  anonymousId: 'owner',
);

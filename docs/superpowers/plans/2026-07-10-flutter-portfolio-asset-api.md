# Flutter Portfolio Asset API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Flutter Collection and Card Detail asset state to the real Workers portfolio and wishlist APIs.

**Architecture:** Add a small shared Portfolio API client that sends the current Auth session token and parses Workers envelopes. Convert Collection and Card Detail repositories to async boundaries, keep the current UI state model, and use existing local card presentation data as a temporary display fallback while portfolio ownership state comes from the backend.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider`, Dio, Workers `/api/v1` portfolio endpoints, Flutter unit/widget tests.

---

## Execution Constraints

- Do not modify existing unrelated dirty files in `apps/workers-api/**` or `docs/tcg-card/**`.
- Do not change Workers routes unless a Flutter request proves a route cannot be used.
- Do not integrate Search, Home, or full card catalog API in this plan.
- Keep `MockCollectionRepository` and `MockCardDetailRepository` available for tests.
- Use `KANDO_API_BASE_URL` with default `http://127.0.0.1:8787/api/v1`, matching Auth.
- Stage only files touched by this implementation.

## Important Design Choice

Workers portfolio endpoints return real asset rows with `card_ref`, grading, quantity, purchase price, folder, and wishlist ids. They do not return full card display metadata in those responses. This plan treats backend asset state as authoritative and uses existing Flutter mock card presentation data as a temporary display fallback. Unknown backend `card_ref` values render readable fallback text based on `card_ref` until the later Search/Card data integration replaces that display source.

## File Structure

- Create: `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart`
  - Shared Dio client, DTOs, request helpers, and portfolio/wishlist methods.
- Create: `apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart`
  - Riverpod providers for Portfolio Dio and Portfolio API client.
- Create: `apps/flutter-app/test/portfolio_api_client_test.dart`
  - HTTP request, auth header, envelope parsing, and payload tests.
- Modify: `apps/flutter-app/lib/features/collection/collection_models.dart`
  - Add `cardRef` to `CollectionItem`.
- Modify: `apps/flutter-app/lib/features/collection/collection_repository.dart`
  - Convert repository to async and add `HttpCollectionRepository`.
- Modify: `apps/flutter-app/lib/features/collection/collection_controller.dart`
  - Watch Auth state, load async, expose loading/failure/content.
- Modify: `apps/flutter-app/lib/features/collection/collection_page.dart`
  - Render `KandoLoadingBlock` when loading.
- Modify: `apps/flutter-app/test/collection_controller_test.dart`
  - Await async load and override mock repository.
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`
  - Await async load and override mock repository.
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
  - Add `folderId` and `cardRef` to `CardCollectionItem`; add `wishlistItemId` to `CardDetail`.
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
  - Convert repository to async, add mutation methods, and add `HttpCardDetailRepository`.
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
  - Watch Auth state, load async, call repository mutations, and stop generating local backend ids.
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
  - Render `KandoLoadingBlock` when loading.
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`
  - Await async load, override mock repository, and add mutation-intent tests.
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`
  - Await async load and override mock repository where necessary.
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`
  - Override new async repositories where this widget test can navigate into Collection or Card Detail.
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`
  - Override new async repositories where this widget test can open Card Detail or Collection.

---

### Task 1: Shared Portfolio API Client

**Files:**
- Create: `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart`
- Create: `apps/flutter-app/test/portfolio_api_client_test.dart`

- [ ] **Step 1: Write failing API client tests**

Create `apps/flutter-app/test/portfolio_api_client_test.dart` with tests that use a custom `HttpClientAdapter`, following the pattern already used in `apps/flutter-app/test/auth_repository_test.dart`.

```dart
test('listFolders attaches bearer token because portfolio rows are owner scoped', () async {
  final adapter = _RecordingAdapter((request) {
    expect(request.method, 'GET');
    expect(request.path, '/portfolio/folders');
    expect(request.authorization, 'Bearer owner-access');
    return _json(200, {
      'success': true,
      'data': {
        'items': [
          {
            'id': 'main',
            'name': 'Main',
            'is_default': true,
            'sort_order': 100,
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
          },
        ],
      },
    });
  });
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = adapter;

  final folders = await PortfolioApiClient(dio).listFolders(_session);

  expect(folders.single.id, 'main');
  expect(folders.single.name, 'Main');
  expect(folders.single.isDefault, isTrue);
});
```

```dart
test('quickCollect posts path card ref and body fields required by Workers', () async {
  final adapter = _RecordingAdapter((request) {
    expect(request.method, 'POST');
    expect(request.path, '/cards/squirtle/collect');
    expect(request.body, {
      'folder_id': 'main',
      'object_type': 'tcg',
      'grader': 'Raw',
      'condition': 'Near Mint (NM)',
      'grade': null,
      'language': 'English',
      'finish': 'Holofoil',
      'quantity': 1,
      'purchase_price': null,
      'purchase_currency': null,
      'notes': 'Quick collected from CardDetail.',
    });
    return _json(201, {
      'success': true,
      'data': _portfolioItemJson(id: 'item-squirtle', cardRef: 'squirtle'),
    });
  });
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = adapter;

  final item = await PortfolioApiClient(dio).quickCollect(
    _session,
    cardRef: 'squirtle',
    draft: const PortfolioItemDraftDto(
      folderId: 'main',
      cardRef: 'squirtle',
      objectType: 'tcg',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: 'English',
      finish: 'Holofoil',
      quantity: 1,
      purchasePrice: null,
      purchaseCurrency: null,
      notes: 'Quick collected from CardDetail.',
    ),
  );

  expect(item.id, 'item-squirtle');
  expect(item.cardRef, 'squirtle');
});
```

- [ ] **Step 2: Run the focused failing tests**

Run from `D:\Projects\kando-global-project`:

```powershell
flutter test apps/flutter-app/test/portfolio_api_client_test.dart
```

Expected: fail because `PortfolioApiClient` and DTOs do not exist.

- [ ] **Step 3: Implement the minimal API client**

Create `apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart` with these public pieces:

```dart
import 'package:dio/dio.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

const portfolioApiBaseUrl = authApiBaseUrl;

Dio createPortfolioDio({String baseUrl = portfolioApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
}

class PortfolioApiException implements Exception {
  const PortfolioApiException(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => message;
}
```

Add DTOs with exact backend field names mapped to Dart properties:

```dart
class PortfolioFolderDto {
  const PortfolioFolderDto({
    required this.id,
    required this.name,
    required this.isDefault,
    required this.sortOrder,
  });
  final String id;
  final String name;
  final bool isDefault;
  final int sortOrder;
}

class PortfolioItemDto {
  const PortfolioItemDto({
    required this.id,
    required this.folderId,
    required this.cardRef,
    required this.objectType,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.quantity,
    required this.purchasePrice,
    required this.purchaseCurrency,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String folderId;
  final String cardRef;
  final String objectType;
  final String grader;
  final String? condition;
  final double? grade;
  final String? language;
  final String? finish;
  final int quantity;
  final double? purchasePrice;
  final String? purchaseCurrency;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class WishlistItemDto {
  const WishlistItemDto({
    required this.id,
    required this.cardRef,
    required this.createdAt,
  });
  final String id;
  final String cardRef;
  final DateTime createdAt;
}
```

Add `PortfolioItemDraftDto`, the testable `PortfolioApi` interface, and `PortfolioApiClient`:

```dart
abstract interface class PortfolioApi {
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session);
  Future<List<PortfolioItemDto>> listCollectionItems(AuthSession session);
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session);
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  });
  Future<PortfolioItemDto> createCollectionItem(
    AuthSession session,
    PortfolioItemDraftDto draft,
  );
  Future<PortfolioItemDto> updateCollectionItem(
    AuthSession session, {
    required String itemId,
    required PortfolioItemDraftDto draft,
  });
  Future<void> deleteCollectionItem(AuthSession session, String itemId);
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef);
  Future<void> deleteWishlist(AuthSession session, String itemId);
}

class PortfolioApiClient implements PortfolioApi {
  const PortfolioApiClient(this._dio);
  final Dio _dio;
}
```

- [ ] **Step 4: Run API client tests until they pass**

Run:

```powershell
flutter test apps/flutter-app/test/portfolio_api_client_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- apps/flutter-app/lib/shared/portfolio/portfolio_api_client.dart apps/flutter-app/test/portfolio_api_client_test.dart
git commit -m "feat: add flutter portfolio api client"
```

---

### Task 2: Collection Repository and Async Controller

**Files:**
- Modify: `apps/flutter-app/lib/features/collection/collection_models.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_repository.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_controller.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_page.dart`
- Modify: `apps/flutter-app/test/collection_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`

- [ ] **Step 1: Write failing Collection repository/controller tests**

Add a repository mapping test to `apps/flutter-app/test/collection_controller_test.dart` or a new `apps/flutter-app/test/collection_repository_test.dart`:

```dart
test('http repository maps real portfolio rows into collection dashboard because Collection must show backend-owned assets', () async {
  final api = _FakePortfolioApiClient(
    folders: const [
      PortfolioFolderDto(id: 'main', name: 'Main', isDefault: true, sortOrder: 100),
    ],
    items: [
      _portfolioItem(id: 'item-squirtle', folderId: 'main', cardRef: 'squirtle'),
    ],
    wishlist: [
      WishlistItemDto(
        id: 'wish-luffy',
        cardRef: 'one-piece-luffy',
        createdAt: DateTime.parse('2026-01-02T00:00:00.000Z'),
      ),
    ],
  );

  final dashboard = await HttpCollectionRepository(api).loadDashboard(_session);

  expect(dashboard.defaultFolder.id, 'main');
  expect(dashboard.portfolioItems.single.cardRef, 'squirtle');
  expect(dashboard.portfolioItems.single.name, 'Squirtle');
  expect(dashboard.wishlistItems.single.cardRef, 'one-piece-luffy');
});
```

Update existing controller tests so each test awaits the async load:

```dart
final container = ProviderContainer(
  overrides: [
    collectionRepositoryProvider.overrideWithValue(const MockCollectionRepository()),
  ],
);
addTearDown(container.dispose);
await container.read(collectionControllerProvider.notifier).loadComplete;
```

- [ ] **Step 2: Run Collection tests and confirm failure**

Run:

```powershell
flutter test apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart
```

Expected: fail because Collection repository is still synchronous and `CollectionState.loading` does not exist.

- [ ] **Step 3: Implement async Collection repository**

Change the interface:

```dart
abstract interface class CollectionRepository {
  Future<CollectionDashboard> loadDashboard(AuthSession session);
}
```

Keep `MockCollectionRepository`:

```dart
@override
Future<CollectionDashboard> loadDashboard(AuthSession session) async {
  return const CollectionDashboard(...);
}
```

Add `HttpCollectionRepository`:

```dart
class HttpCollectionRepository implements CollectionRepository {
  const HttpCollectionRepository(this._api);
  final PortfolioApi _api;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final results = await Future.wait([
      _api.listFolders(session),
      _api.listCollectionItems(session),
      _api.listWishlistItems(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;
    return CollectionDashboard(
      folders: folders.map(_folderFromDto).toList(),
      portfolioItems: items.map(_collectionItemFromPortfolioDto).toList(),
      wishlistItems: wishlist.map(_collectionItemFromWishlistDto).toList(),
    );
  }
}
```

Add `cardRef` to `CollectionItem` and update all mock items with their ids, for example `cardRef: 'charizard-ex'`.

- [ ] **Step 4: Implement async Collection controller loading**

Add a loading constructor:

```dart
const CollectionState.loading({required this.currency})
  : _dashboard = null,
    selectedTab = CollectionTab.portfolio,
    selectedFolderId = '',
    amountHidden = false,
    searchByTab = const {CollectionTab.portfolio: '', CollectionTab.wishlist: ''},
    sortByTab = const {
      CollectionTab.portfolio: CollectionSort.newest,
      CollectionTab.wishlist: CollectionSort.newest,
    },
    gamesByTab = const {
      CollectionTab.portfolio: <String>{},
      CollectionTab.wishlist: <String>{},
    },
    languagesByTab = const {
      CollectionTab.portfolio: <String>{},
      CollectionTab.wishlist: <String>{},
    },
    loadStatus = KandoLoadStatus.loading;
```

In `CollectionController.build`, watch Auth state and start async loading when a session exists:

```dart
@override
CollectionState build() {
  ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
    state = state.copyWith(currency: next);
  });

  final currency = ref.watch(selectedCurrencyProvider);
  final authState = ref.watch(authControllerProvider);
  final session = authState.session;
  if (authState.isLoading || session == null) {
    return CollectionState.loading(currency: currency);
  }
  _startLoad(session: session, currency: currency);
  return CollectionState.loading(currency: currency);
}
```

Add a `Future<void> get loadComplete` test hook using a completer, following the Auth controller pattern.

- [ ] **Step 5: Render Collection loading state**

In `apps/flutter-app/lib/features/collection/collection_page.dart`, branch before failure:

```dart
if (state.loadStatus == KandoLoadStatus.loading)
  const KandoLoadingBlock()
else if (state.isUnavailable)
  KandoFailureBlock(onRefresh: controller.refresh)
else ...[
  ...
]
```

- [ ] **Step 6: Run Collection tests until they pass**

Run:

```powershell
flutter test apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart
```

Expected: all Collection tests pass.

- [ ] **Step 7: Commit Task 2**

```powershell
git add -- apps/flutter-app/lib/features/collection/collection_models.dart apps/flutter-app/lib/features/collection/collection_repository.dart apps/flutter-app/lib/features/collection/collection_controller.dart apps/flutter-app/lib/features/collection/collection_page.dart apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "feat: load flutter collection from portfolio api"
```

---

### Task 3: Card Detail Repository Asset Overlay and Mutations

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write failing Card Detail repository tests**

Add tests that prove backend state overlays local presentation:

```dart
test('http detail repository overlays backend collection rows onto local card detail', () async {
  final api = _FakePortfolioApiClient(
    folders: const [
      PortfolioFolderDto(id: 'main', name: 'Main', isDefault: true, sortOrder: 100),
    ],
    items: [
      _portfolioItem(
        id: 'backend-item',
        folderId: 'main',
        cardRef: 'squirtle',
        quantity: 2,
      ),
    ],
    wishlist: const [],
  );

  final detail = await HttpCardDetailRepository(
    api: api,
    presentationRepository: const MockCardDetailRepository(),
  ).loadDetail(_session, 'squirtle');

  expect(detail.name, 'Squirtle');
  expect(detail.quantity, 2);
  expect(detail.collectionItems.single.id, 'backend-item');
  expect(detail.collectionItems.single.cardRef, 'squirtle');
});
```

Add mutation intent tests:

```dart
test('quick collect returns backend item because Card Detail must not invent ids', () async {
  final repository = _RecordingCardDetailRepository();
  final detail = await const MockCardDetailRepository().loadDetail(
    _session,
    'squirtle',
  );
  final saved = await repository.quickCollect(_session, detail);

  expect(repository.quickCollectCardRefs, ['squirtle']);
  expect(saved.id, 'backend-item-squirtle');
});
```

- [ ] **Step 2: Run Card Detail repository tests and confirm failure**

Run:

```powershell
flutter test apps/flutter-app/test/card_detail_controller_test.dart
```

Expected: fail because `CardDetailRepository` has no async session-aware methods or mutations.

- [ ] **Step 3: Extend Card Detail model**

Change `CardCollectionItem` to include:

```dart
final String cardRef;
final String? folderId;
```

Update constructor and `copyWith`, and update all existing mock `CardCollectionItem` calls with `cardRef` and `folderId`.

Change `CardDetail` to carry the backend wishlist row id:

```dart
final String? wishlistItemId;
```

Update the constructor and `copyWith` so wishlist deletion can call `DELETE /wishlist/:item_id`.

- [ ] **Step 4: Extend Card Detail repository interface**

Use these signatures:

```dart
abstract interface class CardDetailRepository {
  Future<CardDetail> loadDetail(AuthSession session, String cardId);
  Future<CardCollectionItem> quickCollect(AuthSession session, CardDetail detail);
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
```

Keep `MockCardDetailRepository` deterministic by returning `Future.value` and in-memory mutation results.

- [ ] **Step 5: Implement `HttpCardDetailRepository`**

Compose the existing mock presentation source and Portfolio API:

```dart
class HttpCardDetailRepository implements CardDetailRepository {
  const HttpCardDetailRepository({
    required PortfolioApi api,
    CardDetailRepository presentationRepository = const MockCardDetailRepository(),
  }) : _api = api,
       _presentationRepository = presentationRepository;

  final PortfolioApi _api;
  final CardDetailRepository _presentationRepository;
}
```

Load flow:

```dart
final detail = await _presentationRepository.loadDetail(session, cardId);
final folders = await _api.listFolders(session);
final items = await _api.listCollectionItems(session);
final wishlist = await _api.listWishlistItems(session);
return _mergeAssetState(detail, folders, items, wishlist);
```

Mutation mapping:

```dart
PortfolioItemDraftDto _draftFromCardItem(CardDetail detail, CardCollectionItem item) {
  return PortfolioItemDraftDto(
    folderId: item.folderId ?? _defaultFolderId,
    cardRef: detail.id,
    objectType: _objectTypeFromDetail(detail),
    grader: item.grader,
    condition: item.condition,
    grade: double.tryParse(item.grade ?? ''),
    language: item.language,
    finish: item.finish,
    quantity: item.quantity,
    purchasePrice: item.purchasePriceUsd,
    purchaseCurrency: item.purchasePriceUsd == null ? null : 'USD',
    notes: item.notes.isEmpty ? null : item.notes,
  );
}
```

- [ ] **Step 6: Run Card Detail repository tests until they pass**

Run:

```powershell
flutter test apps/flutter-app/test/card_detail_controller_test.dart
```

Expected: tests covering repository overlay and mutation intent pass.

- [ ] **Step 7: Commit Task 3**

```powershell
git add -- apps/flutter-app/lib/features/card_detail/card_detail_models.dart apps/flutter-app/lib/features/card_detail/card_detail_repository.dart apps/flutter-app/test/card_detail_controller_test.dart
git commit -m "feat: add card detail portfolio repository"
```

---

### Task 4: Card Detail Async Controller Mutations

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`

- [ ] **Step 1: Write failing controller mutation tests**

Update controller tests to await load:

```dart
final container = ProviderContainer(
  overrides: [
    cardDetailRepositoryProvider.overrideWithValue(repository),
  ],
);
addTearDown(container.dispose);
final provider = cardDetailControllerProvider('squirtle');
await container.read(provider.notifier).loadComplete;
```

Add test:

```dart
test('quick Collect updates from repository result and clears Wishlist because backend owns the item id', () async {
  final repository = _RecordingCardDetailRepository();
  final container = ProviderContainer(
    overrides: [cardDetailRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('one-piece-luffy');
  await container.read(provider.notifier).loadComplete;

  await container.read(provider.notifier).quickCollect();

  final detail = container.read(provider).detail;
  expect(repository.quickCollectCardRefs, ['one-piece-luffy']);
  expect(detail.collectionItems.single.id, 'backend-item-one-piece-luffy');
  expect(detail.isWishlisted, isFalse);
});
```

Add test:

```dart
test('wishlist toggle persists through repository because Wishlist must survive refresh', () async {
  final repository = _RecordingCardDetailRepository();
  final container = ProviderContainer(
    overrides: [cardDetailRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('squirtle');
  await container.read(provider.notifier).loadComplete;

  await container.read(provider.notifier).toggleWishlist();

  expect(repository.addedWishlistCardRefs, ['squirtle']);
  expect(container.read(provider).detail.isWishlisted, isTrue);
});
```

- [ ] **Step 2: Run Card Detail controller/widget tests and confirm failure**

Run:

```powershell
flutter test apps/flutter-app/test/card_detail_controller_test.dart apps/flutter-app/test/widget/card_detail_page_test.dart
```

Expected: fail because controller methods are synchronous and do not call repository mutations.

- [ ] **Step 3: Implement async Card Detail loading**

Add `CardDetailState.loading`:

```dart
const CardDetailState.loading({
  required this.cardId,
  required this.currency,
  this.selectedPriceChartMode = CardPriceChartMode.raw,
  this.selectedPriceRange = CardPriceRange.oneMonth,
  this.collectionItemDraft,
  this.editingCollectionItemId,
  this.collectionItemFormError,
}) : _detail = null,
     loadStatus = KandoLoadStatus.loading;
```

In `build`, watch Auth:

```dart
final authState = ref.watch(authControllerProvider);
final session = authState.session;
if (authState.isLoading || session == null) {
  return CardDetailState.loading(cardId: cardId, currency: currency);
}
_startLoad(session: session, currency: currency);
return CardDetailState.loading(cardId: cardId, currency: currency);
```

- [ ] **Step 4: Implement repository-backed mutations**

Change method signatures:

```dart
Future<void> quickCollect() async
Future<void> toggleWishlist() async
Future<bool> saveCollectionItemDraft() async
Future<void> removeCollectionItem(String itemId) async
```

For `quickCollect`, replace local `_defaultCollectionItem` persistence with:

```dart
final savedItem = await _repository.quickCollect(session, detail);
state = state.copyWith(
  detail: _detailWithCollectionItems(
    detail,
    [...detail.collectionItems, savedItem],
    isWishlisted: false,
  ),
);
```

For save draft:

```dart
final savedItem = editingItemId == null
    ? await _repository.createCollectionItem(session, detail: detail, item: draftItem)
    : await _repository.updateCollectionItem(session, detail: detail, item: draftItem);
```

For remove:

```dart
await _repository.deleteCollectionItem(session, itemId);
final nextItems = detail.collectionItems.where((item) => item.id != itemId).toList();
```

For wishlist:

```dart
if (state.detail.isWishlisted) {
  final wishlistId = state.detail.wishlistItemId;
  if (wishlistId != null) await _repository.deleteWishlist(session, wishlistId);
  state = state.copyWith(detail: state.detail.copyWith(isWishlisted: false, wishlistItemId: null));
} else {
  final wishlistId = await _repository.addWishlist(session, state.detail.id);
  state = state.copyWith(detail: state.detail.copyWith(isWishlisted: true, wishlistItemId: wishlistId));
}
```

Use `CardDetail.wishlistItemId` for deletion so `DELETE /wishlist/:item_id` always receives the backend row id.

- [ ] **Step 5: Update Card Detail page callbacks**

Where callbacks expect sync values, await futures:

```dart
onPressed: () async {
  await controller.quickCollect();
}
```

For save button:

```dart
onPressed: () async {
  await controller.saveCollectionItemDraft();
}
```

- [ ] **Step 6: Run Card Detail tests until they pass**

Run:

```powershell
flutter test apps/flutter-app/test/card_detail_controller_test.dart apps/flutter-app/test/widget/card_detail_page_test.dart
```

Expected: all Card Detail tests pass.

- [ ] **Step 7: Commit Task 4**

```powershell
git add -- apps/flutter-app/lib/features/card_detail/card_detail_controller.dart apps/flutter-app/lib/features/card_detail/card_detail_page.dart apps/flutter-app/test/card_detail_controller_test.dart apps/flutter-app/test/widget/card_detail_page_test.dart
git commit -m "feat: persist card detail asset actions"
```

---

### Task 5: Provider Defaults and Full Flutter Verification

**Files:**
- Create: `apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_controller.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`

- [ ] **Step 1: Wire default providers to HTTP implementations**

Create `apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'portfolio_api_client.dart';

final portfolioDioProvider = Provider((ref) {
  final dio = createPortfolioDio();
  ref.onDispose(dio.close);
  return dio;
});

final portfolioApiClientProvider = Provider((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});
```

Collection provider:

```dart
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return HttpCollectionRepository(ref.watch(portfolioApiClientProvider));
});
```

Card Detail provider:

```dart
final cardDetailRepositoryProvider = Provider<CardDetailRepository>((ref) {
  return HttpCardDetailRepository(api: ref.watch(portfolioApiClientProvider));
});
```

Update widget tests that can navigate into Collection or Card Detail with explicit mock overrides:

```dart
collectionRepositoryProvider.overrideWithValue(const MockCollectionRepository()),
cardDetailRepositoryProvider.overrideWithValue(const MockCardDetailRepository()),
```

- [ ] **Step 2: Run all Flutter tests**

Run:

```powershell
flutter test apps/flutter-app/test
```

Expected: all tests pass with widget tests using explicit repository overrides for Collection and Card Detail routes.

- [ ] **Step 3: Run Flutter analyzer**

Run:

```powershell
flutter analyze apps/flutter-app
```

Expected: `No issues found!`

- [ ] **Step 4: Inspect final git diff**

Run:

```powershell
git status --short
git diff --stat
git diff --check
```

Expected:

- Only Flutter files and the plan file are changed for this implementation.
- Unrelated pre-existing Workers and documentation changes remain unstaged.
- `git diff --check` exits with code 0.

- [ ] **Step 5: Commit Task 5**

```powershell
git add -- apps/flutter-app/lib/shared/portfolio/portfolio_providers.dart apps/flutter-app/lib/features/collection/collection_controller.dart apps/flutter-app/lib/features/card_detail/card_detail_controller.dart apps/flutter-app/test/widget/home_page_test.dart apps/flutter-app/test/widget/search_page_test.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "test: verify flutter portfolio api integration"
```

---

## Plan Self-Review

- Spec coverage: Collection read, Card Detail quick collect, manual item add/edit/delete, wishlist add/remove, Auth bearer token, and regression checks are all covered.
- Scope control: Search, Home, folder management UI, backend changes, offline cache, and retry infrastructure are excluded.
- Type consistency: Repository methods use `AuthSession`; API DTO names use `Portfolio*Dto`; Flutter view models keep existing names with added `cardRef`, `folderId`, and `wishlistItemId`.
- Known transition: Card display metadata remains local fallback while real asset ownership comes from Workers portfolio endpoints.

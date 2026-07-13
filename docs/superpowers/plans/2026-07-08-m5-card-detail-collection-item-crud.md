# M5 CardDetail Collection Item CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build M5-4 so CardDetail can add, edit, and remove mock Collection Item records with grader-driven form state.

**Architecture:** Extend the existing Flutter `features/card_detail` model, controller, and page. Keep persistence local to `CardDetailState`; no backend clients, database changes, Admin code, or global Home refresh wiring.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider.family`, Material form widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Keep this slice mock-first and local to CardDetail.
- Do not implement Home/Collection/Search global data reload after save/delete.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add Collection Item Draft State And Controller Actions

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add tests that define the state API before implementation:

```dart
test('adding a Collection Item appends an owned row and clears Wishlist', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('squirtle');
  final controller = container.read(provider.notifier);

  controller.startAddingCollectionItem();
  controller.updateCollectionItemDraft(
    quantityText: '2',
    portfolioName: 'Sealed',
    grader: 'Raw',
    condition: 'Lightly Played',
    purchasePriceText: '12.50',
    notes: 'Second binder copy.',
  );

  expect(controller.saveCollectionItemDraft(), isTrue);
  final state = container.read(provider);

  expect(state.detail.isCollected, isTrue);
  expect(state.detail.quantity, 2);
  expect(state.detail.isWishlisted, isFalse);
  expect(state.collectionItemRows.single.portfolioName, 'Sealed');
  expect(state.collectionItemRows.single.quantityText, 'Qty: 2');
  expect(state.collectionItemRows.single.statusText, 'Raw / Lightly Played');
  expect(state.collectionItemRows.single.purchasePriceText, r'$12.50');
  expect(state.collectionItemRows.single.notes, 'Second binder copy.');
  expect(state.collectionItemDraft, isNull);
});

test('editing a Collection Item switches graded state to Raw state', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('charizard-ex');
  final controller = container.read(provider.notifier);

  controller.startEditingCollectionItem('item-charizard');
  controller.updateCollectionItemDraft(
    quantityText: '3',
    grader: 'Raw',
    condition: 'Near Mint',
    purchasePriceText: '640',
    notes: 'Cracked slab for binder.',
  );

  expect(controller.saveCollectionItemDraft(), isTrue);
  final row = container.read(provider).collectionItemRows.single;

  expect(row.quantityText, 'Qty: 3');
  expect(row.statusText, 'Raw / Near Mint');
  expect(row.purchasePriceText, r'$640.00');
  expect(row.notes, 'Cracked slab for binder.');
});

test('invalid Collection Item draft stays open with validation copy', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('charizard-ex');
  final controller = container.read(provider.notifier);

  controller.startEditingCollectionItem('item-charizard');
  controller.updateCollectionItemDraft(quantityText: '0');

  expect(controller.saveCollectionItemDraft(), isFalse);
  final state = container.read(provider);

  expect(state.collectionItemDraft, isNotNull);
  expect(state.collectionItemFormError, 'Quantity must be at least 1.');
  expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
});

test('removing the final Collection Item returns detail to uncollected state', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('charizard-ex');

  container.read(provider.notifier).removeCollectionItem('item-charizard');
  final state = container.read(provider);

  expect(state.detail.isCollected, isFalse);
  expect(state.detail.quantity, 0);
  expect(state.collectionItemRows, isEmpty);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
```

Expected: FAIL because `collectionItemDraft`, draft methods, save/remove methods, and validation state do not exist.

- [ ] **Step 3: Implement minimal model support**

Add `copyWith` to `CardCollectionItem`:

```dart
CardCollectionItem copyWith({
  String? portfolioName,
  int? quantity,
  String? grader,
  String? condition,
  String? grade,
  double? purchasePriceUsd,
  String? notes,
}) {
  return CardCollectionItem(
    id: id,
    portfolioName: portfolioName ?? this.portfolioName,
    quantity: quantity ?? this.quantity,
    grader: grader ?? this.grader,
    condition: condition,
    grade: grade,
    purchasePriceUsd: purchasePriceUsd,
    notes: notes ?? this.notes,
  );
}
```

Keep the existing `CardDetail.copyWith` `isWishlisted`, price series, and sold listings behavior unchanged while adding `CardCollectionItem.copyWith`.

- [ ] **Step 4: Implement draft state and controller actions**

Add a small draft class in `card_detail_controller.dart`:

```dart
class CardCollectionItemDraft {
  const CardCollectionItemDraft({
    required this.quantityText,
    required this.portfolioName,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.purchasePriceText,
    required this.notes,
  });

  final String quantityText;
  final String portfolioName;
  final String grader;
  final String condition;
  final String grade;
  final String purchasePriceText;
  final String notes;

  bool get isRaw => grader == 'Raw';
}
```

Add state fields:

```dart
final CardCollectionItemDraft? collectionItemDraft;
final String? editingCollectionItemId;
final String? collectionItemFormError;
```

Controller behavior:

- `startAddingCollectionItem()` creates a default draft: quantity `1`, portfolio `Main`, grader `Raw`, condition `Near Mint`, empty grade, empty purchase price, empty notes.
- `startEditingCollectionItem(id)` fills draft from the matching item.
- `updateCollectionItemDraft(...)` copies provided field values; when grader becomes `Raw`, keep condition and clear grade; when grader is not `Raw`, clear condition and default grade to `10`.
- `saveCollectionItemDraft()` validates, returns `false` on validation error, returns `true` after add/edit.
- `removeCollectionItem(id)` removes the item and recomputes total quantity from remaining items.

Use these validation messages:

```dart
const _quantityRequiredText = 'Please enter a quantity.';
const _quantityMinText = 'Quantity must be at least 1.';
const _quantityWholeText = 'Quantity must be a whole number.';
const _invalidPriceText = 'Please enter a valid price.';
const _notesTooLongText = 'Notes must be 500 characters or less.';
```

- [ ] **Step 5: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/card_detail_controller_test.dart
flutter test test/card_detail_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail apps/flutter-app/test/card_detail_controller_test.dart
git commit -m "feat: add CardDetail collection item draft state"
```

## Task 2: Render Collection Item Add/Edit/Delete UI

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests:

```dart
testWidgets('owned Collection Item can be edited from CardDetail', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
  );

  await tester.scrollUntilVisible(find.text('Collection Item'), 400);
  await tester.tap(find.text('Edit item'));
  await tester.pumpAndSettle();

  expect(find.text('Ownership Summary'), findsOneWidget);
  await tester.enterText(find.byKey(const Key('card-detail-item-quantity')), '3');
  await tester.tap(find.byKey(const Key('card-detail-item-grader')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Raw').last);
  await tester.pumpAndSettle();

  expect(find.text('Condition'), findsOneWidget);
  expect(find.text('Grade'), findsNothing);

  await tester.enterText(find.byKey(const Key('card-detail-item-notes')), 'Cracked slab for binder.');
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();

  expect(find.text('Ownership Summary'), findsNothing);
  expect(find.text('Qty: 3'), findsOneWidget);
  expect(find.text('Raw / Near Mint'), findsOneWidget);
  expect(find.text('Cracked slab for binder.'), findsOneWidget);
});

testWidgets('owned Collection Item shows validation without losing draft', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
  );

  await tester.scrollUntilVisible(find.text('Collection Item'), 400);
  await tester.tap(find.text('Edit item'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('card-detail-item-quantity')), '0');
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();

  expect(find.text('Quantity must be at least 1.'), findsOneWidget);
  expect(find.text('Ownership Summary'), findsOneWidget);
});

testWidgets('owned Collection Item can be removed after confirmation', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
  );

  await tester.scrollUntilVisible(find.text('Collection Item'), 400);
  await tester.tap(find.text('Remove from Portfolio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Remove'));
  await tester.pumpAndSettle();

  expect(find.text('Collect'), findsOneWidget);
  expect(find.text('Collection Item'), findsNothing);
  expect(find.text('Price overview'), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/card_detail_page_test.dart
```

Expected: FAIL because the edit buttons, inline form, and remove confirmation do not exist.

- [ ] **Step 3: Implement minimal UI**

Thread `controller` into `_CollectionItems`.

Add to each owned item card:

- `TextButton(onPressed: () => controller.startEditingCollectionItem(item.id), child: const Text('Edit item'))`
- `TextButton(onPressed: () => _confirmRemoveCollectionItem(...), child: const Text('Remove from Portfolio'))`

Render the form when `state.collectionItemDraft != null`:

- Heading `Ownership Summary`
- `TextField` key `card-detail-item-quantity`
- Portfolio dropdown key `card-detail-item-portfolio`
- Grader dropdown key `card-detail-item-grader`
- Condition dropdown key `card-detail-item-condition` for Raw drafts
- Grade dropdown key `card-detail-item-grade` for graded drafts
- Purchase price text field key `card-detail-item-purchase-price`
- Notes text field key `card-detail-item-notes`
- `Cancel` and `Save changes` buttons

For remove confirmation, use `showDialog` with title `Remove from Portfolio`, body `Remove this Collection Item from your portfolio?`, and actions `Cancel` / `Remove`.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/widget/card_detail_page_test.dart
flutter test test/widget/card_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail apps/flutter-app/test/widget/card_detail_page_test.dart
git commit -m "feat: render CardDetail collection item editor"
```

## Task 3: Search Regression, Final Verification, And Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run Search regression**

```powershell
cd apps/flutter-app
flutter test test/widget/search_page_test.dart
```

Expected: PASS. If scrolling makes a previously visible header assertion brittle, move that assertion before the scroll; do not weaken behavior coverage.

- [ ] **Step 2: Run focused CardDetail tests again**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
flutter test test/widget/card_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run full Flutter verification**

```powershell
flutter pub get
dart run melos run test
cd apps/flutter-app
flutter analyze
dart format --set-exit-if-changed lib test
```

Expected: all commands exit 0.

- [ ] **Step 4: Stop hook**

```powershell
cmd /c "echo [M5-4] Implement CardDetail Collection Item CRUD| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 5: Commit and push status**

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M5 CardDetail Collection Item CRUD status"
git push origin codex/m2-data-adapter
```

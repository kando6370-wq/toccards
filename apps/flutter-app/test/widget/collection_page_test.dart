import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/in_memory_portfolio_amount_hidden_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets('Collection filter matches the 390x884 Figma viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 884);
    addTearDown(tester.view.reset);

    await _pumpCollection(tester);
    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();

    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    final highToLowOption = tester.getRect(
      find
          .ancestor(
            of: find.text('Price: High to Low'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    final lowToHighOption = tester.getRect(
      find
          .ancestor(
            of: find.text('Price: Low to High'),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(lowToHighOption.top - highToLowOption.bottom, 10);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.byKey(const Key('collection-filter-apply')), findsOneWidget);
    expect(
      tester
          .getBottomRight(find.byKey(const Key('collection-filter-apply')))
          .dy,
      lessThanOrEqualTo(884),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Collection filter keeps Apply fixed while options scroll', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 884);
    addTearDown(tester.view.reset);

    await _pumpCollection(tester);
    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();

    final apply = find.byKey(const Key('collection-filter-apply'));
    final sortOption = find.text('Price: Low to High');
    final applyBeforeScroll = tester.getRect(apply);
    final sortBeforeScroll = tester.getRect(sortOption);

    await tester.drag(
      find.byKey(const Key('collection-filter-sheet')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(apply), applyBeforeScroll);
    expect(tester.getTopLeft(sortOption).dy, lessThan(sortBeforeScroll.top));
  });

  testWidgets('Collection shows Portfolio summary and rows by default', (
    tester,
  ) async {
    await _pumpCollection(tester);

    expect(find.byKey(const Key('collection-pull-to-refresh')), findsOneWidget);
    expect(find.text('Collection'), findsOneWidget);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-folder-switch-icon')),
      findsOneWidget,
    );
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Pokemon · Obsidian Flames'), findsOneWidget);
    expect(find.text('Special Illustration Rare · 223'), findsOneWidget);
    expect(find.text('PSA 10 · Holofoil'), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('Qty: 1'), findsWidgets);
    _expectTextOrder(tester, const [
      'Charizard ex',
      'Pokemon · Obsidian Flames',
      'Special Illustration Rare · 223',
      'PSA 10 · Holofoil',
      r'$780.00',
    ]);
    _expectCollectionCardRowMatchesSearchField(
      tester,
      leftCardId: 'charizard-ex',
      rightCardId: 'umbreon-vmax',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull refresh keeps Collection content and shows one spinner', (
    tester,
  ) async {
    final repository = _BlockingRefreshCollectionRepository();
    await _pumpCollection(tester, repository: repository);

    final indicator = find.byKey(const Key('collection-pull-to-refresh'));
    final refresh = tester.state<RefreshIndicatorState>(indicator).show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.calls, 2);
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    expect(find.byType(KandoLoadingBlock), findsNothing);
    expect(find.text('Charizard ex'), findsOneWidget);

    await repository.completeRefresh();
    await refresh;
    await tester.pumpAndSettle();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(find.text('Charizard ex'), findsOneWidget);
  });

  testWidgets(
    'Collection content uses the standard top spacing below the safe area',
    (tester) async {
      await _pumpCollection(tester);

      final header = tester.widget<Padding>(
        find.byKey(const Key('collection-fixed-header')),
      );
      final listView = tester.widget<ListView>(
        find.byKey(const Key('collection-content-list')),
      );

      expect(
        header.padding,
        const EdgeInsets.fromLTRB(20, KandoLayout.mainTabTopPadding, 20, 16),
      );
      expect(listView.padding, const EdgeInsets.fromLTRB(20, 0, 20, 24));
    },
  );

  testWidgets(
    'Collection header stays fixed because card browsing must preserve controls and portfolio context',
    (tester) async {
      await _pumpCollection(tester);

      final header = find.byKey(const Key('collection-fixed-header'));
      final list = find.byKey(const Key('collection-content-list'));
      final firstCard = find.text('Charizard ex');
      final headerBeforeScroll = tester.getRect(header);
      final cardBeforeScroll = tester.getRect(firstCard);

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(header), headerBeforeScroll);
      expect(tester.getTopLeft(firstCard).dy, lessThan(cardBeforeScroll.top));
    },
  );

  testWidgets('Collection restores the server currency preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _PreferenceCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('1,132.95'), findsOneWidget);
    expect(find.textContaining('709.80'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);
  });

  testWidgets('page failure shows Refresh and restores collection content', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulCollectionRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.text('Collection'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('folder picker changes Portfolio list', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-select-sealed')));
    await tester.pumpAndSettle();

    expect(find.text('Sealed'), findsWidgets);
    expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets(
    'folder manager exposes Figma actions and creates a backend folder',
    (tester) async {
      await _pumpCollection(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        KandoColors.surface,
      );
      expect(find.text('DRAG AND DROP TO CHANGE ORDER'), findsOneWidget);
      expect(find.byKey(const Key('collection-folder-add')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('collection-folder-delete-main')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('collection-folder-edit-sealed')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-default-folder-trade')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'folder radio and label share a large target because portfolio switching must not require precise text taps',
    (tester) async {
      await _pumpCollection(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('collection-folder-select-sealed')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionPage)),
      );
      expect(
        container.read(collectionControllerProvider).selectedFolder.id,
        'sealed',
      );
    },
  );

  testWidgets('folder delete confirmation opens as a bottom sheet', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-delete-sealed')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('collection-folder-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sealed')),
      findsNothing,
    );
  });

  testWidgets('Wishlist tab uses wishlist copy and hides quantity', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('One Piece Manga Luffy (JP)'), findsOneWidget);
    expect(find.text('Lorcana · The First Chapter'), findsOneWidget);
    expect(find.text('Enchanted Rare · 212'), findsOneWidget);
    expect(find.text('Raw · Near Mint (NM)'), findsNothing);
    expect(find.text('Enchanted'), findsOneWidget);
    expect(find.textContaining('Qty:'), findsNothing);
    _expectCollectionCardRowMatchesSearchField(
      tester,
      leftCardId: 'lorcana-elsa',
      rightCardId: 'one-piece-luffy',
    );
  });

  testWidgets('search no-match state is distinct from empty state', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching cards found.'), findsOneWidget);
    expect(find.text('Try adjusting your search or filters.'), findsOneWidget);
    expect(find.byKey(const Key('collection-no-match-state')), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    expect(find.text('0 cards'), findsOneWidget);
    expect(find.text('0 graded'), findsOneWidget);
    expect(find.text('No cards in this portfolio yet.'), findsNothing);
  });

  testWidgets('amount toggle masks only the portfolio total', (tester) async {
    await _pumpCollection(tester);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    expect(find.text(r'$780.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('collection-hide-amount')));
    await tester.pump();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.text(hiddenMoneyText), findsOneWidget);
    expect(find.text(r'$1,245.00'), findsNothing);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
  });

  testWidgets(
    'amount toggle stays local when the server preference endpoint fails',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const _FailingPreferenceCollectionRepository(),
            ),
          ],
          child: const _CollectionTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('collection-hide-amount')));
      await tester.pump();
      await tester.pump();

      expect(find.text(genericFailureToastText), findsNothing);
      expect(find.text(r'$1,245.00'), findsNothing);
      expect(find.text(hiddenMoneyText), findsOneWidget);
    },
  );

  testWidgets('filter sheet applies Game and Language filters', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DecoratedBox>(
      find.byKey(const Key('collection-filter-sheet-background')),
    );
    expect((sheet.decoration as BoxDecoration).color, KandoColors.surface);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsOneWidget);
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('GAME / IP'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('GAME / IP'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pokemon'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Pokemon'), findsOneWidget);
    await tester.tap(find.byKey(const Key('collection-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pikachu Promo'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets('Collection bottom navigation can return Home and Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kando-tab-collection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection bottom navigation can open Search', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('Collection cards open the detail for their backend card ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('search-card-charizard-ex'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Detail charizard-ex'), findsOneWidget);
  });

  testWidgets(
    'Portfolio empty state actions open Scan and Search because empty collections must have recovery paths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 884);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);
      expect(find.text('Scan or search cards to track value'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-portfolio-empty-illustration')),
        findsOneWidget,
      );
      final portfolioIllustration = tester.widget<Image>(
        find.byKey(const Key('collection-portfolio-empty-illustration')),
      );
      expect(
        (portfolioIllustration.image as AssetImage).assetName,
        'assets/collection/portfolio_empty_figma.png',
      );
      expect(portfolioIllustration.width, 83);
      expect(portfolioIllustration.height, 90);
      final scanIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'SCAN A CARD'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (scanIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_action_camera.svg',
      );
      expect(scanIcon.width, 16.0417);
      expect(scanIcon.height, 14.5417);
      final searchIcon = tester.widget<SvgPicture>(
        find.descendant(
          of: find.widgetWithText(FilledButton, 'SEARCH A CARD'),
          matching: find.byType(SvgPicture),
        ),
      );
      expect(
        (searchIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/home/empty_action_search.svg',
      );
      expect(searchIcon.width, 15.2707);
      expect(searchIcon.height, 15.8891);
      expect(
        tester
            .getBottomLeft(find.widgetWithText(FilledButton, 'SEARCH A CARD'))
            .dy,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byKey(const Key('kando-tab-bar'))).dy,
        ),
      );

      await tester.ensureVisible(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);

      await tester.ensureVisible(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Wishlist empty state matches the Figma recovery layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _EmptyWishlistCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Your wishlist is empty'), findsOneWidget);
    expect(find.text('Add cards you want to collect later'), findsOneWidget);
    expect(find.text('SEARCH CARDS'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-wishlist-empty-illustration')),
      findsOneWidget,
    );
    final wishlistIllustration = tester.widget<Image>(
      find.byKey(const Key('collection-wishlist-empty-illustration')),
    );
    expect(
      (wishlistIllustration.image as AssetImage).assetName,
      'assets/collection/wishlist_empty_figma.png',
    );
    expect(wishlistIllustration.width, 170);
    expect(wishlistIllustration.height, 100);
    expect(find.byKey(const Key('collection-portfolio-summary')), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

Future<void> _pumpCollection(
  WidgetTester tester, {
  CollectionRepository repository = const MockCollectionRepository(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._localAuthOverrides(),
        collectionRepositoryProvider.overrideWithValue(repository),
      ],
      child: const _CollectionTestApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectCollectionCardRowMatchesSearchField(
  WidgetTester tester, {
  required String leftCardId,
  required String rightCardId,
}) {
  final searchFieldRect = tester.getRect(find.byType(TextField).first);
  final leftCardRect = tester.getRect(
    find.byKey(Key('search-card-$leftCardId')),
  );
  final rightCardRect = tester.getRect(
    find.byKey(Key('search-card-$rightCardId')),
  );

  expect(leftCardRect.left, closeTo(searchFieldRect.left, 0.01));
  expect(rightCardRect.right, closeTo(searchFieldRect.right, 0.01));
  expect(rightCardRect.left - leftCardRect.right, closeTo(10, 0.01));
}

void _expectTextOrder(WidgetTester tester, List<String> labels) {
  for (var index = 1; index < labels.length; index++) {
    expect(
      tester.getRect(find.text(labels[index])).top,
      greaterThan(tester.getRect(find.text(labels[index - 1])).top),
      reason: 'Collection cards must preserve the Search Cards field order.',
    );
  }
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

_localAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
    currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
    portfolioAmountHiddenStorageProvider.overrideWithValue(
      InMemoryPortfolioAmountHiddenStorage(),
    ),
  ];
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi();

  @override
  Future<double> loadUsdRate(String targetCurrency) async => 0.91;
}

class _CollectionTestApp extends StatelessWidget {
  const _CollectionTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CollectionPage());
  }
}

class _CollectionTestAppWithRoutes extends StatelessWidget {
  const _CollectionTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/collection',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) => Scaffold(
              body: Text('Detail ${state.pathParameters['cardId']}'),
            ),
          ),
        ],
      ),
    );
  }
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

class _BlockingRefreshCollectionRepository extends MockCollectionRepository {
  final _refresh = Completer<CollectionDashboard>();
  AuthSession? _session;
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) {
    _session = session;
    calls += 1;
    if (calls == 1) return super.loadDashboard(session);
    return _refresh.future;
  }

  Future<void> completeRefresh() async {
    _refresh.complete(await super.loadDashboard(_session!));
  }
}

class _PreferenceCollectionRepository extends MockCollectionRepository {
  const _PreferenceCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(currencyCode: 'EUR');
  }
}

class _FailingPreferenceCollectionRepository extends MockCollectionRepository {
  const _FailingPreferenceCollectionRepository();

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) {
    throw StateError('Preference backend rejected the mutation.');
  }
}

class _EmptyWishlistCollectionRepository extends MockCollectionRepository {
  const _EmptyWishlistCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(wishlistItems: const []);
  }
}

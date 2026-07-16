import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

void main() {
  test(
    'API dashboard previews three highest unit prices because Most Valuable ignores quantity',
    () async {
      final dashboard = await ApiHomeRepository(
        session: _session,
        portfolioApi: _PortfolioApi(),
        managementApi: _ManagementApi(),
        cardDataApi: _CardDataApi(),
      ).loadDashboard();

      expect(dashboard.defaultFolder.name, 'Main');
      expect(dashboard.portfoliosByFolderId['main']!.totalValueUsd, 760);
      expect(dashboard.portfoliosByFolderId['main']!.previous30dValueUsd, 608);
      expect(
        dashboard.mostValuableCardsByFolderId['main']!.map(
          (card) => card.title,
        ),
        ['Owned Card', 'Mid Value Card', 'Lower Value Card'],
      );
      expect(
        dashboard.mostValuableCardsByFolderId['main']!.map(
          (card) => card.priceUsd,
        ),
        [100, 50, 10],
      );
      expect(dashboard.trending.single.title, 'Trending Card');
      expect(dashboard.trending.single.priceUsd, 60);
      expect(dashboard.trending.single.previousPriceUsd, 50);
      expect(dashboard.currencyCode, 'USD');
      expect(dashboard.amountHidden, isFalse);
      final month = dashboard
          .portfoliosByFolderId['main']!
          .chartValuesByRange[HomeChartRange.oneMonth]!;
      expect(month, hasLength(31));
      expect(month.first, 608);
      expect(month.last, 760);
    },
  );

  test(
    'one server history response supplies the Figma 3M range without per-card curve requests',
    () async {
      final dashboard = await ApiHomeRepository(
        session: _session,
        portfolioApi: _PortfolioApi(),
        managementApi: _ManagementApi(),
        cardDataApi: _CardDataApi(),
      ).loadDashboard();

      expect(dashboard.portfoliosByFolderId['main']!.totalValueUsd, 760);
      expect(
        dashboard
            .portfoliosByFolderId['main']!
            .chartValuesByRange[HomeChartRange.threeMonths],
        hasLength(91),
      );
      expect(dashboard.mostValuableCardsByFolderId['main'], hasLength(3));
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access',
  refreshToken: 'refresh',
  anonymousId: 'anon-1',
);

class _PortfolioApi implements PortfolioApi {
  @override
  Future<List<PortfolioFolderDto>> listFolders(
    AuthSession session,
  ) async => const [
    PortfolioFolderDto(id: 'main', name: 'Main', isDefault: true, sortOrder: 0),
  ];

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async => [
    PortfolioItemDto(
      id: 'item-1',
      folderId: 'main',
      cardRef: 'owned',
      objectType: 'tcg',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: 'English',
      finish: 'Holofoil',
      quantity: 2,
      purchasePrice: null,
      purchaseCurrency: null,
      notes: null,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
    ),
    PortfolioItemDto(
      id: 'item-2',
      folderId: 'main',
      cardRef: 'owned-low',
      objectType: 'tcg',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: 'English',
      finish: 'Normal',
      quantity: 1,
      purchasePrice: null,
      purchaseCurrency: null,
      notes: null,
      createdAt: DateTime.utc(2026, 7, 2),
      updatedAt: DateTime.utc(2026, 7, 2),
    ),
    PortfolioItemDto(
      id: 'item-3',
      folderId: 'main',
      cardRef: 'owned-mid',
      objectType: 'tcg',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: 'English',
      finish: 'Normal',
      quantity: 1,
      purchasePrice: null,
      purchaseCurrency: null,
      notes: null,
      createdAt: DateTime.utc(2026, 7, 3),
      updatedAt: DateTime.utc(2026, 7, 3),
    ),
    PortfolioItemDto(
      id: 'item-4',
      folderId: 'main',
      cardRef: 'owned-quantity',
      objectType: 'tcg',
      grader: 'Raw',
      condition: 'Near Mint (NM)',
      grade: null,
      language: 'English',
      finish: 'Normal',
      quantity: 100,
      purchasePrice: null,
      purchaseCurrency: null,
      notes: null,
      createdAt: DateTime.utc(2026, 7, 4),
      updatedAt: DateTime.utc(2026, 7, 4),
    ),
  ];

  @override
  Future<List<PortfolioFolderValuationDto>> getValuationHistory(
    AuthSession session, {
    int days = 90,
  }) async => [
    PortfolioFolderValuationDto(
      folderId: 'main',
      currentValueUsd: 760,
      series: List.generate(
        days + 1,
        (index) => PortfolioValuationPointDto(
          date: DateTime.utc(2026, 4, 16 + index).toIso8601String(),
          valueUsd: index < 60 ? 500 : (index == days ? 760 : 608),
        ),
      ),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManagementApi implements PortfolioManagementApi {
  @override
  Future<UserPreferenceDto> getPreferences(AuthSession session) async {
    return const UserPreferenceDto(
      currency: 'USD',
      amountHidden: false,
      lastSelectedFolderId: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CardDataApi implements CardDataApi {
  @override
  Future<CardDataCardDto> getCard(String cardRef) async => _card(cardRef);

  @override
  Future<List<CardDataCardDto>> trendingCards() async => [_card('trending')];

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async {
    if (cardRef == 'trending') {
      throw StateError('Trending must use the feed price contract');
    }
    return [
      if (cardRef == 'owned')
        const CardDataMarketPriceDto(
          grader: 'Raw',
          grade: null,
          condition: 'Lightly Played',
          price: 10,
        ),
      CardDataMarketPriceDto(
        grader: 'Raw',
        grade: null,
        condition: 'Near Mint',
        price: switch (cardRef) {
          'owned' => 100,
          'owned-low' => 10,
          'owned-mid' => 50,
          'owned-quantity' => 5,
          _ => 60,
        },
      ),
    ];
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  }) async {
    throw StateError('Home must not make per-card series requests');
  }

  CardDataCardDto _card(String cardRef) => CardDataCardDto(
    cardRef: cardRef,
    name: switch (cardRef) {
      'owned' => 'Owned Card',
      'owned-low' => 'Lower Value Card',
      'owned-mid' => 'Mid Value Card',
      'owned-quantity' => 'High Quantity Card',
      _ => 'Trending Card',
    },
    setName: 'Server Set',
    setCode: 'SRV',
    cardNumber: '1',
    finish: 'Holofoil',
    language: 'English',
    objectType: 'tcg',
    imageUrl: 'https://cdn.example.test/$cardRef.png',
    rarity: 'Rare',
    priceUsd: cardRef == 'trending' ? 60 : null,
    previous1dPriceUsd: cardRef == 'trending' ? 50 : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

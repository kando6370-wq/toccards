import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

void main() {
  test(
    'API dashboard values owned cards from server prices because Home is an asset summary',
    () async {
      final dashboard = await ApiHomeRepository(
        session: _session,
        portfolioApi: _PortfolioApi(),
        managementApi: _ManagementApi(),
        cardDataApi: _CardDataApi(),
      ).loadDashboard();

      expect(dashboard.defaultFolder.name, 'Main');
      expect(dashboard.portfoliosByFolderId['main']!.totalValueUsd, 210);
      expect(dashboard.portfoliosByFolderId['main']!.previous30dValueUsd, 168);
      expect(
        dashboard.mostValuableCardsByFolderId['main']!.single.title,
        'Owned Card',
      );
      expect(
        dashboard.mostValuableCardsByFolderId['main']!.single.priceUsd,
        100,
      );
      expect(dashboard.trending.single.title, 'Trending Card');
      expect(dashboard.trending.single.priceUsd, 60);
      expect(dashboard.trending.single.previousPriceUsd, 50);
      expect(dashboard.currencyCode, 'USD');
      expect(dashboard.amountHidden, isFalse);
      expect(
        dashboard
            .portfoliosByFolderId['main']!
            .chartValuesByRange[HomeChartRange.oneMonth],
        [168, 210],
      );
    },
  );

  test(
    'a missing chart range keeps the current asset total because history availability must not change portfolio value',
    () async {
      final dashboard = await ApiHomeRepository(
        session: _session,
        portfolioApi: _PortfolioApi(),
        managementApi: _ManagementApi(),
        cardDataApi: _CardDataApi(failedSeriesDays: {90}),
      ).loadDashboard();

      expect(dashboard.portfoliosByFolderId['main']!.totalValueUsd, 210);
      expect(
        dashboard
            .portfoliosByFolderId['main']!
            .chartValuesByRange[HomeChartRange.threeMonths],
        [210],
      );
      expect(dashboard.mostValuableCardsByFolderId['main'], hasLength(1));
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
  _CardDataApi({this.failedSeriesDays = const {}});

  final Set<int> failedSeriesDays;

  @override
  Future<CardDataCardDto> getCard(String cardRef) async => _card(cardRef);

  @override
  Future<List<CardDataCardDto>> trendingCards() async => [_card('trending')];

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async =>
      [
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
            _ => 60,
          },
        ),
      ];

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  }) async {
    if (cardRef.startsWith('owned') && failedSeriesDays.contains(days)) {
      throw StateError('price series unavailable');
    }
    return [
      CardDataPricePointDto(
        date: '2026-06-15',
        price: switch (cardRef) {
          'owned' => days == 30 ? 80 : 90,
          'owned-low' => days == 30 ? 8 : 9,
          _ => 50,
        },
      ),
      CardDataPricePointDto(
        date: '2026-07-15',
        price: switch (cardRef) {
          'owned' => 100,
          'owned-low' => 10,
          _ => 60,
        },
      ),
    ];
  }

  CardDataCardDto _card(String cardRef) => CardDataCardDto(
    cardRef: cardRef,
    name: switch (cardRef) {
      'owned' => 'Owned Card',
      'owned-low' => 'Lower Value Card',
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
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/scan/scan_review_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

void main() {
  test(
    'review keeps a valid match when another candidate or supplemental prices fail',
    () async {
      final repository = ApiScanReviewRepository(
        portfolioApi: _UnusedPortfolioApi(),
        cardDataApi: _PartialCardDataApi(),
        scanApi: _UnusedScanApi(),
        session: () => null,
      );

      final cards = await repository.loadCards(['valid-card', 'bad-card']);

      expect(cards.keys, ['valid-card']);
      expect(cards['valid-card']?.name, 'Goldkiss Rum');
      expect(cards['valid-card']?.prices, isEmpty);
    },
  );
}

class _PartialCardDataApi implements CardDataApi {
  @override
  Future<CardDataCardDto> getCard(String cardRef) async {
    if (cardRef == 'bad-card') throw Exception('candidate unavailable');
    return const CardDataCardDto(
      cardRef: 'valid-card',
      name: 'Goldkiss Rum',
      setName: 'High Seas',
      setCode: 'HNT',
      cardNumber: '001',
      finish: 'Normal',
      language: 'English',
      objectType: 'tcg',
      game: 'Flesh and Blood TCG',
      imageUrl: null,
      rarity: 'Pirate Booty',
    );
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) {
    throw Exception('prices unavailable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedPortfolioApi implements PortfolioApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedScanApi implements ScanApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

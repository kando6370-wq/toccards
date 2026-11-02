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
      expect(cards['valid-card']?.availableLanguages, ['English', 'Japanese']);
      expect(cards['valid-card']?.availableFinishes, ['Normal']);
      expect(cards['valid-card']?.prices, isEmpty);
    },
  );

  test(
    'review bounds concurrent requests while preserving every variant',
    () async {
      final api = _MeasuredCardDataApi();
      final repository = _repository(api);
      final refs = List.generate(10, (index) => 'card-$index');

      final cards = await repository.loadCards(refs);

      expect(
        api.peakRequests,
        lessThanOrEqualTo(4),
        reason: 'batch review must leave network capacity for other app work',
      );
      expect(api.cardCalls.values, everyElement(1));
      expect(api.priceCalls, hasLength(60));
      expect(cards.keys, refs);
      for (final card in cards.values) {
        expect(card.prices.map((price) => (price.finish, price.language)), [
          ('Normal', 'English'),
          ('Normal', 'Japanese'),
          ('Normal', 'French'),
          ('Foil', 'English'),
          ('Foil', 'Japanese'),
          ('Foil', 'French'),
        ]);
        expect(card.prices.map((price) => price.price), everyElement(0));
      }
    },
  );

  test(
    'preload and review share in-flight cards without caching completed prices',
    () async {
      final api = _MeasuredCardDataApi();
      final repository = _repository(api);

      final results = await Future.wait([
        repository.loadCards(['card-a', 'card-b']),
        repository.loadCards(['card-b', 'card-a', 'card-a']),
      ]);

      expect(api.cardCalls, {'card-a': 1, 'card-b': 1});
      expect(api.priceCalls, hasLength(12));
      expect(api.peakRequests, lessThanOrEqualTo(4));
      expect(results[0].keys, ['card-a', 'card-b']);
      expect(results[1].keys, ['card-b', 'card-a']);
      await repository.loadCards(['card-a']);
      expect(
        api.cardCalls['card-a'],
        2,
        reason: 'explicit later review must still fetch fresh prices',
      );
      expect(api.priceCalls, hasLength(18));
    },
  );

  test(
    'failed details and prices release capacity and can be retried',
    () async {
      final api = _MeasuredCardDataApi()
        ..failedCards.add('bad-card')
        ..failedPrices.add(('good-card', 'Foil', 'French'));
      final repository = _repository(api);

      final first = await repository.loadCards(['bad-card', 'good-card']);
      expect(first.keys, ['good-card']);
      expect(first['good-card']!.prices, hasLength(5));
      expect(api.activeRequests, 0);

      api.failedCards.clear();
      api.failedPrices.clear();
      final retry = await repository.loadCards(['bad-card', 'good-card']);
      expect(retry.keys, ['bad-card', 'good-card']);
      expect(retry.values.map((card) => card.prices.length), everyElement(6));
      expect(api.cardCalls, {'bad-card': 2, 'good-card': 2});
      expect(api.activeRequests, 0);
    },
  );
}

ApiScanReviewRepository _repository(CardDataApi api) => ApiScanReviewRepository(
  portfolioApi: _UnusedPortfolioApi(),
  cardDataApi: api,
  scanApi: _UnusedScanApi(),
  session: () => null,
);

class _MeasuredCardDataApi implements CardDataApi {
  final cardCalls = <String, int>{};
  final priceCalls = <(String, String?, String?)>[];
  final failedCards = <String>{};
  final failedPrices = <(String, String?, String?)>{};
  var activeRequests = 0;
  var peakRequests = 0;

  Future<T> _request<T>(T Function() result) async {
    activeRequests++;
    if (activeRequests > peakRequests) peakRequests = activeRequests;
    try {
      await Future<void>.delayed(Duration.zero);
      return result();
    } finally {
      activeRequests--;
    }
  }

  @override
  Future<CardDataCardDto> getCard(String cardRef) {
    cardCalls.update(cardRef, (count) => count + 1, ifAbsent: () => 1);
    return _request(() {
      if (failedCards.contains(cardRef)) throw Exception('detail unavailable');
      return CardDataCardDto(
        cardRef: cardRef,
        name: cardRef,
        setName: 'Test',
        setCode: 'TEST',
        cardNumber: '001',
        finish: 'Normal',
        language: 'English',
        availableFinishes: const ['Normal', 'Foil'],
        availableLanguages: const ['English', 'Japanese', 'French'],
        objectType: 'tcg',
        imageUrl: null,
        rarity: null,
      );
    });
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) {
    final selection = (cardRef, finish, language);
    priceCalls.add(selection);
    return _request(() {
      if (failedPrices.contains(selection)) {
        throw Exception('price unavailable');
      }
      return const [
        CardDataMarketPriceDto(
          grader: 'Ungraded',
          grade: null,
          condition: 'Near Mint',
          price: 0,
        ),
      ];
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
      availableLanguages: ['English', 'Japanese'],
      availableFinishes: ['Normal'],
      objectType: 'tcg',
      game: 'Flesh and Blood TCG',
      imageUrl: null,
      rarity: 'Pirate Booty',
    );
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(
    String cardRef, {
    String? finish,
    String? language,
  }) {
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

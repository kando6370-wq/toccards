import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/portfolio/portfolio_api_client.dart';
import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/card_data/card_data_api_client.dart';
import '../../shared/card_data/card_data_providers.dart';
import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

final scanReviewRepositoryProvider = Provider<ScanReviewRepository>((ref) {
  return ApiScanReviewRepository(
    portfolioApi: ref.watch(portfolioApiClientProvider),
    cardDataApi: ref.watch(cardDataApiClientProvider),
    scanApi: ref.watch(scanApiClientProvider),
    session: () => ref.read(authControllerProvider).session,
  );
});

class ScanReviewFolder {
  const ScanReviewFolder({required this.id, required this.name});

  final String id;
  final String name;
}

class ScanReviewTarget {
  const ScanReviewTarget({
    required this.folderId,
    required this.folderName,
    this.folders = const [],
  });

  final String folderId;
  final String folderName;
  final List<ScanReviewFolder> folders;
}

class ScanReviewPrice {
  const ScanReviewPrice({
    required this.grader,
    required this.grade,
    required this.condition,
    required this.price,
  });

  final String grader;
  final double? grade;
  final String? condition;
  final double? price;
}

class ScanReviewCard {
  const ScanReviewCard({
    required this.cardRef,
    required this.name,
    required this.setName,
    required this.cardNumber,
    required this.game,
    required this.imageUrl,
    required this.language,
    required this.finish,
    required this.prices,
  });

  final String cardRef;
  final String name;
  final String setName;
  final String cardNumber;
  final String? game;
  final String? imageUrl;
  final String? language;
  final String? finish;
  final List<ScanReviewPrice> prices;
}

abstract interface class ScanReviewRepository {
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId});

  Future<Map<String, ScanReviewCard>> loadCards(List<String> cardRefs);

  Future<ScanConfirmationDto> addToPortfolio({
    required String scanId,
    required ScanCollectionItemInput item,
  });
}

class ApiScanReviewRepository implements ScanReviewRepository {
  const ApiScanReviewRepository({
    required PortfolioApi portfolioApi,
    required CardDataApi cardDataApi,
    required ScanApi scanApi,
    required AuthSession? Function() session,
  }) : _portfolioApi = portfolioApi,
       _cardDataApi = cardDataApi,
       _scanApi = scanApi,
       _session = session;

  final PortfolioApi _portfolioApi;
  final CardDataApi _cardDataApi;
  final ScanApi _scanApi;
  final AuthSession? Function() _session;

  @override
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId}) async {
    final session = _requiredSession();
    final folders = await _portfolioApi.listFolders(session);
    if (folders.isEmpty) {
      throw StateError('Portfolio folder is unavailable.');
    }
    final folder = folders.firstWhere(
      (candidate) => candidate.id == preferredFolderId,
      orElse: () => folders.firstWhere(
        (candidate) => candidate.isDefault,
        orElse: () => folders.first,
      ),
    );
    return ScanReviewTarget(
      folderId: folder.id,
      folderName: folder.name,
      folders: folders
          .map((folder) => ScanReviewFolder(id: folder.id, name: folder.name))
          .toList(),
    );
  }

  @override
  Future<Map<String, ScanReviewCard>> loadCards(List<String> cardRefs) async {
    final uniqueRefs = cardRefs.toSet();
    final entries = await Future.wait(
      uniqueRefs.map((cardRef) async {
        final results = await Future.wait([
          _cardDataApi.getCard(cardRef),
          _cardDataApi.getMarketPrices(cardRef),
        ]);
        final card = results[0] as CardDataCardDto;
        final prices = results[1] as List<CardDataMarketPriceDto>;
        return MapEntry(
          cardRef,
          ScanReviewCard(
            cardRef: card.cardRef,
            name: card.name,
            setName: card.setName,
            cardNumber: card.cardNumber,
            game: card.game,
            imageUrl: card.imageUrl,
            language: card.language,
            finish: card.finish,
            prices: prices
                .map(
                  (price) => ScanReviewPrice(
                    grader: price.grader,
                    grade: price.grade,
                    condition: price.condition,
                    price: price.price,
                  ),
                )
                .toList(),
          ),
        );
      }),
    );
    return Map.fromEntries(entries);
  }

  @override
  Future<ScanConfirmationDto> addToPortfolio({
    required String scanId,
    required ScanCollectionItemInput item,
  }) {
    final session = _requiredSession();
    return _scanApi.confirmMatch(session, scanId: scanId, item: item);
  }

  AuthSession _requiredSession() {
    final session = _session();
    if (session == null) throw StateError('Scan session is unavailable.');
    return session;
  }
}

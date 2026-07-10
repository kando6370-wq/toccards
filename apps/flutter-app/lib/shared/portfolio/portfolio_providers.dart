import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'portfolio_api_client.dart';

final portfolioDioProvider = Provider((ref) {
  final dio = createPortfolioDio();
  ref.onDispose(dio.close);
  return dio;
});

final portfolioApiClientProvider = Provider<PortfolioApi>((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});

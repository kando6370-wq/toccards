import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';

import 'portfolio_api_client.dart';

final portfolioDioProvider = Provider((ref) {
  final dio = createPortfolioDio();
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
  );
  ref.onDispose(dio.close);
  return dio;
});

final portfolioApiClientProvider = Provider<PortfolioApi>((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});

final portfolioManagementApiProvider = Provider<PortfolioManagementApi>((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});

final selectedPortfolioFolderProvider =
    NotifierProvider<SelectedPortfolioFolderController, String?>(
      SelectedPortfolioFolderController.new,
    );

class SelectedPortfolioFolderController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String folderId) {
    state = folderId;
  }
}

final portfolioAmountHiddenProvider =
    NotifierProvider<PortfolioAmountHiddenController, bool?>(
      PortfolioAmountHiddenController.new,
    );

class PortfolioAmountHiddenController extends Notifier<bool?> {
  @override
  bool? build() => null;

  void select(bool amountHidden) {
    state = amountHidden;
  }
}

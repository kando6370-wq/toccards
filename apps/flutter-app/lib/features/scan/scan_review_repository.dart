import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/portfolio/portfolio_api_client.dart';
import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

final scanReviewRepositoryProvider = Provider<ScanReviewRepository>((ref) {
  return ApiScanReviewRepository(
    portfolioApi: ref.watch(portfolioApiClientProvider),
    scanApi: ref.watch(scanApiClientProvider),
    session: () => ref.read(authControllerProvider).session,
  );
});

class ScanReviewTarget {
  const ScanReviewTarget({required this.folderId, required this.folderName});

  final String folderId;
  final String folderName;
}

abstract interface class ScanReviewRepository {
  Future<ScanReviewTarget> loadTarget({String? preferredFolderId});

  Future<ScanConfirmationDto> addToPortfolio({
    required ScanReviewTarget target,
    required String scanId,
    required String cardRef,
  });
}

class ApiScanReviewRepository implements ScanReviewRepository {
  const ApiScanReviewRepository({
    required PortfolioApi portfolioApi,
    required ScanApi scanApi,
    required AuthSession? Function() session,
  }) : _portfolioApi = portfolioApi,
       _scanApi = scanApi,
       _session = session;

  final PortfolioApi _portfolioApi;
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
    return ScanReviewTarget(folderId: folder.id, folderName: folder.name);
  }

  @override
  Future<ScanConfirmationDto> addToPortfolio({
    required ScanReviewTarget target,
    required String scanId,
    required String cardRef,
  }) {
    final session = _requiredSession();
    return _scanApi.confirmMatch(
      session,
      scanId: scanId,
      folderId: target.folderId,
      cardRef: cardRef,
    );
  }

  AuthSession _requiredSession() {
    final session = _session();
    if (session == null) throw StateError('Scan session is unavailable.');
    return session;
  }
}

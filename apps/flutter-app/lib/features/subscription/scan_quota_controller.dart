import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import 'subscription_controller.dart';

final freeScanLimitProvider = Provider<int>((ref) {
  const configured = int.fromEnvironment(
    'SUBSCRIPTION_FREE_SCAN_LIMIT',
    defaultValue: 10,
  );
  return configured < 0 ? 0 : configured;
});

final scanQuotaControllerProvider =
    NotifierProvider<ScanQuotaController, ScanQuotaState>(
      ScanQuotaController.new,
    );

class ScanQuotaState {
  const ScanQuotaState({
    required this.limit,
    required this.remainingScans,
    this.isLoading = false,
    this.unlimited = false,
    this.isServerAuthoritative = false,
  });

  final int limit;
  final int remainingScans;
  final bool isLoading;
  final bool unlimited;
  final bool isServerAuthoritative;

  ScanQuotaState copyWith({bool? isLoading}) {
    return ScanQuotaState(
      limit: limit,
      remainingScans: remainingScans,
      isLoading: isLoading ?? this.isLoading,
      unlimited: unlimited,
      isServerAuthoritative: isServerAuthoritative,
    );
  }
}

class ScanQuotaController extends Notifier<ScanQuotaState> {
  @override
  ScanQuotaState build() {
    final limit = ref.watch(freeScanLimitProvider);
    return ScanQuotaState(limit: limit, remainingScans: limit, isLoading: true);
  }

  void applyServerQuota(ScanQuotaDto quota) {
    state = ScanQuotaState(
      limit: quota.limit,
      remainingScans: quota.remaining,
      isLoading: false,
      unlimited: quota.unlimited,
      isServerAuthoritative: true,
    );
  }

  Future<bool> refresh() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return false;
    state = state.copyWith(isLoading: true);
    try {
      final quota = await ref
          .read(scanApiClientProvider)
          .getQuota(
            session,
            localPremiumVerified: ref
                .read(subscriptionControllerProvider)
                .isPro,
          );
      if (!ref.mounted) return false;
      applyServerQuota(quota);
      return true;
    } on Object {
      if (ref.mounted) state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

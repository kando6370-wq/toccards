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
    int? displayRemainingScans,
    this.serverConsumedScans = 0,
    this.isLoading = false,
    this.unlimited = false,
    this.isServerAuthoritative = false,
  }) : displayRemainingScans = displayRemainingScans ?? remainingScans;

  final int limit;

  // Includes active reservations and remains the source for capture/queue gates.
  final int remainingScans;

  // Excludes reservations until a result is revealed as a usable match.
  final int displayRemainingScans;
  final int serverConsumedScans;
  final bool isLoading;
  final bool unlimited;
  final bool isServerAuthoritative;

  ScanQuotaState copyWith({bool? isLoading, int? displayRemainingScans}) {
    return ScanQuotaState(
      limit: limit,
      remainingScans: remainingScans,
      displayRemainingScans:
          displayRemainingScans ?? this.displayRemainingScans,
      serverConsumedScans: serverConsumedScans,
      isLoading: isLoading ?? this.isLoading,
      unlimited: unlimited,
      isServerAuthoritative: isServerAuthoritative,
    );
  }
}

class ScanQuotaController extends Notifier<ScanQuotaState> {
  var _quotaRevision = 0;

  @override
  ScanQuotaState build() {
    final limit = ref.watch(freeScanLimitProvider);
    return ScanQuotaState(limit: limit, remainingScans: limit, isLoading: true);
  }

  void applyServerQuota(
    ScanQuotaDto quota, {
    bool syncDisplayedRemaining = true,
  }) {
    _quotaRevision += 1;
    final settledRemaining = (quota.limit - quota.consumed)
        .clamp(0, quota.limit)
        .toInt();
    final serverConsumedScans = syncDisplayedRemaining
        ? quota.consumed
        : quota.consumed > state.serverConsumedScans
        ? quota.consumed
        : state.serverConsumedScans;
    state = ScanQuotaState(
      limit: quota.limit,
      remainingScans: quota.remaining,
      displayRemainingScans: syncDisplayedRemaining
          ? settledRemaining
          : state.displayRemainingScans.clamp(0, quota.limit).toInt(),
      serverConsumedScans: serverConsumedScans,
      isLoading: false,
      unlimited: quota.unlimited,
      isServerAuthoritative: true,
    );
  }

  // Advances presentation only; the server has already settled this scan.
  void revealSuccessfulScanInDisplay() {
    if (state.unlimited) return;
    final settledRemaining = (state.limit - state.serverConsumedScans)
        .clamp(0, state.limit)
        .toInt();
    if (state.displayRemainingScans <= settledRemaining) return;
    state = state.copyWith(
      displayRemainingScans: state.displayRemainingScans - 1,
    );
  }

  Future<bool> refresh() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return false;
    final quotaRevision = _quotaRevision;
    state = state.copyWith(isLoading: true);
    Future<ScanQuotaDto> request() => ref
        .read(scanApiClientProvider)
        .getQuota(
          session,
          localPremiumVerified: ref.read(subscriptionControllerProvider).isPro,
        );
    try {
      final quota = await request();
      if (!ref.mounted) return false;
      if (_quotaRevision != quotaRevision) return true;
      applyServerQuota(quota);
      return true;
    } on ScanApiException catch (error) {
      if (!ref.mounted) return false;
      if (_quotaRevision != quotaRevision) return true;
      if (error.statusCode != 409 ||
          error.code != 'ENTITLEMENT_SYNC_REQUIRED') {
        if (ref.mounted) state = state.copyWith(isLoading: false);
        return false;
      }
      final reconciliation = await ref
          .read(subscriptionControllerProvider.notifier)
          .reconcileServerEntitlement();
      if (reconciliation ==
              EntitlementReconciliationResult.verificationUnavailable ||
          !ref.mounted) {
        if (ref.mounted) state = state.copyWith(isLoading: false);
        return false;
      }
      if (_quotaRevision != quotaRevision) return true;
      try {
        final quota = await request();
        if (!ref.mounted) return false;
        if (_quotaRevision != quotaRevision) return true;
        applyServerQuota(quota);
        return true;
      } on Object {
        if (ref.mounted) state = state.copyWith(isLoading: false);
        return false;
      }
    } on Object {
      if (ref.mounted) state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

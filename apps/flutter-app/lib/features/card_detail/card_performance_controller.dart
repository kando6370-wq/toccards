import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/shared/api/api_request_executor.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

final cardPerformanceControllerProvider = NotifierProvider.autoDispose
    .family<CardPerformanceController, CardPerformanceState, String>(
      CardPerformanceController.new,
    );

class CardPerformanceState {
  const CardPerformanceState({
    this.selectedRange = PerformanceRange.oneMonth,
    this.data,
    this.status = KandoLoadStatus.content,
    this.hasLoaded = false,
  });

  final PerformanceRange selectedRange;
  final PortfolioPerformanceDto? data;
  final KandoLoadStatus status;
  final bool hasLoaded;

  bool get isLoading => status == KandoLoadStatus.loading;
  bool get isFailure => status == KandoLoadStatus.failure;
}

class CardPerformanceController extends Notifier<CardPerformanceState> {
  CardPerformanceController(this.itemId);

  final String itemId;
  var _generation = 0;

  @override
  CardPerformanceState build() => const CardPerformanceState();

  Future<void> load({required bool localPremiumVerified, bool force = false}) {
    if (!force && state.hasLoaded && !state.isFailure) {
      return Future<void>.value();
    }
    return _request(
      range: state.selectedRange,
      localPremiumVerified: localPremiumVerified,
    );
  }

  Future<void> selectRange(
    PerformanceRange range, {
    required bool localPremiumVerified,
  }) {
    if (range == state.selectedRange && state.hasLoaded && !state.isFailure) {
      return Future<void>.value();
    }
    return _request(range: range, localPremiumVerified: localPremiumVerified);
  }

  Future<void> _request({
    required PerformanceRange range,
    required bool localPremiumVerified,
  }) async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    final generation = ++_generation;
    final previous = state;
    state = CardPerformanceState(
      selectedRange: range,
      data: previous.data,
      status: KandoLoadStatus.loading,
      hasLoaded: previous.hasLoaded,
    );
    try {
      final deadline = ApiRequestDeadline(portfolioRequestDeadline);
      PortfolioApiException timeoutException() => const PortfolioApiException(
        portfolioRequestTimeoutMessage,
        code: portfolioRequestTimeoutCode,
      );
      Future<PortfolioPerformanceDto> request() => runWithinApiDeadline(
        deadline,
        () => ref
            .read(portfolioApiClientProvider)
            .getItemPerformance(
              session,
              itemId: itemId,
              range: range,
              localPremiumVerified: localPremiumVerified,
              deadline: deadline,
            ),
        timeoutException: timeoutException,
      );
      late final PortfolioPerformanceDto data;
      try {
        data = await request();
      } on PortfolioApiException catch (error) {
        if (error.statusCode != 409 ||
            error.code != 'ENTITLEMENT_SYNC_REQUIRED') {
          rethrow;
        }
        final reconciliation = await runWithinApiDeadline(
          deadline,
          () => ref
              .read(subscriptionControllerProvider.notifier)
              .reconcileServerEntitlement(),
          timeoutException: timeoutException,
        );
        if (reconciliation !=
            EntitlementReconciliationResult.premiumSynchronized) {
          rethrow;
        }
        data = await request();
      }
      if (!ref.mounted || generation != _generation) return;
      state = CardPerformanceState(
        selectedRange: range,
        data: data,
        hasLoaded: true,
      );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      state = CardPerformanceState(
        selectedRange: previous.selectedRange,
        data: previous.data,
        status: KandoLoadStatus.failure,
        hasLoaded: previous.hasLoaded,
      );
    }
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

final homePerformanceControllerProvider =
    NotifierProvider<HomePerformanceController, HomePerformanceState>(
      HomePerformanceController.new,
    );

class HomePerformanceState {
  const HomePerformanceState({
    this.selectedRange = PerformanceRange.oneMonth,
    this.folderId,
    this.data,
    this.status = KandoLoadStatus.content,
    this.hasLoaded = false,
    this.failureCode,
  });

  final PerformanceRange selectedRange;
  final String? folderId;
  final PortfolioPerformanceDto? data;
  final KandoLoadStatus status;
  final bool hasLoaded;
  final String? failureCode;

  bool get isLoading => status == KandoLoadStatus.loading;
  bool get isFailure => status == KandoLoadStatus.failure;
}

class HomePerformanceController extends Notifier<HomePerformanceState> {
  var _generation = 0;

  @override
  HomePerformanceState build() => const HomePerformanceState();

  Future<void> load({
    required String folderId,
    required bool localPremiumVerified,
    bool force = false,
  }) {
    final sameFolder = state.folderId == folderId;
    if (sameFolder &&
        (state.isLoading || !force && (state.hasLoaded || state.isFailure))) {
      return Future<void>.value();
    }
    return _request(
      folderId: folderId,
      range: state.selectedRange,
      localPremiumVerified: localPremiumVerified,
      clearData: state.folderId != folderId,
    );
  }

  Future<void> selectRange(
    PerformanceRange range, {
    required String folderId,
    required bool localPremiumVerified,
  }) {
    if (range == state.selectedRange && state.hasLoaded && !state.isFailure) {
      return Future<void>.value();
    }
    return _request(
      folderId: folderId,
      range: range,
      localPremiumVerified: localPremiumVerified,
      clearData: false,
    );
  }

  Future<void> _request({
    required String folderId,
    required PerformanceRange range,
    required bool localPremiumVerified,
    required bool clearData,
  }) async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) return;
    final generation = ++_generation;
    final previous = state;
    state = HomePerformanceState(
      selectedRange: range,
      folderId: folderId,
      data: clearData ? null : previous.data,
      status: KandoLoadStatus.loading,
      hasLoaded: previous.hasLoaded && !clearData,
    );
    try {
      final data = await ref
          .read(portfolioApiClientProvider)
          .getPortfolioPerformance(
            session,
            range: range,
            folderId: folderId,
            localPremiumVerified: localPremiumVerified,
          )
          .timeout(const Duration(seconds: 15));
      if (!ref.mounted || generation != _generation) return;
      state = HomePerformanceState(
        selectedRange: range,
        folderId: folderId,
        data: data,
        hasLoaded: true,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = HomePerformanceState(
        selectedRange: previous.data?.range ?? previous.selectedRange,
        folderId: folderId,
        data: clearData ? null : previous.data,
        status: KandoLoadStatus.failure,
        hasLoaded: previous.hasLoaded && !clearData,
        failureCode: error is PortfolioApiException ? error.code : null,
      );
    }
  }
}

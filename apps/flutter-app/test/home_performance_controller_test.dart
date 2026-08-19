import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/home/home_performance_controller.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';

void main() {
  test(
    'Range failures preserve the last valid range because a failed selection must not replace visible data',
    () async {
      final api = _ControlledPerformanceApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          portfolioApiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        homePerformanceControllerProvider.notifier,
      );

      final initial = controller.load(
        folderId: 'main',
        localPremiumVerified: true,
      );
      api.completeNext(_performance(PerformanceRange.oneMonth, 100));
      await initial;
      final failed = controller.selectRange(
        PerformanceRange.oneYear,
        folderId: 'main',
        localPremiumVerified: true,
      );
      api.failNext();
      await failed;

      final state = container.read(homePerformanceControllerProvider);
      expect(state.selectedRange, PerformanceRange.oneMonth);
      expect(state.data?.current.marketValueUsd, 100);
      expect(state.isFailure, isTrue);
    },
  );

  test(
    'A late old-range response cannot overwrite the newer folder context',
    () async {
      final api = _ControlledPerformanceApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          portfolioApiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        homePerformanceControllerProvider.notifier,
      );

      final oldRequest = controller.selectRange(
        PerformanceRange.oneYear,
        folderId: 'folder-a',
        localPremiumVerified: true,
      );
      final newRequest = controller.load(
        folderId: 'folder-b',
        localPremiumVerified: true,
      );
      api.completeAt(1, _performance(PerformanceRange.oneMonth, 200));
      await newRequest;
      api.completeAt(0, _performance(PerformanceRange.oneYear, 999));
      await oldRequest;

      final state = container.read(homePerformanceControllerProvider);
      expect(state.folderId, 'folder-b');
      expect(state.selectedRange, PerformanceRange.oneMonth);
      expect(state.data?.current.marketValueUsd, 200);
      expect(api.requests.map((request) => request.folderId), [
        'folder-a',
        'folder-b',
      ]);
    },
  );

  test(
    'A failed automatic load is not repeated for the same target until an explicit retry',
    () async {
      final api = _ControlledPerformanceApi();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          portfolioApiClientProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        homePerformanceControllerProvider.notifier,
      );

      final initial = controller.load(
        folderId: 'main',
        localPremiumVerified: true,
      );
      api.failNext();
      await initial;

      final duplicate = controller.load(
        folderId: 'main',
        localPremiumVerified: true,
      );
      if (api.requests.length > 1) {
        api.completeAt(1, _performance(PerformanceRange.oneMonth, 100));
      }
      await duplicate;

      expect(api.requests, hasLength(1));
    },
  );
}

class _ReadyAuthController extends AuthController {
  @override
  AuthState build() => const AuthState.ready(
    session: AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'access',
      refreshToken: 'refresh',
      userId: 'user-1',
    ),
  );
}

class _PerformanceRequest {
  const _PerformanceRequest(this.folderId, this.range);

  final String? folderId;
  final PerformanceRange range;
}

class _ControlledPerformanceApi extends PortfolioApiClient {
  _ControlledPerformanceApi() : super(Dio());

  final requests = <_PerformanceRequest>[];
  final _pending = <Completer<PortfolioPerformanceDto>>[];

  @override
  Future<PortfolioPerformanceDto> getPortfolioPerformance(
    AuthSession session, {
    required PerformanceRange range,
    String? folderId,
    bool localPremiumVerified = false,
  }) {
    expect(localPremiumVerified, isTrue);
    requests.add(_PerformanceRequest(folderId, range));
    final completer = Completer<PortfolioPerformanceDto>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext(PortfolioPerformanceDto data) => completeAt(0, data);

  void completeAt(int index, PortfolioPerformanceDto data) {
    _pending[index].complete(data);
  }

  void failNext() {
    _pending.last.completeError(const PortfolioApiException('failed'));
  }
}

PortfolioPerformanceDto _performance(PerformanceRange range, double value) {
  final point = PerformancePointDto(
    date: '2026-08-12',
    marketValueUsd: value,
    marketValueChangeUsd: 3,
    marketChangeUsd: 1,
    portfolioChangeUsd: 2,
    paidMarketValueUsd: value,
    totalPaidUsd: 50,
    profitLossUsd: value - 50,
    profitLossChangeUsd: 3,
    returnPercent: 100,
    quantity: 2,
    quantityChange: 0,
  );
  return PortfolioPerformanceDto(
    range: range,
    rangeStart: '2026-07-12',
    rangeEnd: '2026-08-12',
    historyAvailableFrom: '2026-07-12',
    partialHistory: false,
    itemCount: 1,
    marketPriceStatus: MarketPriceStatus.available,
    purchasePriceStatus: PurchasePriceStatus.complete,
    current: point,
    series: [point],
  );
}

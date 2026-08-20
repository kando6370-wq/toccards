import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_performance_controller.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';

void main() {
  test(
    'failed Item range keeps the last valid Card Performance data',
    () async {
      final api = _ControlledItemPerformanceApi();
      final container = _container(api);
      addTearDown(container.dispose);
      final controller = container.read(
        cardPerformanceControllerProvider('item-1').notifier,
      );
      final initial = controller.load(localPremiumVerified: true);
      api.completeAt(0, _performance(PerformanceRange.oneMonth, 100));
      await initial;
      final failed = controller.selectRange(
        PerformanceRange.oneYear,
        localPremiumVerified: true,
      );
      api.failAt(1);
      await failed;

      final state = container.read(cardPerformanceControllerProvider('item-1'));
      expect(state.selectedRange, PerformanceRange.oneMonth);
      expect(state.data?.current.marketValueUsd, 100);
      expect(state.isFailure, isTrue);
    },
  );

  test(
    'late Item response cannot overwrite the newer Card Performance range',
    () async {
      final api = _ControlledItemPerformanceApi();
      final container = _container(api);
      addTearDown(container.dispose);
      final controller = container.read(
        cardPerformanceControllerProvider('item-1').notifier,
      );
      final oldRequest = controller.selectRange(
        PerformanceRange.sevenDays,
        localPremiumVerified: true,
      );
      final newRequest = controller.selectRange(
        PerformanceRange.oneYear,
        localPremiumVerified: true,
      );
      api.completeAt(1, _performance(PerformanceRange.oneYear, 200));
      await newRequest;
      api.completeAt(0, _performance(PerformanceRange.sevenDays, 999));
      await oldRequest;

      final state = container.read(cardPerformanceControllerProvider('item-1'));
      expect(state.selectedRange, PerformanceRange.oneYear);
      expect(state.data?.current.marketValueUsd, 200);
      expect(api.itemIds, ['item-1', 'item-1']);
    },
  );
}

ProviderContainer _container(_ControlledItemPerformanceApi api) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(_ReadyAuthController.new),
      portfolioApiClientProvider.overrideWithValue(api),
    ],
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

class _ControlledItemPerformanceApi extends PortfolioApiClient {
  _ControlledItemPerformanceApi() : super(Dio());

  final itemIds = <String>[];
  final _pending = <Completer<PortfolioPerformanceDto>>[];

  @override
  Future<PortfolioPerformanceDto> getItemPerformance(
    AuthSession session, {
    required String itemId,
    required PerformanceRange range,
    bool localPremiumVerified = false,
  }) {
    expect(localPremiumVerified, isTrue);
    itemIds.add(itemId);
    final completer = Completer<PortfolioPerformanceDto>();
    _pending.add(completer);
    return completer.future;
  }

  void completeAt(int index, PortfolioPerformanceDto data) {
    _pending[index].complete(data);
  }

  void failAt(int index) {
    _pending[index].completeError(const PortfolioApiException('failed'));
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
    quantity: 1,
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
    purchasePriceItemCount: 1,
    current: point,
    series: [point],
  );
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:subscription_core/subscription_core.dart';

const subscriptionWeeklyPlanId = 'weekly';
const subscriptionYearlyPlanId = 'yearly';
const subscriptionLifetimePlanId = 'lifetime';

class SubscriptionPlanPresentation {
  const SubscriptionPlanPresentation({
    required this.id,
    required this.title,
    required this.fallbackPrice,
    required this.periodLabel,
    this.badge,
  });

  final String id;
  final String title;
  final String fallbackPrice;
  final String periodLabel;
  final String? badge;
}

const subscriptionPlans = [
  SubscriptionPlanPresentation(
    id: subscriptionWeeklyPlanId,
    title: 'Weekly',
    fallbackPrice: r'$4.99',
    periodLabel: 'per week',
  ),
  SubscriptionPlanPresentation(
    id: subscriptionYearlyPlanId,
    title: 'Yearly',
    fallbackPrice: r'$49.99',
    periodLabel: 'per year',
    badge: 'MOST POPULAR',
  ),
  SubscriptionPlanPresentation(
    id: subscriptionLifetimePlanId,
    title: 'Lifetime Access',
    fallbackPrice: r'$79.99',
    periodLabel: 'one-time purchase',
    badge: 'BEST VALUE',
  ),
];

class AppSubscriptionConfiguration {
  const AppSubscriptionConfiguration({
    required this.store,
    required this.productIds,
  });

  factory AppSubscriptionConfiguration.fromEnvironment() {
    final store = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => SubscriptionStore.appStore,
      TargetPlatform.android => SubscriptionStore.googlePlay,
      _ => null,
    };
    if (store == null) {
      return const AppSubscriptionConfiguration(store: null, productIds: {});
    }
    final productIds = store == SubscriptionStore.appStore
        ? const {
            subscriptionWeeklyPlanId: String.fromEnvironment(
              'SUBSCRIPTION_APP_STORE_WEEKLY_ID',
            ),
            subscriptionYearlyPlanId: String.fromEnvironment(
              'SUBSCRIPTION_APP_STORE_YEARLY_ID',
            ),
            subscriptionLifetimePlanId: String.fromEnvironment(
              'SUBSCRIPTION_APP_STORE_LIFETIME_ID',
            ),
          }
        : const {
            subscriptionWeeklyPlanId: String.fromEnvironment(
              'SUBSCRIPTION_GOOGLE_PLAY_WEEKLY_ID',
            ),
            subscriptionYearlyPlanId: String.fromEnvironment(
              'SUBSCRIPTION_GOOGLE_PLAY_YEARLY_ID',
            ),
            subscriptionLifetimePlanId: String.fromEnvironment(
              'SUBSCRIPTION_GOOGLE_PLAY_LIFETIME_ID',
            ),
          };
    return AppSubscriptionConfiguration(store: store, productIds: productIds);
  }

  final SubscriptionStore? store;
  final Map<String, String> productIds;

  bool get isConfigured =>
      store != null && productIds.values.every((value) => value.isNotEmpty);
}

final appSubscriptionConfigurationProvider =
    Provider<AppSubscriptionConfiguration>((ref) {
      return AppSubscriptionConfiguration.fromEnvironment();
    });

final subscriptionReceiptVerifierProvider =
    Provider<SubscriptionReceiptVerifier>((ref) {
      return const _MissingSubscriptionReceiptVerifier();
    });

final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, SubscriptionState>(
      SubscriptionController.new,
    );

class SubscriptionState {
  const SubscriptionState({
    this.selectedPlanId = subscriptionYearlyPlanId,
    this.displayPrices = const {},
    this.isConfigured = false,
    this.isLoading = false,
    this.isPro = false,
    this.completionCount = 0,
    this.errorMessage,
  });

  final String selectedPlanId;
  final Map<String, String> displayPrices;
  final bool isConfigured;
  final bool isLoading;
  final bool isPro;
  final int completionCount;
  final String? errorMessage;

  SubscriptionState copyWith({
    String? selectedPlanId,
    Map<String, String>? displayPrices,
    bool? isConfigured,
    bool? isLoading,
    bool? isPro,
    int? completionCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SubscriptionState(
      selectedPlanId: selectedPlanId ?? this.selectedPlanId,
      displayPrices: displayPrices ?? this.displayPrices,
      isConfigured: isConfigured ?? this.isConfigured,
      isLoading: isLoading ?? this.isLoading,
      isPro: isPro ?? this.isPro,
      completionCount: completionCount ?? this.completionCount,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SubscriptionController extends Notifier<SubscriptionState> {
  SubscriptionClient? _client;
  StreamSubscription<SubscriptionEvent>? _eventSubscription;
  SubscriptionStore? _store;

  @override
  SubscriptionState build() {
    final configuration = ref.watch(appSubscriptionConfigurationProvider);
    ref.onDispose(() {
      unawaited(_eventSubscription?.cancel());
      unawaited(_client?.dispose());
    });
    if (!configuration.isConfigured) {
      return const SubscriptionState();
    }
    Future<void>.microtask(() => _initialize(configuration));
    return const SubscriptionState(isConfigured: true, isLoading: true);
  }

  void selectPlan(String planId) {
    state = state.copyWith(selectedPlanId: planId, clearError: true);
  }

  Future<void> purchase() async {
    final client = _client;
    final store = _store;
    if (client == null || store == null) {
      state = state.copyWith(
        errorMessage: 'Subscription products are not configured.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await client.purchase(planId: state.selectedPlanId, store: store);
    } on Exception {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to start the purchase. Please try again.',
      );
    }
  }

  Future<void> restore() async {
    final client = _client;
    if (client == null) {
      state = state.copyWith(
        errorMessage: 'Subscription products are not configured.',
      );
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    final failures = await client.restore(store: _store);
    if (failures.isNotEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Unable to restore purchases. Please try again.',
      );
    }
  }

  Future<void> _initialize(AppSubscriptionConfiguration configuration) async {
    final store = configuration.store!;
    final config = SubscriptionConfig(
      enabledStores: {store},
      plans: subscriptionPlans
          .map(
            (plan) => SubscriptionPlanConfig(
              id: plan.id,
              entitlementId: 'performance_pro',
              productIds: {store: configuration.productIds[plan.id]!},
            ),
          )
          .toList(growable: false),
    );
    final client = SubscriptionClient(
      config: config,
      gateways: [InAppPurchaseSubscriptionGateway(store: store)],
      verifier: ref.read(subscriptionReceiptVerifierProvider),
    );
    _store = store;
    _client = client;
    _eventSubscription = client.events.listen(_handleEvent);
    try {
      await client.initialize();
      final catalog = await client.loadProducts();
      final prices = <String, String>{};
      for (final product in catalog.products) {
        final plan = config.planByProductId(store, product.storeProductId);
        if (plan != null) prices[plan.id] = product.displayPrice;
      }
      state = state.copyWith(
        displayPrices: prices,
        isLoading: false,
        errorMessage: catalog.hasProducts
            ? null
            : 'Subscription products are unavailable.',
        clearError: catalog.hasProducts,
      );
    } on Exception {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Subscription products are unavailable.',
      );
    }
  }

  void _handleEvent(SubscriptionEvent event) {
    final entitlement = event.entitlement;
    if (entitlement?.isActive == true) {
      state = state.copyWith(
        isLoading: false,
        isPro: true,
        completionCount: state.completionCount + 1,
        clearError: true,
      );
      return;
    }
    if (event.failure != null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'The subscription could not be verified.',
      );
      return;
    }
    if (event.purchase?.status == SubscriptionPurchaseStatus.canceled) {
      state = state.copyWith(isLoading: false, clearError: true);
    }
  }
}

class _MissingSubscriptionReceiptVerifier
    implements SubscriptionReceiptVerifier {
  const _MissingSubscriptionReceiptVerifier();

  @override
  Future<SubscriptionEntitlement> verify(
    SubscriptionVerificationRequest request,
  ) {
    throw StateError('A receipt verifier must be configured by the app.');
  }
}

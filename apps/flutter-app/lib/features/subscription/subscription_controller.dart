import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:subscription_core/subscription_core.dart';

import '../../shared/portfolio/portfolio_providers.dart';
import '../../shared/analytics/app_analytics.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import 'apple_app_attest.dart';
import 'apple_current_entitlements.dart';
import 'subscription_entitlement_api.dart';
import 'subscription_entitlement_cache.dart';
import 'subscription_revenue_reporter.dart';
import 'subscription_sync_queue.dart';

const subscriptionWeeklyPlanId = 'weekly';
const subscriptionYearlyPlanId = 'yearly';
const subscriptionLifetimePlanId = 'lifetime';
const subscriptionSheetLocation = '/subscription?presentation=sheet';
const scanSubscriptionLocation = '/subscription?source=scan';
const profileSubscriptionLocation =
    '/subscription?source=profile&entry_source=profile_banner';

enum SubscriptionPaywallResult { premiumUnlocked, premiumRestored }

class SubscriptionPlanPresentation {
  const SubscriptionPlanPresentation({
    required this.id,
    required this.title,
    required this.periodLabel,
    this.badge,
  });

  final String id;
  final String title;
  final String periodLabel;
  final String? badge;
}

const subscriptionPlans = [
  SubscriptionPlanPresentation(
    id: subscriptionWeeklyPlanId,
    title: 'Weekly',
    periodLabel: 'per week',
  ),
  SubscriptionPlanPresentation(
    id: subscriptionYearlyPlanId,
    title: 'Yearly',
    periodLabel: 'per year',
    badge: 'MOST POPULAR',
  ),
  SubscriptionPlanPresentation(
    id: subscriptionLifetimePlanId,
    title: 'Lifetime Access',
    periodLabel: 'one-time purchase',
    badge: 'BEST VALUE',
  ),
];

class AppSubscriptionConfiguration {
  const AppSubscriptionConfiguration({
    required this.store,
    required this.productIds,
  });

  factory AppSubscriptionConfiguration.fromEnvironment({
    TargetPlatform? platform,
  }) {
    final store = switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS => SubscriptionStore.appStore,
      _ => null,
    };
    if (store == null) {
      return const AppSubscriptionConfiguration(store: null, productIds: {});
    }
    const productIds = {
      subscriptionWeeklyPlanId: String.fromEnvironment(
        'SUBSCRIPTION_APP_STORE_WEEKLY_ID',
      ),
      subscriptionYearlyPlanId: String.fromEnvironment(
        'SUBSCRIPTION_APP_STORE_YEARLY_ID',
      ),
      subscriptionLifetimePlanId: String.fromEnvironment(
        'SUBSCRIPTION_APP_STORE_LIFETIME_ID',
      ),
    };
    return AppSubscriptionConfiguration(store: store, productIds: productIds);
  }

  final SubscriptionStore? store;
  final Map<String, String> productIds;

  Map<String, String> get configuredProductIds => Map.unmodifiable(
    Map.fromEntries(
      productIds.entries.where((entry) => entry.value.isNotEmpty),
    ),
  );

  bool get isConfigured => store != null && configuredProductIds.isNotEmpty;
}

final appSubscriptionConfigurationProvider =
    Provider<AppSubscriptionConfiguration>((ref) {
      return AppSubscriptionConfiguration.fromEnvironment();
    });

final subscriptionReceiptVerifierProvider =
    Provider<SubscriptionReceiptVerifier>((ref) {
      return StoreKit2SubscriptionReceiptVerifier(
        session: () => ref.read(authControllerProvider).session,
        syncQueue: ref.watch(subscriptionSyncQueueProvider),
      );
    });

final subscriptionEntitlementApiProvider = Provider<SubscriptionEntitlementApi>(
  (ref) {
    return HttpSubscriptionEntitlementApi(ref.watch(portfolioDioProvider));
  },
);

final appleRestoreProofApiProvider = Provider<AppleRestoreProofApi>((ref) {
  return HttpSubscriptionEntitlementApi(ref.watch(portfolioDioProvider));
});

final appleLifecycleApiProvider = Provider<AppleLifecycleApi>((ref) {
  return HttpSubscriptionEntitlementApi(ref.watch(portfolioDioProvider));
});

final subscriptionSyncStorageProvider = Provider<SubscriptionSyncStorage>((
  ref,
) {
  return const SecureSubscriptionSyncStorage();
});

final subscriptionSyncQueueProvider = Provider<SubscriptionSyncQueue>((ref) {
  return SubscriptionSyncQueue(
    storage: ref.watch(subscriptionSyncStorageProvider),
    api: ref.watch(subscriptionEntitlementApiProvider),
  );
});

final appleCurrentEntitlementReaderProvider =
    Provider<AppleCurrentEntitlementReader>((ref) {
      return const MethodChannelAppleCurrentEntitlementReader();
    });

final appleSubscriptionRestorerProvider = Provider<AppleSubscriptionRestorer>((
  ref,
) {
  return AppleSubscriptionRestorer(
    reader: ref.watch(appleCurrentEntitlementReaderProvider),
  );
});

final appleRestoreProofSyncProvider = Provider<AppleRestoreProofSync>((ref) {
  return AppleRestoreProofSync(
    api: ref.watch(appleRestoreProofApiProvider),
    bridge: const MethodChannelAppleAppAttestBridge(),
    storage: const SecureAppleAppAttestKeyStorage(),
  );
});

final subscriptionControllerProvider =
    NotifierProvider<SubscriptionController, SubscriptionState>(
      SubscriptionController.new,
    );

final subscriptionRevenueStorageProvider = Provider<SubscriptionRevenueStorage>(
  (ref) {
    return const PreferencesSubscriptionRevenueStorage();
  },
);

final subscriptionEntitlementCacheStorageProvider =
    Provider<SubscriptionEntitlementCacheStorage>((ref) {
      return const SecureSubscriptionEntitlementCacheStorage();
    });

final subscriptionRevenueReporterProvider =
    Provider<SubscriptionRevenueReporter>((ref) {
      return SubscriptionRevenueReporter(
        storage: ref.watch(subscriptionRevenueStorageProvider),
        sink: AnalyticsSubscriptionRevenueSink(ref.watch(analyticsProvider)),
      );
    });

enum SubscriptionResultEvent {
  purchaseSuccess,
  restoreSuccess,
  restoreNotFound,
  restoreFailed,
  externalPremium,
}

enum SubscriptionRestoreSource { subscriptionPage, profile }

AppPremiumState resolvePremiumStateAfterRestore(
  AppPremiumState current,
  AppleRestoreResult? result,
) {
  if (result == null) return current;
  return result.isSuccess ? AppPremiumState.premium : AppPremiumState.free;
}

List<AppleCurrentEntitlement> applyAppleLifecycleCorrections(
  List<AppleCurrentEntitlement> entitlements,
  List<ApplePurchaseChainLifecycle>? lifecycle,
) {
  if (lifecycle == null) return entitlements;
  return entitlements
      .where((entitlement) {
        final payload = decodeStoreKitJwsPayload(
          entitlement.signedTransactionInfo,
        );
        final originalTransactionId = payload?['originalTransactionId'];
        final signedDate = payload?['signedDate'];
        if (originalTransactionId is! String || signedDate is! num) return true;
        final signedAt = DateTime.fromMillisecondsSinceEpoch(
          signedDate.toInt(),
          isUtc: true,
        );
        return !lifecycle.any(
          (item) =>
              item.originalTransactionId == originalTransactionId &&
              item.isExplicitlyInactive &&
              item.stateEffectiveAt != null &&
              !item.stateEffectiveAt!.isBefore(signedAt),
        );
      })
      .toList(growable: false);
}

class SubscriptionState {
  const SubscriptionState({
    this.selectedPlanId = subscriptionYearlyPlanId,
    this.displayPrices = const {},
    this.availablePlanIds = const {},
    this.unavailablePlanIds = const {},
    this.isConfigured = false,
    this.isLoading = false,
    this.isPurchasing = false,
    this.isPurchasePending = false,
    this.isRestoring = false,
    AppPremiumState? premiumState,
    bool isPro = false,
    this.completionCount = 0,
    this.resultEventCount = 0,
    this.resultEvent,
    this.restoreSource,
    this.errorMessage,
  }) : premiumState =
           premiumState ??
           (isPro ? AppPremiumState.premium : AppPremiumState.unknown);

  final String selectedPlanId;
  final Map<String, String> displayPrices;
  final Set<String> availablePlanIds;
  final Set<String> unavailablePlanIds;
  final bool isConfigured;
  final bool isLoading;
  final bool isPurchasing;
  final bool isPurchasePending;
  final bool isRestoring;
  final AppPremiumState premiumState;
  bool get isPro => premiumState == AppPremiumState.premium;
  final int completionCount;
  final int resultEventCount;
  final SubscriptionResultEvent? resultEvent;
  final SubscriptionRestoreSource? restoreSource;
  final String? errorMessage;

  SubscriptionState copyWith({
    String? selectedPlanId,
    Map<String, String>? displayPrices,
    Set<String>? availablePlanIds,
    Set<String>? unavailablePlanIds,
    bool? isConfigured,
    bool? isLoading,
    bool? isPurchasing,
    bool? isPurchasePending,
    bool? isRestoring,
    AppPremiumState? premiumState,
    bool? isPro,
    int? completionCount,
    int? resultEventCount,
    SubscriptionResultEvent? resultEvent,
    SubscriptionRestoreSource? restoreSource,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return SubscriptionState(
      selectedPlanId: selectedPlanId ?? this.selectedPlanId,
      displayPrices: displayPrices ?? this.displayPrices,
      availablePlanIds: availablePlanIds ?? this.availablePlanIds,
      unavailablePlanIds: unavailablePlanIds ?? this.unavailablePlanIds,
      isConfigured: isConfigured ?? this.isConfigured,
      isLoading: isLoading ?? this.isLoading,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      isPurchasePending: isPurchasePending ?? this.isPurchasePending,
      isRestoring: isRestoring ?? this.isRestoring,
      premiumState:
          premiumState ??
          (isPro == null
              ? this.premiumState
              : isPro
              ? AppPremiumState.premium
              : AppPremiumState.free),
      completionCount: completionCount ?? this.completionCount,
      resultEventCount: resultEventCount ?? this.resultEventCount,
      resultEvent: clearResult ? null : resultEvent ?? this.resultEvent,
      restoreSource: clearResult ? null : restoreSource ?? this.restoreSource,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class SubscriptionController extends Notifier<SubscriptionState> {
  SubscriptionClient? _client;
  StreamSubscription<SubscriptionEvent>? _eventSubscription;
  SubscriptionStore? _store;
  var _restoreAttempt = 0;
  var _purchasePresentationActive = false;
  Future<AppPremiumState>? _entitlementRefreshInFlight;
  Future<bool>? _productLoadInFlight;
  var _productLoadCycle = 0;

  @override
  SubscriptionState build() {
    final configuration = ref.watch(appSubscriptionConfigurationProvider);
    ref.listen(authControllerProvider, (_, next) {
      final session = next.session;
      if (session != null) {
        unawaited(ref.read(subscriptionSyncQueueProvider).flush(session));
      }
    });
    final currentSession = ref.read(authControllerProvider).session;
    if (currentSession != null) {
      Future<void>.microtask(
        () => ref.read(subscriptionSyncQueueProvider).flush(currentSession),
      );
    }
    Future<void>.microtask(() async {
      try {
        await ref.read(subscriptionRevenueReporterProvider).flush();
      } on Object catch (error, stackTrace) {
        debugPrint('Unable to flush subscription revenue: $error\n$stackTrace');
      }
    });
    ref.onDispose(() {
      _restoreAttempt++;
      _productLoadCycle++;
      unawaited(_eventSubscription?.cancel());
      unawaited(_client?.dispose());
    });
    if (!configuration.isConfigured) {
      return const SubscriptionState(
        unavailablePlanIds: {
          subscriptionWeeklyPlanId,
          subscriptionYearlyPlanId,
          subscriptionLifetimePlanId,
        },
      );
    }
    Future<void>.microtask(() async {
      try {
        await refreshEntitlement(showFailure: false);
      } on Object catch (error, stackTrace) {
        debugPrint(
          'Unable to refresh subscription entitlement: $error\n$stackTrace',
        );
      }
    });
    Future<void>.microtask(() => _initialize(configuration));
    return const SubscriptionState(isConfigured: true, isLoading: true);
  }

  void selectPlan(String planId) {
    if (state.isLoading ||
        state.isPurchasePending ||
        !state.availablePlanIds.contains(planId)) {
      return;
    }
    state = state.copyWith(selectedPlanId: planId, clearError: true);
  }

  Future<void> refreshProducts({
    required bool Function() isContextActive,
  }) async {
    if (!state.isConfigured ||
        state.isLoading ||
        state.isPurchasing ||
        state.isPurchasePending ||
        state.isRestoring ||
        _client == null ||
        _store == null) {
      return;
    }
    state = state.copyWith(isLoading: true);
    var loaded = false;
    try {
      loaded = await _loadProductsWithRetry(isContextActive: isContextActive);
    } finally {
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, clearError: loaded);
      }
    }
  }

  Future<void> purchase() async {
    if (state.isLoading || state.isPurchasing || state.isPurchasePending) {
      return;
    }
    final client = _client;
    final store = _store;
    if (client == null || store == null) {
      state = state.copyWith(
        errorMessage: 'Subscription products are not configured.',
      );
      return;
    }
    state = state.copyWith(
      isLoading: true,
      isPurchasing: true,
      isPurchasePending: false,
      clearError: true,
      clearResult: true,
    );
    _purchasePresentationActive = true;
    try {
      if (!state.availablePlanIds.contains(state.selectedPlanId)) {
        final loaded = await _loadProductsWithRetry();
        if (!loaded || !state.availablePlanIds.contains(state.selectedPlanId)) {
          state = state.copyWith(
            isLoading: false,
            isPurchasing: false,
            errorMessage:
                'Unable to connect to the App Store. Please try again.',
          );
          _purchasePresentationActive = false;
          return;
        }
        state = state.copyWith(isLoading: true);
      }
      String? applicationUserName;
      final session = ref.read(authControllerProvider).session;
      if (store == SubscriptionStore.appStore && session != null) {
        final productId = ref
            .read(appSubscriptionConfigurationProvider)
            .productIds[state.selectedPlanId];
        if (productId != null) {
          try {
            applicationUserName = await ref
                .read(subscriptionEntitlementApiProvider)
                .createPurchaseChallenge(session, productId: productId);
          } on Exception {
            // Per PRD, an unavailable business API must not block StoreKit.
          }
        }
      }
      await client.purchase(
        planId: state.selectedPlanId,
        store: store,
        applicationUserName: applicationUserName,
      );
    } on TimeoutException {
      _purchasePresentationActive = false;
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        errorMessage: 'Unable to connect to the App Store. Please try again.',
      );
    } on Object {
      _purchasePresentationActive = false;
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        errorMessage:
            'Purchases are unavailable right now. Please try again later.',
      );
    }
  }

  void abandonPurchasePresentation() {
    if (state.isPurchasePending) {
      _purchasePresentationActive = false;
    }
  }

  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) {
    final inFlight = _entitlementRefreshInFlight;
    if (inFlight != null) return inFlight;
    final refresh = _runEntitlementRefresh(showFailure: showFailure);
    _entitlementRefreshInFlight = refresh;
    return refresh;
  }

  Future<AppPremiumState> _runEntitlementRefresh({
    required bool showFailure,
  }) async {
    try {
      return await _refreshEntitlement(
        ref.read(appSubscriptionConfigurationProvider),
        showFailure: showFailure,
      );
    } finally {
      _entitlementRefreshInFlight = null;
    }
  }

  Future<void> restore({
    SubscriptionRestoreSource source =
        SubscriptionRestoreSource.subscriptionPage,
  }) async {
    if (state.isLoading || state.isPurchasePending) return;
    final configuration = ref.read(appSubscriptionConfigurationProvider);
    if (_client == null || _store != SubscriptionStore.appStore) {
      debugPrint(
        'Unable to restore Apple subscription: StoreKit client is not ready '
        '(client=${_client == null ? 'missing' : 'ready'}, store=$_store).',
      );
      state = state.copyWith(
        resultEvent: SubscriptionResultEvent.restoreFailed,
        restoreSource: source,
        resultEventCount: state.resultEventCount + 1,
      );
      return;
    }
    final attempt = ++_restoreAttempt;
    state = state.copyWith(
      isLoading: true,
      isRestoring: true,
      restoreSource: source,
      clearError: true,
      clearResult: true,
    );
    try {
      final result = await ref
          .read(appleSubscriptionRestorerProvider)
          .restore(configuration.configuredProductIds.values.toSet());
      if (attempt != _restoreAttempt) return;
      if (result.isSuccess) {
        final session = ref.read(authControllerProvider).session;
        final evidence = result.signedTransactionInfo;
        if (session != null && evidence != null) {
          unawaited(
            ref
                .read(appleRestoreProofSyncProvider)
                .sync(session, evidence)
                .catchError((Object error, StackTrace stackTrace) {
                  debugPrint(
                    'Unable to synchronize Apple Restore proof: $error\n'
                    '$stackTrace',
                  );
                }),
          );
        }
      }
      final event = result.isSuccess
          ? SubscriptionResultEvent.restoreSuccess
          : SubscriptionResultEvent.restoreNotFound;
      state = state.copyWith(
        isLoading: false,
        isRestoring: false,
        premiumState: resolvePremiumStateAfterRestore(
          state.premiumState,
          result,
        ),
        resultEvent: event,
        restoreSource: source,
        resultEventCount: state.resultEventCount + 1,
      );
      await _cacheRestoreResult(result);
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Unable to restore Apple subscription: $error\n$stackTrace',
      );
      if (attempt != _restoreAttempt) return;
      state = state.copyWith(
        isLoading: false,
        isRestoring: false,
        premiumState: resolvePremiumStateAfterRestore(state.premiumState, null),
        resultEvent: SubscriptionResultEvent.restoreFailed,
        restoreSource: source,
        resultEventCount: state.resultEventCount + 1,
      );
    }
  }

  Future<void> _initialize(AppSubscriptionConfiguration configuration) async {
    final store = configuration.store!;
    final configuredProductIds = configuration.configuredProductIds;
    final config = SubscriptionConfig(
      enabledStores: {store},
      plans: subscriptionPlans
          .where((plan) => configuredProductIds.containsKey(plan.id))
          .map(
            (plan) => SubscriptionPlanConfig(
              id: plan.id,
              entitlementId: 'performance_pro',
              productIds: {store: configuredProductIds[plan.id]!},
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
      final loaded = await _loadProductsWithRetry();
      state = state.copyWith(
        isLoading: false,
        errorMessage: loaded
            ? null
            : 'Unable to connect to the App Store. Please try again.',
        clearError: loaded,
      );
    } on Object {
      state = state.copyWith(
        isLoading: false,
        availablePlanIds: const {},
        unavailablePlanIds: subscriptionPlans.map((plan) => plan.id).toSet(),
        errorMessage: 'Unable to connect to the App Store. Please try again.',
      );
    }
  }

  Future<AppPremiumState> _refreshEntitlement(
    AppSubscriptionConfiguration configuration, {
    bool showFailure = false,
  }) async {
    final storage = ref.read(subscriptionEntitlementCacheStorageProvider);
    final cached = await storage.read();
    final cachedState = cached?.effectiveState(DateTime.now().toUtc());
    if (cachedState != null && ref.mounted) {
      state = state.copyWith(premiumState: cachedState);
    }
    if (configuration.store != SubscriptionStore.appStore ||
        configuration.configuredProductIds.isEmpty) {
      return state.premiumState;
    }
    try {
      final session = ref.read(authControllerProvider).session;
      final lifecycleFuture = session == null
          ? Future<List<ApplePurchaseChainLifecycle>?>.value(null)
          : ref
                .read(appleLifecycleApiProvider)
                .loadCurrentSessionLifecycle(session)
                .timeout(const Duration(seconds: 15))
                .then<List<ApplePurchaseChainLifecycle>?>((value) => value)
                .catchError((Object _) => null);
      final appleEntitlements = await ref
          .read(appleCurrentEntitlementReaderProvider)
          .read(configuration.configuredProductIds.values.toSet())
          .timeout(const Duration(seconds: 15));
      if (!ref.mounted) return state.premiumState;
      final lifecycle = await lifecycleFuture;
      if (!ref.mounted) return state.premiumState;
      final entitlements = applyAppleLifecycleCorrections(
        appleEntitlements,
        lifecycle,
      );
      if (entitlements.isEmpty) {
        final verifiedFree = VerifiedEntitlementCache(
          state: AppPremiumState.free,
          verifiedAt: DateTime.now().toUtc(),
        );
        await storage.write(verifiedFree);
        if (ref.mounted) {
          state = state.copyWith(
            premiumState: AppPremiumState.free,
            clearError: true,
          );
        }
        return AppPremiumState.free;
      }
      final cache = selectBestVerifiedEntitlementCache(
        entitlements,
        lifetimeProductId:
            configuration.configuredProductIds[subscriptionLifetimePlanId],
        verifiedAt: DateTime.now().toUtc(),
      );
      if (cache == null) {
        throw StateError('Current Apple entitlement evidence is malformed.');
      }
      await storage.write(cache);
      if (ref.mounted) {
        state = state.copyWith(
          premiumState: AppPremiumState.premium,
          clearError: true,
        );
      }
      return AppPremiumState.premium;
    } on Object {
      final fallback = cachedState ?? AppPremiumState.unknown;
      if (ref.mounted) {
        state = state.copyWith(
          premiumState: fallback,
          errorMessage: showFailure
              ? 'Unable to verify Premium access. Please try again.'
              : null,
          clearError: !showFailure,
        );
      }
      return fallback;
    }
  }

  Future<void> _cacheRestoreResult(AppleRestoreResult result) async {
    final storage = ref.read(subscriptionEntitlementCacheStorageProvider);
    if (!result.isSuccess) {
      await storage.write(
        VerifiedEntitlementCache(
          state: AppPremiumState.free,
          verifiedAt: DateTime.now().toUtc(),
        ),
      );
      return;
    }
    final evidence = result.signedTransactionInfo!;
    final payload = decodeStoreKitJwsPayload(evidence);
    final productId = payload?['productId'];
    final cache = productId is String
        ? _cacheFromEvidence(productId, evidence)
        : null;
    if (cache != null) await storage.write(cache);
  }

  VerifiedEntitlementCache? _cacheFromEvidence(
    String productId,
    String evidence,
  ) {
    final payload = decodeStoreKitJwsPayload(evidence);
    if (payload == null || payload['productId'] != productId) return null;
    final originalTransactionId = payload['originalTransactionId'];
    final expiresDate = payload['expiresDate'];
    final configuration = ref.read(appSubscriptionConfigurationProvider);
    final lifetimeProductId =
        configuration.configuredProductIds[subscriptionLifetimePlanId];
    return VerifiedEntitlementCache(
      state: AppPremiumState.premium,
      verifiedAt: DateTime.now().toUtc(),
      productId: productId,
      originalTransactionId: originalTransactionId is String
          ? originalTransactionId
          : null,
      expiresAt: expiresDate is num
          ? DateTime.fromMillisecondsSinceEpoch(
              expiresDate.toInt(),
              isUtc: true,
            )
          : null,
      isLifetime: productId == lifetimeProductId,
    );
  }

  Future<bool> _loadProducts(
    int cycle, {
    bool Function()? isContextActive,
  }) async {
    final client = _client;
    final store = _store;
    if (client == null || store == null) return false;
    final catalog = await client.loadProducts();
    if (cycle != _productLoadCycle ||
        !ref.mounted ||
        isContextActive?.call() == false) {
      return false;
    }
    final prices = <String, String>{};
    final available = <String>{};
    for (final product in catalog.products) {
      final plan = client.config.planByProductId(store, product.storeProductId);
      if (plan != null) {
        available.add(plan.id);
        prices[plan.id] = product.displayPrice;
      }
    }
    final unavailable = subscriptionPlans
        .map((plan) => plan.id)
        .where((planId) => !available.contains(planId))
        .toSet();
    final selected = available.contains(state.selectedPlanId)
        ? state.selectedPlanId
        : subscriptionPlans
              .map((plan) => plan.id)
              .firstWhere(
                available.contains,
                orElse: () => state.selectedPlanId,
              );
    state = state.copyWith(
      selectedPlanId: selected,
      displayPrices: prices,
      availablePlanIds: available,
      unavailablePlanIds: unavailable,
    );
    return available.isNotEmpty;
  }

  Future<bool> _loadProductsWithRetry({bool Function()? isContextActive}) {
    final inFlight = _productLoadInFlight;
    if (inFlight != null) return inFlight;
    final cycle = ++_productLoadCycle;
    late final Future<bool> load;
    load =
        loadSubscriptionProductsWithRetry(
          () => _loadProducts(cycle, isContextActive: isContextActive),
          shouldContinue: isContextActive,
        ).whenComplete(() {
          if (cycle == _productLoadCycle) _productLoadCycle++;
          if (identical(_productLoadInFlight, load)) {
            _productLoadInFlight = null;
          }
        });
    _productLoadInFlight = load;
    return load;
  }

  void _handleEvent(SubscriptionEvent event) {
    final entitlement = event.entitlement;
    if (entitlement?.isActive == true) {
      final resultEvent = _purchasePresentationActive
          ? SubscriptionResultEvent.purchaseSuccess
          : SubscriptionResultEvent.externalPremium;
      _purchasePresentationActive = false;
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        isPurchasePending: false,
        premiumState: AppPremiumState.premium,
        completionCount: state.completionCount + 1,
        resultEvent: resultEvent,
        resultEventCount: state.resultEventCount + 1,
        clearError: true,
      );
      final purchase = event.purchase;
      if (purchase != null) {
        final cache = _cacheFromEvidence(
          purchase.storeProductId,
          purchase.verificationData,
        );
        if (cache != null) {
          unawaited(
            ref.read(subscriptionEntitlementCacheStorageProvider).write(cache),
          );
        }
      }
      if (event.purchase?.status == SubscriptionPurchaseStatus.purchased &&
          event.failure == null) {
        unawaited(
          ref
              .read(subscriptionRevenueReporterProvider)
              .enqueueVerifiedPurchase(event)
              .catchError((Object error, StackTrace stackTrace) {
                debugPrint(
                  'Unable to report subscription revenue: $error\n$stackTrace',
                );
              }),
        );
      }
      return;
    }
    if (event.failure != null) {
      _purchasePresentationActive = false;
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        isPurchasePending: false,
        errorMessage: 'Something went wrong. Please try again.',
      );
      return;
    }
    if (event.purchase?.status == SubscriptionPurchaseStatus.pending) {
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        isPurchasePending: true,
        errorMessage:
            'Purchase pending. We will unlock Premium once Apple confirms it.',
      );
      return;
    }
    if (event.purchase?.status == SubscriptionPurchaseStatus.canceled) {
      _purchasePresentationActive = false;
      state = state.copyWith(
        isLoading: false,
        isPurchasing: false,
        isPurchasePending: false,
        clearError: true,
      );
    }
  }
}

Future<bool> loadSubscriptionProductsWithRetry(
  Future<bool> Function() load, {
  bool Function()? shouldContinue,
  Duration deadline = const Duration(seconds: 15),
  List<Duration> retryDelays = const [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
  ],
}) async {
  final elapsed = Stopwatch()..start();
  for (var attempt = 0; attempt <= retryDelays.length; attempt++) {
    if (shouldContinue?.call() == false) return false;
    if (attempt > 0) {
      final delay = retryDelays[attempt - 1];
      if (elapsed.elapsed + delay >= deadline) return false;
      await Future<void>.delayed(delay);
      if (shouldContinue?.call() == false) return false;
    }
    final remaining = deadline - elapsed.elapsed;
    if (remaining <= Duration.zero) return false;
    try {
      if (await load().timeout(remaining)) return true;
    } on TimeoutException {
      return false;
    } on Object {
      // A transient StoreKit failure may be retried within the same deadline.
    }
  }
  return false;
}

VerifiedEntitlementCache? selectBestVerifiedEntitlementCache(
  Iterable<AppleCurrentEntitlement> entitlements, {
  required String? lifetimeProductId,
  required DateTime verifiedAt,
}) {
  VerifiedEntitlementCache? best;
  for (final entitlement in entitlements) {
    final payload = decodeStoreKitJwsPayload(entitlement.signedTransactionInfo);
    if (payload == null || payload['productId'] != entitlement.productId) {
      continue;
    }
    final originalTransactionId = payload['originalTransactionId'];
    final expiresDate = payload['expiresDate'];
    final candidate = VerifiedEntitlementCache(
      state: AppPremiumState.premium,
      verifiedAt: verifiedAt,
      productId: entitlement.productId,
      originalTransactionId: originalTransactionId is String
          ? originalTransactionId
          : null,
      expiresAt: expiresDate is num
          ? DateTime.fromMillisecondsSinceEpoch(
              expiresDate.toInt(),
              isUtc: true,
            )
          : null,
      isLifetime: entitlement.productId == lifetimeProductId,
    );
    if (best == null ||
        candidate.isLifetime && !best.isLifetime ||
        !candidate.isLifetime &&
            !best.isLifetime &&
            (candidate.expiresAt?.isAfter(
                  best.expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                ) ??
                false)) {
      best = candidate;
    }
  }
  return best;
}

class StoreKit2SubscriptionReceiptVerifier
    implements SubscriptionReceiptVerifier {
  const StoreKit2SubscriptionReceiptVerifier({
    required AuthSession? Function() session,
    required SubscriptionSyncQueue syncQueue,
  }) : _session = session,
       _syncQueue = syncQueue;

  final AuthSession? Function() _session;
  final SubscriptionSyncQueue _syncQueue;

  @override
  Future<SubscriptionEntitlement> verify(
    SubscriptionVerificationRequest request,
  ) async {
    if (request.purchase.store != SubscriptionStore.appStore ||
        request.purchase.storeData is! SK2PurchaseDetails ||
        request.purchase.verificationData.isEmpty) {
      throw StateError(
        'The Apple transaction is not StoreKit 2 verified data.',
      );
    }

    if (request.purchase.status == SubscriptionPurchaseStatus.purchased) {
      final appAccountToken = request.purchase.applicationUserName;
      final session = _session();
      if (session != null &&
          appAccountToken != null &&
          appAccountToken.isNotEmpty) {
        try {
          await _syncQueue.enqueueAndFlush(
            session,
            signedTransactionInfo: request.purchase.verificationData,
          );
        } on Object catch (error, stackTrace) {
          debugPrint(
            'Unable to persist Apple entitlement sync evidence: $error\n'
            '$stackTrace',
          );
        }
      }
    }

    return SubscriptionEntitlement(
      planId: request.plan.id,
      entitlementId: request.plan.entitlementId,
      status: SubscriptionEntitlementStatus.active,
    );
  }
}

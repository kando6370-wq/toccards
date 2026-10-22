import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:subscription_core/subscription_core.dart';

import 'subscription_display_config.dart';
import 'subscription_store_product.dart';

typedef DisplayConfigLoader =
    Future<SubscriptionDisplayConfig?> Function(SubscriptionPageType type);
typedef DisplayProductLoader =
    Future<List<SubscriptionStoreProduct>> Function(Set<String> ids);
typedef TrialEligibilityLoader = Future<TrialEligibility> Function(String id);

class SubscriptionDisplayCard {
  const SubscriptionDisplayCard({
    required this.sku,
    required this.product,
    required this.copy,
    required this.cta,
    required this.billingNote,
    required this.subtitle,
    required this.badge,
    required this.priceNote,
    required this.weeklyReference,
    required this.weeklyOnly,
    required this.hidePrice,
  });
  final SubscriptionDisplaySku sku;
  final SubscriptionStoreProduct product;
  final SubscriptionCopy copy;
  final String cta, billingNote, subtitle, badge, priceNote;
  final bool weeklyReference, weeklyOnly, hidePrice;
}

/// One instance per page/modal. It never owns or disposes the transaction listener.
class SubscriptionDisplayController extends ChangeNotifier {
  SubscriptionDisplayController({
    required this.fallback,
    required DisplayConfigLoader loadConfig,
    required DisplayProductLoader loadProducts,
    required TrialEligibilityLoader loadEligibility,
    this.loadBudget = const Duration(seconds: 15),
    this.configBudget = const Duration(seconds: 3),
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
      Duration(seconds: 8),
    ],
  }) : _loadConfig = loadConfig,
       _loadProducts = loadProducts,
       _loadEligibility = loadEligibility;
  final SubscriptionDisplayConfig fallback;
  final DisplayConfigLoader _loadConfig;
  final DisplayProductLoader _loadProducts;
  final TrialEligibilityLoader _loadEligibility;
  final Duration loadBudget, configBudget;
  final List<Duration> retryDelays;
  final Stopwatch _entered = Stopwatch()..start();
  SubscriptionDisplayConfig? config;
  Map<String, SubscriptionStoreProduct> products = const {};
  String? selectedId, errorMessage;
  String? _activeTrialSkuId;
  bool isLoading = true,
      isVerifying = false,
      trialOn = false,
      trialInvalid = false;
  bool _disposed = false, _usedFallback = false, _hasShownProducts = false;
  int _cycle = 0;
  Timer? _closeTimer;

  bool get closeAvailable =>
      config != null && _entered.elapsed >= config!.closeDelay;
  bool get usesRemoteConfiguration => config != null && !_usedFallback;
  List<SubscriptionDisplaySku> get availableSkus =>
      config?.skus
          .where((sku) => products[sku.productId]?.type == sku.type)
          .toList(growable: false) ??
      const [];
  SubscriptionDisplaySku? get selectedSku {
    for (final sku in config?.skus ?? <SubscriptionDisplaySku>[]) {
      if (sku.productId == selectedId) return sku;
    }
    return null;
  }

  bool _validTrial(SubscriptionDisplaySku sku) {
    final source = products[sku.productId];
    final target = products[sku.trial?.productId];
    return config?.trialEnabled == true &&
        source != null &&
        target != null &&
        source.matchesTrial(target);
  }

  bool get showTrialSwitch => trialOn || availableSkus.any(_validTrial);
  bool get canPurchase =>
      !_disposed &&
      !isLoading &&
      !isVerifying &&
      !trialInvalid &&
      selectedCard != null;
  SubscriptionDisplayCard? get selectedCard =>
      selectedSku == null ? null : card(selectedSku!);

  SubscriptionDisplayCard? card(SubscriptionDisplaySku sku) {
    final linked = trialOn && _activeTrialSkuId == sku.productId;
    final product = products[linked ? sku.trial?.productId : sku.productId];
    if (product == null || (!linked && product.type != sku.type)) return null;
    final copy = product.useNeutralCopy
        ? const SubscriptionCopy(name: 'Premium')
        : linked
        ? sku.trial!.copy
        : sku.copy;
    final weeklyReference = linked
        ? sku.trial!.weeklyReference ?? sku.weeklyReference
        : sku.weeklyReference;
    String expand(String value) =>
        value.replaceAll('{price}', product.product.displayPrice);
    final cta = product.useNeutralCopy
        ? 'SUBSCRIBE'
        : copy.cta.trim().isNotEmpty
        ? copy.cta
        : config!.cta.trim().isNotEmpty
        ? config!.cta
        : 'SUBSCRIBE';
    return SubscriptionDisplayCard(
      sku: sku,
      product: product,
      copy: copy,
      cta: cta,
      subtitle: expand(copy.subtitle),
      badge: expand(copy.badge),
      priceNote: expand(copy.priceNote),
      weeklyReference: weeklyReference,
      weeklyOnly:
          weeklyReference &&
          (linked ? sku.trial!.weeklyOnly ?? sku.weeklyOnly : sku.weeklyOnly),
      hidePrice: linked ? sku.trial!.hidePrice ?? sku.hidePrice : sku.hidePrice,
      billingNote: copy.autoBillingNote ? '' : expand(copy.billingNote),
    );
  }

  Future<void> load() async {
    if (_disposed || isVerifying) return;
    final cycle = ++_cycle;
    final clock = Stopwatch()..start();
    Duration remaining() => loadBudget - clock.elapsed;
    bool active() => !_disposed && cycle == _cycle;
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      if (config == null) {
        SubscriptionDisplayConfig? remote;
        try {
          remote = await _loadConfig(
            fallback.pageType,
          ).timeout(configBudget < remaining() ? configBudget : remaining());
        } on Object {
          /* Missing/invalid/failed configuration locks this page to fallback. */
        }
        if (!active()) return;
        _usedFallback = remote == null;
        _useConfig(remote ?? fallback);
      }
      for (
        var attempt = 0;
        attempt <= retryDelays.length && remaining() > Duration.zero;
        attempt++
      ) {
        if (attempt > 0) {
          final delay = retryDelays[attempt - 1];
          if (delay >= remaining()) break;
          await Future<void>.delayed(delay);
          if (!active()) return;
        }
        List<SubscriptionStoreProduct> loaded = const [];
        try {
          loaded = await _loadProducts(config!.productIds).timeout(remaining());
        } on Object {
          /* Retry only within the original total deadline. */
        }
        if (!active()) return;
        final next = {
          for (final product in loaded)
            if (config!.productIds.contains(product.id)) product.id: product,
        };
        if (config!.skus.any((sku) => next[sku.productId]?.type == sku.type)) {
          products = Map.unmodifiable(next);
          _hasShownProducts = true;
          final available = availableSkus;
          selectedId ??= available
              .firstWhere((sku) => sku.isDefault, orElse: () => available.first)
              .productId;
          isLoading = false;
          _notify();
          // Account-level StoreKit eligibility is intentionally disabled for
          // the current Apple-configured trial policy. Keep the old lookup
          // available for a future re-enable without delaying this render:
          // for (final product in loaded.where((p) => p.hasFreeTrial)) {
          //   if (remaining() > Duration.zero) {
          //     unawaited(_qualify(product, cycle, remaining()));
          //   }
          // }
          return;
        }
        if (!_usedFallback &&
            !_hasShownProducts &&
            remaining() > Duration.zero) {
          _usedFallback = true;
          _useConfig(fallback);
          // The one fallback attempt consumes the same budget, without an extra delay.
          try {
            loaded = await _loadProducts(
              fallback.productIds,
            ).timeout(remaining());
            if (!active()) return;
            products = Map.unmodifiable({
              for (final p in loaded)
                if (fallback.productIds.contains(p.id)) p.id: p,
            });
            final available = availableSkus;
            if (available.isNotEmpty) {
              _hasShownProducts = true;
              selectedId = available
                  .firstWhere((s) => s.isDefault, orElse: () => available.first)
                  .productId;
              isLoading = false;
              _notify();
              // Account-level StoreKit eligibility is intentionally disabled;
              // retain the previous asynchronous lookup as commented code.
              // for (final p in loaded.where((p) => p.hasFreeTrial)) {
              //   if (remaining() > Duration.zero) {
              //     unawaited(_qualify(p, cycle, remaining()));
              //   }
              // }
              return;
            }
          } on Object {
            /* Continue bounded fallback retries. */
          }
        }
      }
      if (active()) {
        products = const {};
        errorMessage =
            'Could not load plans from the App Store. Check your connection.';
      }
    } finally {
      if (active()) {
        isLoading = false;
        _notify();
      }
    }
  }

  void _useConfig(SubscriptionDisplayConfig value) {
    config = value;
    _closeTimer?.cancel();
    final remaining = value.closeDelay - _entered.elapsed;
    if (remaining > Duration.zero) _closeTimer = Timer(remaining, _notify);
    _notify();
  }

  // Retained for a future policy that needs account-level eligibility again.
  // ignore: unused_element
  Future<void> _qualify(
    SubscriptionStoreProduct product,
    int cycle,
    Duration budget,
  ) async {
    var eligibility = TrialEligibility.unknown;
    try {
      eligibility = await _loadEligibility(product.id).timeout(budget);
    } on Object {
      /* Unknown is not ineligible. */
    }
    if (_disposed ||
        cycle != _cycle ||
        isVerifying ||
        !identical(products[product.id], product)) {
      return;
    }
    products = Map.unmodifiable({
      ...products,
      product.id: product.withEligibility(eligibility),
    });
    _notify();
  }

  void select(String id) {
    if (isLoading ||
        isVerifying ||
        selectedId == id ||
        !availableSkus.any((s) => s.productId == id)) {
      return;
    }
    selectedId = id;
    trialInvalid = false;
    errorMessage = null;
    _notify();
  }

  void toggleTrial(bool value) {
    if (isLoading || isVerifying) return;
    if (!value) {
      trialOn = false;
      _activeTrialSkuId = null;
      trialInvalid = false;
      errorMessage = null;
      _notify();
      return;
    }
    final candidates = availableSkus.where(_validTrial).toList(growable: false);
    if (candidates.isEmpty) {
      errorMessage = 'This trial is currently unavailable.';
      _notify();
      return;
    }
    final candidate = candidates.firstWhere(
      (s) => s.productId == selectedId,
      orElse: () => candidates.first,
    );
    selectedId = candidate.productId;
    _activeTrialSkuId = candidate.productId;
    trialOn = true;
    trialInvalid = false;
    errorMessage = null;
    _notify();
  }

  /// Called immediately before StoreKit purchase, after any account challenge.
  /// Changed terms always require another explicit user action.
  Future<SubscriptionProduct?> confirmPurchase() async {
    final previous = selectedCard;
    if (!canPurchase || previous == null) return null;
    final purchasingLinkedTrial =
        trialOn &&
        _activeTrialSkuId == previous.sku.productId &&
        previous.sku.trial?.productId == previous.product.id;
    isVerifying = true;
    final cycle = ++_cycle;
    _notify();
    try {
      // final clock = Stopwatch()..start();
      final ids = {previous.product.id, previous.sku.productId};
      final loaded = await _loadProducts(ids).timeout(loadBudget);
      final next = <String, SubscriptionStoreProduct>{};
      for (final product in loaded.where((p) => ids.contains(p.id))) {
        // Account-level eligibility recheck is intentionally disabled for the
        // current Apple-configured trial policy. The previous code is kept
        // commented so the policy can be restored without reconstructing it:
        // var value = product;
        // if (product.hasFreeTrial) {
        //   final remaining = loadBudget - clock.elapsed;
        //   var eligibility = TrialEligibility.unknown;
        //   if (remaining > Duration.zero) {
        //     try {
        //       eligibility = await _loadEligibility(
        //         product.id,
        //       ).timeout(remaining);
        //     } on Object {
        //       /* Keep unknown. */
        //     }
        //   }
        //   value = product.withEligibility(eligibility);
        // }
        next[product.id] = product;
      }
      if (_disposed || cycle != _cycle) return null;
      products = Map.unmodifiable(
        {...products}
          ..removeWhere((id, _) => ids.contains(id))
          ..addAll(next),
      );
      final current = selectedCard;
      if (purchasingLinkedTrial && !_validTrial(previous.sku)) {
        trialInvalid = true;
      }
      if (current == null ||
          trialInvalid ||
          !previous.product.sameTerms(current.product)) {
        errorMessage = trialInvalid
            ? 'This trial is no longer available. Turn off the trial or choose another plan.'
            : 'Purchase conditions changed. Review the current price and tap again.';
        return null;
      }
      return current.product.product;
    } on Object {
      if (!_disposed) {
        errorMessage =
            'Could not verify current purchase conditions. Please retry.';
      }
      return null;
    } finally {
      if (!_disposed && cycle == _cycle) {
        isVerifying = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cycle++;
    _closeTimer?.cancel();
    super.dispose();
  }
}

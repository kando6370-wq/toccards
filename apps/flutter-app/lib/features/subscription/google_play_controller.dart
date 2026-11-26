import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../auth/android_play_integrity.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import '../auth/auth_session_interceptor.dart';
import '../../shared/api/app_http_transport.dart';
import '../auth/auth_models.dart';
import '../../shared/api/api_environment.dart';
import '../../shared/attribution/app_attribution.dart';
import 'subscription_display_config.dart';
import 'subscription_revenue_reporter.dart';
import 'subscription_singular_events.dart';

class PlayPolicy {
  const PlayPolicy({
    this.metered = false,
    this.premium = false,
    this.sales = false,
    this.account,
    this.package,
    this.product,
    this.expires,
    this.renews,
  });
  final bool metered, premium, sales;
  final String? account, package, product, expires;
  final bool? renews;

  factory PlayPolicy.fromJson(Map<String, dynamic> data) => PlayPolicy(
    metered: data['access_policy'] == 'metered',
    premium: data['premium'] == true,
    sales: data['sales_available'] == true,
    account: data['account_ref'] as String?,
    package: data['package_name'] as String?,
    product: data['product_id'] as String?,
    expires: data['expires_at'] as String?,
    renews: data['auto_renew'] as bool?,
  );
}

extension CurrentPlayPolicy on AsyncValue<PlayPolicy> {
  // Riverpod retains the previous value while it resolves the next signed-in account.
  PlayPolicy? get current => isLoading || hasError ? null : asData?.value;
}

typedef PlayCatalog = ({String title, List<PlayChoice> choices});

class PlayChoice {
  PlayChoice(this.product, this.offer, this.label, this.isDefault);
  final GooglePlayProductDetails product;
  final SubscriptionOfferDetailsWrapper offer;
  final String label;
  final bool isDefault;
  String get key => '${product.id}/${offer.basePlanId}/${offer.offerId ?? ''}';
  String get terms => offer.pricingPhases
      .map((p) {
        final period = playPeriod(p.billingPeriod);
        if (p.recurrenceMode == RecurrenceMode.infiniteRecurring) {
          return '${p.formattedPrice} every $period until canceled';
        }
        if (p.priceAmountMicros == 0 && p.billingCycleCount == 1) {
          return 'Free for $period';
        }
        return '${p.formattedPrice} every $period for ${p.billingCycleCount} billing cycles';
      })
      .join(', then ');
  String get priceIdentity => offer.pricingPhases
      .map(
        (p) =>
            '${p.priceCurrencyCode}/${p.priceAmountMicros}/${p.billingPeriod}/${p.billingCycleCount}/${p.recurrenceMode}/${p.formattedPrice}',
      )
      .join('|');
}

String playPeriod(String iso) {
  final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
  if (m == null) return iso;
  final unit = const {
    'D': 'day',
    'W': 'week',
    'M': 'month',
    'Y': 'year',
  }[m[2]]!;
  return m[1] == '1' ? '1 $unit' : '${m[1]} ${unit}s';
}

// Purchase tokens and account bindings stay out of the in-app network inspector.
final playDioProvider = Provider<Dio>((ref) {
  final client = createAuthDio(transport: ref.watch(appHttpTransportProvider));
  client.interceptors.add(
    AuthSessionInterceptor(
      dio: client,
      storage: ref.watch(authStorageProvider),
    ),
  );
  ref.onDispose(client.close);
  return client;
});

final playBillingProvider = Provider<InAppPurchasePlatform>((ref) {
  InAppPurchaseAndroidPlatform.registerPlatform();
  return InAppPurchasePlatform.instance;
});
final playOwnedPurchasesProvider =
    Provider<Future<List<PurchaseDetails>> Function()>((ref) {
      ref.watch(playBillingProvider);
      return () async {
        final addition =
            InAppPurchasePlatformAddition.instance
                as InAppPurchaseAndroidPlatformAddition;
        final owned = await addition.queryPastPurchases();
        if (owned.error != null) throw StateError('Google Play unavailable');
        return owned.pastPurchases;
      };
    });

final playSingularRevenueProvider = Provider<SubscriptionRevenueReporter>((
  ref,
) {
  final environment = AppConfig.environment;
  return SubscriptionRevenueReporter(
    storage: PreferencesSubscriptionRevenueStorage(
      keyPrefix: 'subscription.google_play.singular.${environment.name}',
    ),
    sink: SingularSubscriptionRevenueSink(
      ref.watch(appAttributionEventReporterProvider),
      environment,
    ),
  );
});

final playPolicyProvider = AsyncNotifierProvider<PlayController, PlayPolicy>(
  PlayController.new,
);

// Only display configuration is shared between entry points. Prices and offer
// eligibility still come from Play, including the final check before purchase.
final playDisplayConfigProvider =
    FutureProvider.family<Map<String, dynamic>?, SubscriptionPageType>((
      ref,
      placement,
    ) async {
      final policy = await ref.watch(playPolicyProvider.future);
      if (!ref.mounted || !policy.metered || !policy.sales || policy.premium) {
        return null;
      }
      return ref.read(playPolicyProvider.notifier)._displayConfig(placement);
    }, retry: (_, _) => null);

final playCatalogProvider = FutureProvider.autoDispose
    .family<PlayCatalog, SubscriptionPageType>((ref, placement) async {
      final play = ref.watch(playPolicyProvider.notifier);
      final config = await ref.watch(
        playDisplayConfigProvider(placement).future,
      );
      if (!ref.mounted) return (title: 'Premium', choices: <PlayChoice>[]);
      return play._choicesForConfig(config);
    }, retry: (_, _) => null);

class PlayController extends AsyncNotifier<PlayPolicy> {
  AuthSession? _session;
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  final _inFlight = <String, Future<String>>{};
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;
  int _generation = 0;
  String? _boundSession;
  Timer? _expiry;
  int? _reportingGeneration;
  @override
  Future<PlayPolicy> build() async {
    final session = ref.watch(authControllerProvider.select((a) => a.session));
    final generation = ++_generation;
    _session = session;
    _inFlight.clear();
    _boundSession = null;
    ref.onDispose(() {
      _generation++;
      _expiry?.cancel();
      unawaited(_purchases?.cancel());
      _purchases = null;
    });
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        session?.platform != AppPlatform.android) {
      return const PlayPolicy();
    }
    final policy = await _readPolicy(session!, generation, rebind: true);
    if (generation == _generation && session.isUser && policy.package != null) {
      _purchases = ref
          .read(playBillingProvider)
          .purchaseStream
          .listen(
            (items) async {
              try {
                final result = await _process(session, items, generation);
                if (result != null && generation == _generation) {
                  _events.add(result);
                }
              } catch (_) {
                if (generation == _generation) {
                  _events.add(
                    'Purchase is syncing. You can retry from Profile.',
                  );
                }
              }
            },
            onError: (Object e) {
              if (generation == _generation) {
                _events.add('Google Play is unavailable. Please retry.');
              }
            },
          );
      unawaited(restore(silent: true));
    }
    return policy;
  }

  Future<Map<String, dynamic>> _call(
    AuthSession session,
    String method,
    String path, {
    Map<String, Object?>? body,
    String? requestId,
  }) async {
    final result = await ref
        .read(playDioProvider)
        .request<Map<String, dynamic>>(
          path,
          data: body,
          options: Options(
            method: method,
            validateStatus: (code) =>
                code == 401 || (code != null && code >= 200 && code < 300),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              if (requestId != null) 'Idempotency-Key': requestId,
            },
          ),
        );
    if (result.statusCode == 401) {
      throw DioException.badResponse(
        statusCode: 401,
        requestOptions: result.requestOptions,
        response: result,
      );
    }
    if (result.data?['success'] != true) {
      throw const FormatException('Invalid Google Play response');
    }
    return (result.data?['data'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  Future<PlayPolicy> _readPolicy(
    AuthSession session,
    int generation, {
    bool rebind = false,
  }) async {
    var data = await _call(session, 'GET', '/entitlements/google/play');
    final binding = data['installation_binding'];
    if (rebind &&
        generation == _generation &&
        binding is String &&
        _boundSession != binding) {
      try {
        final local = await PackageInfo.fromPlatform();
        final installedBuild = int.tryParse(local.buildNumber);
        if (installedBuild != null &&
            installedBuild != data['verified_build']) {
          final device = await ref
              .read(authStorageProvider)
              .readOrCreateDeviceId();
          final proof = await const MethodChannelAndroidPlayIntegrity()
              .boundEvidence(deviceId: device, sessionId: binding);
          if (proof?.token != null && generation == _generation) {
            await _call(
              session,
              'POST',
              '/entitlements/google/installation',
              body: {
                'device_id': device,
                'request_nonce': proof!.requestNonce,
                'integrity_token': proof.token,
              },
            );
            data = await _call(session, 'GET', '/entitlements/google/play');
          }
        }
        if (generation == _generation &&
            installedBuild != null &&
            installedBuild == data['verified_build']) {
          _boundSession = binding;
        }
      } on Exception {
        /* Keep the server's last verified policy and retry on resume. */
      }
    }
    final policy = PlayPolicy.fromJson(data);
    if (generation == _generation) {
      if (session.isUser && data['singular_delivery'] == true) {
        unawaited(_reportFirstCharge(session, generation));
      }
      _expiry?.cancel();
      final expiry = DateTime.tryParse(policy.expires ?? '');
      if (policy.premium && expiry != null) {
        _expiry = Timer(
          expiry.difference(DateTime.now()).isNegative
              ? Duration.zero
              : expiry.difference(DateTime.now()),
          () {
            if (generation == _generation) {
              state = AsyncData(
                PlayPolicy(metered: policy.metered, package: policy.package),
              );
              unawaited(refresh());
            }
          },
        );
      }
    }
    return policy;
  }

  Future<void> _reportFirstCharge(AuthSession session, int generation) async {
    if (_reportingGeneration == generation) return;
    _reportingGeneration = generation;
    try {
      final device = await ref.read(authStorageProvider).readOrCreateDeviceId();
      if (generation != _generation) return;
      const path = '/entitlements/google/attribution';
      final result = await _call(
        session,
        'POST',
        path,
        body: {'installation_id': device},
      );
      final data = result['receipt'];
      if (generation != _generation || data is! Map) return;
      final order = data['order_id'];
      final scope = data['scope'];
      final event = data['event_name'];
      final amount = int.tryParse('${data['amount_micros']}');
      if (order is! String ||
          scope is! String ||
          event is! String ||
          amount == null ||
          amount <= 0) {
        return;
      }
      final record = SubscriptionRevenueRecord.fromJson({
        'transaction_id': '$scope/$order',
        'product_id': data['product_id'],
        'plan_type': 'google_play',
        'value': amount / 1000000,
        'currency': data['currency'],
        'singular_event_name': event,
      });
      if (record == null) return;
      await ref.read(playSingularRevenueProvider).enqueueVerifiedRecord(record);
      if (generation == _generation) {
        await _call(
          session,
          'POST',
          path,
          body: {'installation_id': device, 'handed_off_order': order},
        );
      }
    } catch (_) {
      // The same installation reclaims the receipt on resume, including an interrupted acknowledgement.
      debugPrint('Google Play attribution handoff pending');
    } finally {
      if (_reportingGeneration == generation) _reportingGeneration = null;
    }
  }

  Future<void> refresh() async {
    final session = _session, generation = _generation;
    if (session?.platform != AppPlatform.android) return;
    try {
      final p = await _readPolicy(session!, generation, rebind: true);
      if (generation == _generation) state = AsyncData(p);
    } on Exception {
      if (generation == _generation && !state.hasValue) rethrow;
    }
  }

  Future<Map<String, dynamic>?> _displayConfig(
    SubscriptionPageType placement,
  ) async {
    final data = await _call(
      _session!,
      'GET',
      '/google-play/catalog?placement=${placement.name}',
    );
    if (data['status'] == 'unconfigured' ||
        data['status'] == 'not_applicable') {
      return null;
    }
    final config = data['config'];
    if (data['status'] != 'configured' ||
        config is! Map<String, dynamic> ||
        config['title'] is! String ||
        config['plans'] is! List ||
        (config['plans'] as List).isEmpty) {
      throw const FormatException('Invalid Google Play display configuration');
    }
    return config;
  }

  Future<PlayCatalog> choices(SubscriptionPageType placement) async =>
      _choicesForConfig(await _displayConfig(placement));

  Future<PlayCatalog> _choicesForConfig(Map<String, dynamic>? config) async {
    if (config == null) {
      return (title: 'Premium', choices: <PlayChoice>[]);
    }
    final plans = (config['plans'] as List).whereType<Map>().toList();
    final store = await ref
        .read(playBillingProvider)
        .queryProductDetails(
          plans.map((p) => p['product_id'] as String).toSet(),
        );
    if (store.error != null) {
      throw StateError('Google Play catalog unavailable');
    }
    final choices = <PlayChoice>[];
    for (final plan in plans) {
      for (final product
          in store.productDetails.whereType<GooglePlayProductDetails>()) {
        final i = product.subscriptionIndex,
            offers = product.productDetails.subscriptionOfferDetails;
        if (i == null || offers == null || i >= offers.length) continue;
        final offer = offers[i];
        if (product.id == plan['product_id'] &&
            offer.basePlanId == plan['base_plan_id'] &&
            (offer.offerId ?? '') == plan['offer_id'] &&
            offer.pricingPhases.isNotEmpty &&
            offer.installmentPlanDetails == null) {
          choices.add(
            PlayChoice(
              product,
              offer,
              plan['label'] as String,
              plan['is_default'] == true,
            ),
          );
        }
      }
    }
    return (title: config['title'] as String, choices: choices);
  }

  Future<bool> buy(SubscriptionPageType placement, PlayChoice selected) async {
    final generation = _generation, session = _session!;
    final policy = await _readPolicy(session, generation);
    if (generation != _generation || policy.account == null || !policy.sales) {
      return false;
    }
    final catalog = await choices(placement);
    final fresh = catalog.choices
        .where(
          (c) =>
              c.key == selected.key &&
              c.priceIdentity == selected.priceIdentity,
        )
        .firstOrNull;
    if (fresh == null || generation != _generation) return false;
    return ref
        .read(playBillingProvider)
        .buyNonConsumable(
          purchaseParam: GooglePlayPurchaseParam(
            productDetails: fresh.product,
            offerToken: fresh.offer.offerIdToken,
            applicationUserName: policy.account,
          ),
        );
  }

  Future<String?> _process(
    AuthSession session,
    List<PurchaseDetails> items,
    int generation,
  ) async {
    String? status;
    for (final item in items) {
      if (generation != _generation) return null;
      if (item.status == PurchaseStatus.pending) {
        status = 'Payment pending';
        continue;
      }
      if (item.status == PurchaseStatus.canceled) {
        status = 'Purchase canceled';
        continue;
      }
      if (item.status == PurchaseStatus.error) {
        status = 'Purchase could not be completed';
        continue;
      }
      final token = item.verificationData.serverVerificationData;
      if (token.isEmpty || item.verificationData.source != 'google_play') {
        continue;
      }
      status = await (_inFlight[token] ??= _verify(session, token, generation)
          .whenComplete(() {
            if (generation == _generation) _inFlight.remove(token);
          }));
    }
    return status;
  }

  Future<String> _verify(
    AuthSession session,
    String token,
    int generation,
  ) async {
    final data = await _call(
      session,
      'POST',
      '/entitlements/google/verify',
      body: {'purchase_token': token},
      requestId: const Uuid().v4(),
    );
    if (generation == _generation) await refresh();
    return data['premium'] == true
        ? 'Premium is active'
        : data['state'] == 'PENDING'
        ? 'Payment pending'
        : 'Purchase synced';
  }

  Future<String> restore({bool silent = false}) async {
    final session = _session, generation = _generation;
    if (session == null || !session.isUser) {
      return 'Sign in to your Android account to restore purchases';
    }
    try {
      final owned = await ref.read(playOwnedPurchasesProvider)();
      return await _process(session, owned, generation) ??
          'No subscription found. Check your Play and app accounts.';
    } catch (e) {
      if (silent) return 'Sync pending';
      if (e is DioException && e.response?.statusCode == 403) {
        return 'This purchase cannot be restored to this account. Contact support.';
      }
      return 'Unable to sync with Google Play. Please retry.';
    }
  }
}

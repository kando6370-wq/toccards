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
  client.interceptors.add(AuthSessionInterceptor(dio: client, storage: ref.watch(authStorageProvider)));
  ref.onDispose(client.close);
  return client;
});

final playBillingProvider = Provider<InAppPurchasePlatform>((ref) {
  InAppPurchaseAndroidPlatform.registerPlatform();
  return InAppPurchasePlatform.instance;
});
final playPolicyProvider = AsyncNotifierProvider<PlayController, PlayPolicy>(
  PlayController.new,
);

class PlayController extends AsyncNotifier<PlayPolicy> {
  AuthSession? _session;
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  final _inFlight = <String, Future<String>>{};
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;
  int _generation = 0;
  String? _boundSession;
  Timer? _expiry;
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
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              if (requestId != null) 'Idempotency-Key': requestId,
            },
          ),
        );
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
        if (int.tryParse(local.buildNumber) != data['verified_build']) {
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
        _boundSession = binding;
      } on Exception {
        /* Keep the server's last verified policy and retry on resume. */
      }
    }
    final policy = PlayPolicy.fromJson(data);
    if (generation == _generation) {
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

  Future<({String title, List<PlayChoice> choices})> choices(
    String placement,
  ) async {
    final session = _session!;
    final data = await _call(
      session,
      'GET',
      '/google-play/catalog?placement=$placement',
    );
    final config = data['config'];
    if (config is! Map || config['plans'] is! List) {
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

  Future<bool> buy(String placement, PlayChoice selected) async {
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
      ref.read(playBillingProvider);
      final addition =
          InAppPurchasePlatformAddition.instance
              as InAppPurchaseAndroidPlatformAddition;
      final owned = await addition.queryPastPurchases();
      if (owned.error != null) throw StateError('Google Play unavailable');
      return await _process(session, owned.pastPurchases, generation) ??
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

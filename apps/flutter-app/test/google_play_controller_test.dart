import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/google_play_controller.dart';
import 'package:kando_app/features/subscription/subscription_revenue_reporter.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/in_memory_auth_storage.dart';

AuthSession _user(String id) => AuthSession(
  ownerType: OwnerType.user,
  platform: AppPlatform.android,
  userId: id,
  dataSpaceId: id,
  accessToken: id,
  refreshToken: 'refresh-$id',
);

class _Auth extends AuthController {
  @override
  AuthState build() => AuthState.ready(session: _user('first'));
  void use(String id) => state = AuthState.ready(session: _user(id));
}

class _Billing extends InAppPurchasePlatform {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  int micros = 4990000;
  String? offer = 'welcome';
  GooglePlayPurchaseParam? launched;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    final details = ProductDetailsWrapper(
      description: 'Premium',
      name: 'Premium',
      productId: 'premium',
      productType: ProductType.subs,
      title: 'Premium',
      subscriptionOfferDetails: [
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'monthly',
          offerId: offer,
          offerIdToken: 'token-$micros',
          offerTags: [],
          pricingPhases: [
            PricingPhaseWrapper(
              billingCycleCount: 0,
              billingPeriod: 'P1M',
              formattedPrice: (micros / 1000000).toStringAsFixed(2),
              priceAmountMicros: micros,
              priceCurrencyCode: 'USD',
              recurrenceMode: RecurrenceMode.infiniteRecurring,
            ),
          ],
        ),
      ],
    );
    return ProductDetailsResponse(
      productDetails: GooglePlayProductDetails.fromProductDetails(details),
      notFoundIDs: [],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    launched = purchaseParam as GooglePlayPurchaseParam;
    return true;
  }
}

class _Server implements HttpClientAdapter {
  bool premium = false,
      sales = true,
      metered = true,
      report = false,
      acknowledgeFailed = false;
  int verifications = 0, acknowledgements = 0;
  final secondOwner = Completer<void>();
  final firstHandoff = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final who = options.headers['Authorization'];
    Object? data;
    if (options.path == '/entitlements/google/play') {
      if (who == 'Bearer second') await secondOwner.future;
      data = {
        'access_policy': metered ? 'metered' : 'free_launch',
        'sales_available': sales,
        'account_ref': 'owner-ref',
        'premium': who == 'Bearer first' && premium,
        'package_name': 'com.example.cards',
        'singular_delivery': report,
      };
    } else if (options.path.startsWith('/google-play/catalog')) {
      data = {
        'config': {
          'title': 'Premium',
          'plans': [
            {
              'product_id': 'premium',
              'base_plan_id': 'monthly',
              'offer_id': 'welcome',
              'label': 'Monthly',
              'is_default': true,
            },
          ],
        },
      };
    } else if (options.path.endsWith('/verify')) {
      verifications++;
      expect(who, 'Bearer first');
      expect(options.data['purchase_token'], 'verified-token');
      expect(options.headers['Idempotency-Key'], isNotEmpty);
      premium = true;
      data = {'premium': true, 'state': 'ACTIVE'};
    } else if (options.path.endsWith('/attribution')) {
      if (options.data['handed_off_order'] != null) {
        acknowledgements++;
        if (!firstHandoff.isCompleted) firstHandoff.complete();
        if (!acknowledgeFailed) {
          acknowledgeFailed = true;
          return ResponseBody.fromString('', 503);
        }
        data = {};
      } else {
        data = {
          'receipt': {
            'scope': 'production:google_play:com.example.cards',
            'order_id': 'GPA.first',
            'product_id': 'premium',
            'event_name': 'first_charge',
            'currency': 'USD',
            'amount_micros': '4990000',
          },
        };
      }
    } else {
      throw StateError('Unexpected path ${options.path}');
    }
    return ResponseBody.fromString(
      jsonEncode({'success': true, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RevenueSink implements SubscriptionRevenueSink {
  final sent = <SubscriptionRevenueRecord>[];
  @override
  Future<void> report(SubscriptionRevenueRecord record) async {
    sent.add(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Billing billing;
  late _Server server;
  late _RevenueSink sink;
  late List<PurchaseDetails> owned;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    billing = _Billing();
    server = _Server();
    sink = _RevenueSink();
    owned = [];
    final dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid/api/v1'))
      ..httpClientAdapter = server;
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        authStorageProvider.overrideWithValue(InMemoryAuthStorage()),
        playDioProvider.overrideWithValue(dio),
        playBillingProvider.overrideWithValue(billing),
        playOwnedPurchasesProvider.overrideWithValue(() async => owned),
        playSingularRevenueProvider.overrideWithValue(
          SubscriptionRevenueReporter(
            storage: const PreferencesSubscriptionRevenueStorage(
              keyPrefix: 'play-fixture',
            ),
            sink: sink,
          ),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await billing.events.close();
    debugDefaultTargetPlatformOverride = null;
  });
  Future<PlayController> controller() async {
    await container.read(playPolicyProvider.future);
    return container.read(playPolicyProvider.notifier);
  }

  PurchaseDetails purchase(PurchaseStatus status) => PurchaseDetails(
    productID: 'premium',
    transactionDate: null,
    status: status,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'verified-token',
      source: 'google_play',
    ),
  );

  test(
    'Play charges only after reconfirming the current account offer and price',
    () async {
      final play = await controller();
      final displayed = (await play.choices('page')).choices.single;
      billing.micros = 5990000;
      expect(await play.buy('page', displayed), isFalse);
      expect(billing.launched, isNull);
      final fresh = (await play.choices('page')).choices.single;
      billing.offer = null;
      expect(await play.buy('page', fresh), isFalse);
      billing.offer = 'welcome';
      expect(await play.buy('page', fresh), isTrue);
      expect(billing.launched?.offerToken, 'token-5990000');
      expect(billing.launched?.applicationUserName, 'owner-ref');
    },
  );
  test(
    'pending payments stay free and an Android restore grants only the verified owner',
    () async {
      final play = await controller();
      final pending = play.events.first;
      billing.events.add([purchase(PurchaseStatus.pending)]);
      expect(await pending, 'Payment pending');
      expect(server.verifications, 0);
      expect(container.read(playPolicyProvider).current?.premium, isFalse);
      owned = [purchase(PurchaseStatus.restored)];
      expect(await play.restore(), 'Premium is active');
      expect(server.verifications, 1);
      expect(container.read(playPolicyProvider).current?.premium, isTrue);
      owned = [];
      (container.read(authControllerProvider.notifier) as _Auth).use('second');
      expect(container.read(playPolicyProvider).current?.premium, isNot(true));
      server.secondOwner.complete();
      expect(
        (await container.read(playPolicyProvider.future)).premium,
        isFalse,
      );
    },
  );
  test(
    'a free-launch installation keeps its features and the Android login path',
    () async {
      server.metered = false;
      server.sales = false;
      await controller();
      final policy = container.read(subscriptionAccessPolicyProvider);
      expect(policy.hasFreePremiumFeatures, isTrue);
      expect(policy.usesAppleSubscription, isFalse);
      expect(policy.playSales, isFalse);
    },
  );
  test(
    'retrying a lost handoff acknowledgment never sends a second Singular charge',
    () async {
      server.report = true;
      final play = await controller();
      await server.firstHandoff.future.timeout(const Duration(seconds: 3));
      for (var i = 0; i < 30 && server.acknowledgements < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await play.refresh();
      }
      expect(server.acknowledgements, greaterThanOrEqualTo(2));
      expect(sink.sent.map((r) => r.transactionId), [
        'production:google_play:com.example.cards/GPA.first',
      ]);
      expect(sink.sent.single.value, 4.99);
    },
  );
}

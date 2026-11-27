import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:kando_app/app/router.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_permissions.dart';
import 'package:kando_app/features/subscription/google_play_page.dart';
import 'package:kando_app/features/subscription/scan_quota_controller.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/subscription/google_play_controller.dart';
import 'package:kando_app/features/subscription/subscription_display_config.dart';
import 'package:kando_app/features/subscription/subscription_navigation.dart';
import 'package:kando_app/features/subscription/subscription_revenue_reporter.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:kando_app/shared/ui/toast.dart';
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
  @override
  Future<void> retryStartup() async {} // Refreshing Profile keeps the same signed-in owner.
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
      pagePublished = true,
      modalPublished = true,
      report = false,
      acknowledgeFailed = false;
  String? unavailablePlacement;
  final catalogs = <String>[];
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
      final placement = options.uri.queryParameters['placement']!;
      catalogs.add(placement);
      if (placement == unavailablePlacement) {
        return ResponseBody.fromString('', 503);
      }
      final published = placement == 'modal' ? modalPublished : pagePublished;
      data = {
        'status': published ? 'configured' : 'unconfigured',
        'config': !published
            ? null
            : {
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

class _ExhaustedQuota extends ScanQuotaController {
  @override
  ScanQuotaState build() => const ScanQuotaState(
    limit: 10,
    remainingScans: 0,
    isServerAuthoritative: true,
  );
  @override
  Future<bool> refresh() async => true;
}

class _CameraPermission extends Fake implements ScanPermissionGateway {
  @override
  Future<ScanPermissionResult> requestCamera() async =>
      ScanPermissionResult.denied;
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
        profileVersionProvider.overrideWith((_) async => '1.0.8'),
        scanQuotaControllerProvider.overrideWith(_ExhaustedQuota.new),
        scanPermissionGatewayProvider.overrideWithValue(_CameraPermission()),
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
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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

  Future<GoRouter> openProfile(WidgetTester tester) async {
    final router = container.read(appRouterProvider)..go('/profile');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildKandoTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final page in [false, true]) {
    for (final modal in [false, true]) {
      testWidgets(
        'Play entries use their own placement: page=$page modal=$modal',
        (tester) async {
          server.pagePublished = page;
          server.modalPublished = modal;
          final router = await openProfile(tester);
          final viewPlans = find.text('View Premium plans');
          expect(viewPlans, page ? findsOneWidget : findsNothing);
          expect(
            find.byKey(const Key('profile-premium-top-entry')),
            page ? findsOneWidget : findsNothing,
          );
          expect(find.text('Restore purchases'), findsOneWidget);
          expect(find.text('Manage in Google Play'), findsOneWidget);
          if (page) {
            await tester.ensureVisible(viewPlans);
            await tester.tap(viewPlans);
            await tester.pumpAndSettle();
            expect(
              tester.widget<GooglePlayPage>(find.byType(GooglePlayPage)).sheet,
              isFalse,
            );
            expect(find.text('Monthly'), findsOneWidget);
            router.pop();
            await tester.pumpAndSettle();
          }
          router.go('/scan');
          await tester.pumpAndSettle();
          expect(find.text('0 scans remaining'), findsOneWidget);
          expect(
            find.text('Tap to get unlimited scans'),
            page ? findsOneWidget : findsNothing,
          );
          await tester.tap(find.byTooltip('Take Photo'));
          await tester.pumpAndSettle();
          if (modal) {
            expect(
              tester.widget<GooglePlayPage>(find.byType(GooglePlayPage)).sheet,
              isTrue,
            );
            expect(find.text('Monthly'), findsOneWidget);
          } else {
            expect(find.byType(GooglePlayPage), findsNothing);
            expect(find.text('0 scans remaining'), findsOneWidget);
          }
          if (!page && !modal) {
            router.go('/profile');
            await tester.pumpAndSettle();
            owned = [purchase(PurchaseStatus.restored)];
            final restore = find.text('Restore purchases');
            await tester.ensureVisible(restore);
            await tester.tap(restore);
            await tester.pumpAndSettle();
            expect(server.verifications, 1);
            expect(container.read(playPolicyProvider).current?.premium, isTrue);
          }
          await tester.pump(kandoTopToastDuration);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }
  testWidgets(
    'a stale Page link and a failed Modal lookup keep the user in place and can recover',
    (tester) async {
      final router = await openProfile(tester);
      expect(find.text('View Premium plans'), findsOneWidget);
      server.pagePublished = false;
      await tester.tap(find.byKey(const Key('profile-premium-top-entry')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('View Premium plans'), findsNothing);
      expect(find.byType(GooglePlayPage), findsNothing);

      server.pagePublished = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('View Premium plans'), findsOneWidget);
      router.go('/subscription');
      await tester.pumpAndSettle();
      expect(find.text('Monthly'), findsOneWidget);
      server.pagePublished = false;
      final checkout = find.text('Continue with Google Play');
      await tester.ensureVisible(checkout);
      await tester.tap(checkout);
      await tester.pumpAndSettle();
      expect(billing.launched, isNull);
      expect(checkout, findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
      // A direct link cannot reopen a placement once operations stop it.
      router.go('/profile');
      await tester.pumpAndSettle();
      router.go('/subscription');
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);

      server.unavailablePlacement = 'modal';
      router.go('/scan');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();
      expect(find.text(genericFailureToastText), findsOneWidget);
      expect(find.text('0 scans remaining'), findsOneWidget);
      expect(find.byType(GooglePlayPage), findsNothing);
      server.unavailablePlacement = null;
      await tester.tap(find.byTooltip('Take Photo'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GooglePlayPage>(find.byType(GooglePlayPage)).sheet,
        isTrue,
      );
      expect(find.text('Monthly'), findsOneWidget);
      await tester.pump(kandoTopToastDuration);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'the sales switch blocks both published placements while Profile still offers restore',
    (tester) async {
      server.sales = false;
      final router = await openProfile(tester);
      expect(find.text('View Premium plans'), findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
      router.go('/subscription?presentation=sheet');
      await tester.pumpAndSettle();
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(server.catalogs, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test(
    'a new Android account cannot inherit a published entry while its policy is loading',
    () async {
      await controller();
      container.listen(subscriptionPageEntryVisibleProvider, (_, _) {});
      final page = playDisplayConfigProvider(SubscriptionPageType.page);
      await container.read(page.future);
      expect(container.read(subscriptionPageEntryVisibleProvider), isTrue);
      server.pagePublished = false;
      (container.read(authControllerProvider.notifier) as _Auth).use('second');
      expect(container.read(subscriptionPageEntryVisibleProvider), isFalse);
      server.secondOwner.complete();
      await container.read(page.future);
      expect(container.read(subscriptionPageEntryVisibleProvider), isFalse);
    },
  );

  test(
    'Play charges only after reconfirming the current account offer and price',
    () async {
      final play = await controller();
      final displayed = (await play.choices(
        SubscriptionPageType.page,
      )).choices.single;
      billing.micros = 5990000;
      expect(await play.buy(SubscriptionPageType.page, displayed), isFalse);
      expect(billing.launched, isNull);
      final fresh = (await play.choices(
        SubscriptionPageType.page,
      )).choices.single;
      billing.offer = null;
      expect(await play.buy(SubscriptionPageType.page, fresh), isFalse);
      billing.offer = 'welcome';
      expect(await play.buy(SubscriptionPageType.page, fresh), isTrue);
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

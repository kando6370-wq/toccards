import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_revenue_reporter.dart';
import 'package:kando_app/features/subscription/subscription_singular_events.dart';
import 'package:kando_app/shared/api/api_environment.dart';
import 'package:kando_app/shared/attribution/app_attribution.dart';
import 'package:kando_app/shared/attribution/singular_bootstrap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subscription_core/subscription_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'retries failed startup configuration and flushes pending revenue without restarting or another purchase',
    (tester) async {
      const channel = MethodChannel('singular-api');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var online = false;
      final gateway = SingularAttributionGateway(
        loadCredentials: () async => online
            ? const SingularCredentials(apiKey: 'key', secretKey: 'secret')
            : null,
      );
      addTearDown(gateway.dispose);
      final container = ProviderContainer(
        overrides: [
          singularAttributionGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);
      final reporter = container.read(
        singularSubscriptionRevenueReporterProvider,
      );
      await gateway.updateTrackingStatus(AppTrackingStatus.denied);
      await expectLater(
        reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: true),
        throwsStateError,
      );
      final storage = PreferencesSubscriptionRevenueStorage(
        keyPrefix:
            'subscription.singular_revenue.${AppConfig.environment.name}',
      );
      expect(await storage.readPending(), hasLength(1));
      expect(await storage.readReportedTransactionIds(), isEmpty);
      expect(calls, isEmpty);

      online = true;
      await tester.pump(const Duration(seconds: 5));

      expect(calls.where((call) => call.method == 'start'), hasLength(1));
      expect(
        calls.where((call) => call.method == 'customRevenueWithAttributes'),
        hasLength(1),
      );
      expect(await storage.readPending(), isEmpty);
      expect(await storage.readReportedTransactionIds(), {'transaction-1'});
      await reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: true);
      await gateway.updateTrackingStatus(AppTrackingStatus.denied);
      await tester.pump(const Duration(minutes: 2));
      expect(calls.where((call) => call.method == 'start'), hasLength(1));
      expect(
        calls.where((call) => call.method == 'customRevenueWithAttributes'),
        hasLength(1),
      );
    },
  );

  for (final interruption in [
    AppLifecycleState.paused,
    AppLifecycleState.inactive,
  ]) {
    testWidgets(
      'resume from ${interruption.name} immediately recovers pending purchases',
      (tester) async {
        const channel = MethodChannel('singular-api');
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        var online = false;
        final gateway = SingularAttributionGateway(
          loadCredentials: () async => online
              ? const SingularCredentials(apiKey: 'key', secretKey: 'secret')
              : null,
        );
        addTearDown(gateway.dispose);
        final tracking = _DeniedTracking();
        final container = ProviderContainer(
          overrides: [
            singularAttributionGatewayProvider.overrideWithValue(gateway),
            appTrackingGatewayProvider.overrideWithValue(tracking),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const AppAttributionLifecycleObserver(child: SizedBox()),
          ),
        );
        final reporter = container.read(
          singularSubscriptionRevenueReporterProvider,
        );
        await container
            .read(appAttributionCoordinatorProvider)
            .prepareForStartup(allowInitialRequest: false);
        for (final id in ['transaction-1', 'transaction-2']) {
          await expectLater(
            reporter.enqueueVerifiedPurchase(
              _event(transactionId: id),
              isFreshPurchase: true,
            ),
            throwsStateError,
          );
        }
        final storage = PreferencesSubscriptionRevenueStorage(
          keyPrefix:
              'subscription.singular_revenue.${AppConfig.environment.name}',
        );
        expect(await storage.readPending(), hasLength(2));
        expect(await storage.readReportedTransactionIds(), isEmpty);
        tester.binding.handleAppLifecycleStateChanged(interruption);
        if (interruption == AppLifecycleState.paused) {
          online = true;
          await tester.pump(const Duration(minutes: 2));
        } else {
          // The system dialog finishes before the first five-second retry.
          await tester.pump(const Duration(seconds: 1));
          online = true;
        }
        expect(calls, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(calls.where((call) => call.method == 'start'), hasLength(1));
        expect(
          calls.where((call) => call.method == 'customRevenueWithAttributes'),
          hasLength(2),
        );
        expect(await storage.readPending(), isEmpty);
        expect(await storage.readReportedTransactionIds(), {
          'transaction-1',
          'transaction-2',
        });
        expect(tracking.requests, 0);
        expect(tracking.reads, 2);
        await reporter.flush();
        await reporter.enqueueVerifiedPurchase(
          _event(transactionId: 'transaction-2'),
          isFreshPurchase: true,
        );
        expect(
          calls.where((call) => call.method == 'customRevenueWithAttributes'),
          hasLength(2),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final environment in AppEnvironment.values) {
    for (final plan in ['weekly', 'yearly', 'lifetime']) {
      test(
        '${environment.name} $plan reports signed transaction revenue',
        () async {
          final sdk = _RecordingAttribution();
          final reporter = SingularSubscriptionRevenueReporter(
            environment: environment,
            attribution: sdk,
          );
          await reporter.enqueueVerifiedPurchase(
            _event(plan: plan),
            isFreshPurchase: true,
          );
          expect(sdk.records.single, {
            'eventName':
                '${plan}_card${environment == AppEnvironment.test ? 'test' : ''}',
            'currency': 'CAD',
            'value': 5.49,
            'transactionId': 'transaction-1',
            'productId': 'apple.$plan',
          });
        },
      );
    }
  }

  test(
    'concurrent callbacks and reporter recreation do not repeat revenue or touch Firebase storage',
    () async {
      final sdk = _RecordingAttribution();
      const firebaseStorage = PreferencesSubscriptionRevenueStorage();
      await firebaseStorage.write(
        reportedTransactionIds: {'transaction-1'},
        pending: {},
      );
      SingularSubscriptionRevenueReporter createReporter() =>
          SingularSubscriptionRevenueReporter(
            environment: AppEnvironment.test,
            attribution: sdk,
          );
      final reporter = createReporter();
      await Future.wait([
        reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: true),
        reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: true),
      ]);
      await createReporter().enqueueVerifiedPurchase(
        _event(),
        isFreshPurchase: true,
      );
      expect(sdk.records, hasLength(1));
      expect(await firebaseStorage.readReportedTransactionIds(), {
        'transaction-1',
      });
      expect(await firebaseStorage.readPending(), isEmpty);
    },
  );

  test(
    'failed handoff stays pending and retries after restart without a new purchase',
    () async {
      final sdk = _RecordingAttribution()..fail = true;
      final reporter = SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: sdk,
      );
      await expectLater(
        reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: true),
        throwsStateError,
      );
      sdk.fail = false;
      final restarted = SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: sdk,
      );
      await restarted.flush();
      await restarted.flush();
      expect(sdk.records, hasLength(1));
    },
  );

  test(
    'Restore, external unlock, Pending, failures and inactive entitlements never create revenue',
    () async {
      final sdk = _RecordingAttribution();
      final reporter = SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: sdk,
      );
      for (final status in SubscriptionPurchaseStatus.values.where(
        (status) => status != SubscriptionPurchaseStatus.purchased,
      )) {
        await reporter.enqueueVerifiedPurchase(
          _event(status: status),
          isFreshPurchase: true,
        );
      }
      await reporter.enqueueVerifiedPurchase(_event(), isFreshPurchase: false);
      await reporter.enqueueVerifiedPurchase(
        _event(failed: true),
        isFreshPurchase: true,
      );
      await reporter.enqueueVerifiedPurchase(
        _event(active: false),
        isFreshPurchase: true,
      );
      await reporter.flush();
      expect(sdk.records, isEmpty);
    },
  );

  test(
    'missing or mismatched signed fields never fall back to the product display price',
    () async {
      final sdk = _RecordingAttribution();
      final reporter = SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: sdk,
      );
      for (final fields in <Map<String, Object?>>[
        {'price': null},
        {'currency': null},
        {'price': -1},
        {'currency': 'invalid'},
        {'transactionId': 'another-transaction'},
        {'productId': 'another-product'},
      ]) {
        await reporter.enqueueVerifiedPurchase(
          _event(fields: fields),
          isFreshPurchase: true,
        );
      }
      await reporter.enqueueVerifiedPurchase(
        _event(plan: 'unknown'),
        isFreshPurchase: true,
      );
      expect(sdk.records, isEmpty);
    },
  );

  test(
    'a zero-price transaction stays zero instead of reporting the paid plan price',
    () async {
      final sdk = _RecordingAttribution();
      final reporter = SingularSubscriptionRevenueReporter(
        environment: AppEnvironment.test,
        attribution: sdk,
      );
      await reporter.enqueueVerifiedPurchase(
        _event(fields: {'price': 0}),
        isFreshPurchase: true,
      );
      expect(sdk.records.single['value'], 0);
    },
  );
}

SubscriptionEvent _event({
  String plan = 'weekly',
  String transactionId = 'transaction-1',
  SubscriptionPurchaseStatus status = SubscriptionPurchaseStatus.purchased,
  bool failed = false,
  bool active = true,
  Map<String, Object?> fields = const {},
}) {
  final payload = {
    'transactionId': transactionId,
    'productId': 'apple.$plan',
    'price': 5490,
    'currency': 'cad',
    ...fields,
  };
  final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return SubscriptionEvent(
    purchase: SubscriptionPurchase(
      store: SubscriptionStore.appStore,
      storeProductId: 'apple.$plan',
      status: status,
      verificationData: 'header.$encoded.signature',
      transactionId: transactionId,
    ),
    plan: SubscriptionPlanConfig(
      id: plan,
      entitlementId: 'performance_pro',
      productIds: {SubscriptionStore.appStore: 'apple.$plan'},
    ),
    entitlement: SubscriptionEntitlement(
      planId: plan,
      entitlementId: 'performance_pro',
      status: active
          ? SubscriptionEntitlementStatus.active
          : SubscriptionEntitlementStatus.expired,
    ),
    failure: failed
        ? const SubscriptionFailure(
            code: 'verification_failed',
            message: 'unverified',
          )
        : null,
  );
}

class _DeniedTracking implements AppTrackingGateway {
  int reads = 0;
  int requests = 0;

  @override
  Future<AppTrackingStatus> readStatus() async {
    reads++;
    return AppTrackingStatus.denied;
  }

  @override
  Future<AppTrackingStatus> requestAuthorization() async {
    requests++;
    return AppTrackingStatus.denied;
  }
}

class _RecordingAttribution implements AppAttributionEventReporter {
  final records = <Map<String, Object>>[];
  bool fail = false;

  @override
  Future<void> trackRevenue({
    required String eventName,
    required String currency,
    required double value,
    required String transactionId,
    required String productId,
  }) async {
    if (fail) throw StateError('SDK unavailable');
    records.add({
      'eventName': eventName,
      'currency': currency,
      'value': value,
      'transactionId': transactionId,
      'productId': productId,
    });
  }
}

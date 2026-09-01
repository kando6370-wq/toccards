import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/onboarding/onboarding_controller.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';
import 'package:kando_app/shared/attribution/app_attribution.dart';
import 'package:mixpanel_flutter/mixpanel_flutter.dart';

import 'support/in_memory_onboarding_storage.dart';
import 'support/test_app_attribution.dart';

void main() {
  testWidgets('cold-start events wait for the restored user uid', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();
    final authRepository = _PendingInitialAuthRepository();
    final mixpanel = _RecordingMixpanel();
    final analytics = AppAnalytics.initializingForTest(Future.value(mixpanel));

    await tester.pumpWidget(
      _testApp(storage, authRepository: authRepository, analytics: analytics),
    );
    await tester.pump();

    expect(mixpanel.events, isEmpty);

    authRepository.initialSession.complete(
      const AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: '100028',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(mixpanel.events, contains(AnalyticsEvent.splashView));
    expect(
      mixpanel.properties
          .singleWhere((entry) => entry.$1 == AnalyticsEvent.splashView)
          .$2,
      containsPair(AnalyticsProperty.uid, '100028'),
    );

    await _finishStartup(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('KandoApp shows onboarding before the startup home page', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();

    await tester.pumpWidget(_testApp(storage));
    await _finishStartup(tester);

    expect(find.byKey(const ValueKey('onboarding-guides')), findsOneWidget);
    expect(find.text('Instantly Scan Cards'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);

    await tester.tap(find.byTooltip("LET'S START"));
    await _finishPageTransition(tester);
    await tester.tap(find.byTooltip('NEXT'));
    await _finishPageTransition(tester);
    await tester.tap(find.byTooltip('Skip and start now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Choose Your Plan'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.text('Guest session'), findsNothing);
    expect(find.text('Delete account'), findsNothing);

    await tester.pumpWidget(_testApp(storage));
    await _finishStartup(tester);

    expect(find.byKey(const ValueKey('onboarding-guides')), findsNothing);
    expect(find.text('Overview'), findsOneWidget);
  });
}

Future<void> _finishStartup(WidgetTester tester) async {
  await tester.pump(OnboardingController.minimumSplashDuration);
  await tester.pump();
  await tester.pump(OnboardingController.progressCompletionDuration);
  await tester.pump(OnboardingController.completedProgressHoldDuration);
  await tester.pump();
}

Future<void> _finishPageTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

ProviderScope _testApp(
  InMemoryOnboardingStorage storage, {
  AuthRepository? authRepository,
  AppAnalytics? analytics,
}) {
  return ProviderScope(
    overrides: [
      appAttributionCoordinatorProvider.overrideWithValue(
        testAppAttributionCoordinator(),
      ),
      appStartupPreloaderProvider.overrideWith((ref) async {}),
      authRepositoryProvider.overrideWithValue(
        authRepository ??
            _WidgetTestAuthRepository(
              AuthSession(
                ownerType: OwnerType.anonymous,
                accessToken: 'guest-access',
                refreshToken: 'guest-refresh',
                anonymousId: 'guest-1',
              ),
            ),
      ),
      if (analytics != null) analyticsProvider.overrideWithValue(analytics),
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
      subscriptionControllerProvider.overrideWith(
        _FreeWidgetTestSubscriptionController.new,
      ),
    ],
    child: const KandoApp(),
  );
}

class _PendingInitialAuthRepository extends _WidgetTestAuthRepository {
  _PendingInitialAuthRepository()
    : super(
        const AuthSession(
          ownerType: OwnerType.anonymous,
          accessToken: 'guest-access',
          refreshToken: 'guest-refresh',
          anonymousId: 'guest-1',
        ),
      );

  final initialSession = Completer<AuthSession?>();

  @override
  Future<AuthSession?> currentSessionFromStorage() => initialSession.future;
}

class _RecordingMixpanel extends Mixpanel {
  _RecordingMixpanel() : super('test-token');

  final events = <String>[];
  final properties = <(String, Map<String, dynamic>)>[];

  @override
  Future<void> identify(String distinctId) async {}

  @override
  Future<void> track(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    events.add(eventName);
    this.properties.add((eventName, Map.of(properties ?? const {})));
  }
}

class _FreeWidgetTestSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() =>
      const SubscriptionState(premiumState: AppPremiumState.free);

  @override
  Future<AppPremiumState> refreshEntitlement({bool showFailure = true}) async {
    return AppPremiumState.free;
  }
}

class _WidgetTestAuthRepository implements AuthRepository {
  _WidgetTestAuthRepository(this._anonymousSession);

  final AuthSession _anonymousSession;

  @override
  Future<AuthSession?> currentSessionFromStorage() async => null;

  @override
  Future<AuthSession?> previousAnonymousSessionFromStorage() async => null;

  @override
  Future<AuthSession> createAnonymousSession(String deviceId) async {
    return _anonymousSession;
  }

  @override
  Future<AuthSession?> validateStoredSession(AuthSession session) async {
    return session;
  }

  @override
  Future<void> persistSession(AuthSession session) async {}

  @override
  Future<void> clearUserSession() async {}

  @override
  Future<void> clearAnonymousSession() async {}

  @override
  Future<void> deleteCurrentAccount(AuthSession session) async {}

  @override
  Future<void> sendRegisterCode(String email) async {}

  @override
  Future<void> verifyRegisterCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  }) async {
    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'user-1',
      email: email,
    );
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'user-1',
      email: email,
    );
  }

  @override
  Future<AuthSession> googleCallback({
    required String idToken,
    String? anonymousId,
  }) async {
    return const AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'google-user',
      email: 'google@example.com',
    );
  }

  @override
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  }) async {
    return const AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'user-access',
      refreshToken: 'user-refresh',
      userId: 'apple-user',
      email: 'apple@example.com',
    );
  }

  @override
  Future<void> sendForgotPasswordCode(String email) async {}

  @override
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) async {
    return 'reset-token';
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {}
}

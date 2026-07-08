import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';

void main() {
  testWidgets('KandoApp shows onboarding before the startup home page', (
    tester,
  ) async {
    final storage = InMemoryOnboardingStorage();

    await tester.pumpWidget(_testApp(storage));

    await tester.pumpAndSettle();

    expect(find.text('Track your collection'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('PORTFOLIO'), findsOneWidget);
    expect(find.text('Guest session'), findsNothing);
    expect(find.text('Delete account'), findsNothing);

    await tester.pumpWidget(_testApp(storage));
    await tester.pumpAndSettle();

    expect(find.text('Track your collection'), findsNothing);
    expect(find.text('Overview'), findsOneWidget);
  });
}

ProviderScope _testApp(InMemoryOnboardingStorage storage) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        _WidgetTestAuthRepository(
          AuthSession(
            ownerType: OwnerType.anonymous,
            accessToken: 'guest-access',
            refreshToken: 'guest-refresh',
            anonymousId: 'guest-1',
          ),
        ),
      ),
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(storage),
      ),
    ],
    child: const KandoApp(),
  );
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
  Future<void> sendRegisterCode(String email) async {}

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
    required String code,
    required String redirectUri,
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

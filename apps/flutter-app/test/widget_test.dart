import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

void main() {
  testWidgets('KandoApp shows the startup guest profile', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
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
        ],
        child: const KandoApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Guest session'), findsOneWidget);
    expect(find.text('guest-1'), findsOneWidget);
    expect(find.text('Log out'), findsNothing);
    expect(find.text('Delete account'), findsOneWidget);
  });
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
}

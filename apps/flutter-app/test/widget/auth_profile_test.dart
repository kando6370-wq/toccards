import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

void main() {
  testWidgets(
    'guest profile exposes account deletion through confirmation but not logout',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('Sign in / Sign up'), findsOneWidget);
      expect(find.text('Customer Support'), findsOneWidget);
      expect(find.text('Score'), findsOneWidget);
      expect(find.text('Share With Friends'), findsOneWidget);
      expect(find.text('Terms Of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Log Out'), findsNothing);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Account?'), findsOneWidget);
      expect(
        find.text("This action is permanent and can't be undone."),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleteRequests, 0);
    },
  );

  testWidgets('user profile navigates to account details', (tester) async {
    final repository = _WidgetAuthRepository(initialSession: _userSession());

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('person@example.com'), findsOneWidget);
    expect(find.text('user-1'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  testWidgets(
    'logout from account creates a guest profile without previous anonymous',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _userSession(),
        createdAnonymousIds: ['anon-after-logout'],
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Guest session'), findsOneWidget);
      expect(find.text('anon-after-logout'), findsOneWidget);
      expect(find.text('Log Out'), findsNothing);
      expect(repository.logoutRequests, 1);
    },
  );

  testWidgets(
    'guest delete discards the old anonymous id and creates a fresh guest',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-old'),
        createdAnonymousIds: ['anon-fresh'],
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('anon-old'), findsOneWidget);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('anon-old'), findsNothing);
      expect(find.text('anon-fresh'), findsOneWidget);
      expect(repository.deleteRequests, 1);
    },
  );

  testWidgets('user delete returns to a guest profile', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _userSession(),
      createdAnonymousIds: ['anon-after-delete'],
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Guest session'), findsOneWidget);
    expect(find.text('anon-after-delete'), findsOneWidget);
    expect(find.text('person@example.com'), findsNothing);
  });
}

ProviderScope _testApp(_WidgetAuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const KandoApp(),
  );
}

AuthSession _anonymousSession(String anonymousId) {
  return AuthSession(
    ownerType: OwnerType.anonymous,
    accessToken: '$anonymousId-access',
    refreshToken: '$anonymousId-refresh',
    anonymousId: anonymousId,
  );
}

AuthSession _userSession() {
  return const AuthSession(
    ownerType: OwnerType.user,
    accessToken: 'user-access',
    refreshToken: 'user-refresh',
    userId: 'user-1',
    email: 'person@example.com',
  );
}

class _WidgetAuthRepository implements AuthRepository {
  _WidgetAuthRepository({
    required AuthSession initialSession,
    List<String> createdAnonymousIds = const [],
  }) : _currentSession = initialSession,
       _createdAnonymousIds = [...createdAnonymousIds];

  AuthSession? _currentSession;
  final List<String> _createdAnonymousIds;
  var logoutRequests = 0;
  var deleteRequests = 0;

  @override
  Future<AuthSession?> currentSessionFromStorage() async => _currentSession;

  @override
  Future<AuthSession?> previousAnonymousSessionFromStorage() async => null;

  @override
  Future<AuthSession> createAnonymousSession(String deviceId) async {
    final anonymousId = _createdAnonymousIds.isEmpty
        ? 'anon-created'
        : _createdAnonymousIds.removeAt(0);
    return _anonymousSession(anonymousId);
  }

  @override
  Future<AuthSession?> validateStoredSession(AuthSession session) async {
    return session;
  }

  @override
  Future<void> persistSession(AuthSession session) async {
    _currentSession = session;
  }

  @override
  Future<void> clearUserSession() async {
    if (_currentSession?.isUser ?? false) {
      logoutRequests++;
      _currentSession = null;
    }
  }

  @override
  Future<void> clearAnonymousSession() async {
    deleteRequests++;
    if (_currentSession?.isAnonymous ?? false) {
      _currentSession = null;
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

void main() {
  testWidgets('email auth rejects empty and invalid email before continuing', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your email.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
  });

  testWidgets('short login password blocks submit', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');

    await tester.enterText(find.byType(TextFormField), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(repository.loginRequests, isEmpty);
  });

  testWidgets('successful email login switches profile to user state', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, ' PERSON@example.com ');

    await tester.enterText(find.byType(TextFormField), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await tester.pumpAndSettle();

    expect(repository.loginRequests, [
      const _LoginRequest('person@example.com', 'password123'),
    ]);
    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('person@example.com'), findsWidgets);
  });

  testWidgets(
    'login submit is disabled and deduped while request is in flight',
    (tester) async {
      final loginCompleter = Completer<AuthSession>();
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
        loginCompleter: loginCompleter,
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openEmailAuth(tester);
      await _continueWithEmail(tester, 'person@example.com');

      await tester.enterText(find.byType(TextFormField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pump();

      final loadingButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Loading...'),
      );
      expect(loadingButton.onPressed, isNull);
      expect(repository.loginRequests, [
        const _LoginRequest('person@example.com', 'password123'),
      ]);

      loginCompleter.complete(_userSession());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('register password mismatch blocks submit', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password456');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(repository.registerRequests, isEmpty);
  });

  testWidgets('successful register passes current anonymous id', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(repository.registerCodeEmails, ['person@example.com']);
    expect(repository.registerRequests, [
      const _RegisterRequest(
        email: 'person@example.com',
        code: '123456',
        password: 'password123',
        anonymousId: 'anon-existing',
      ),
    ]);
    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('register code error shows incorrect code and does not sign in', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      registerError: Exception('invalid_verification_code'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect verification code.'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);
  });

  testWidgets('forgot password reset success returns to login path', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await tester.tap(find.text('Forgot password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' PERSON@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'newpass123');
    await tester.enterText(fields.at(1), 'newpass123');
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();

    expect(repository.forgotCodeEmails, ['person@example.com']);
    expect(repository.forgotVerifications, [
      const _CodeRequest('person@example.com', '654321'),
    ]);
    expect(repository.resetRequests, [
      const _ResetRequest('person@example.com', 'reset-token', 'newpass123'),
    ]);
    expect(find.text('Log in'), findsOneWidget);
    final loginPasswordField = tester.widget<TextFormField>(
      find.byType(TextFormField),
    );
    expect(loginPasswordField.controller?.text, isEmpty);
  });

  testWidgets('forgot code expiry shows expired code and stays on code step', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      forgotCodeError: Exception('code_expired'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openEmailAuth(tester);
    await tester.tap(find.text('Forgot password'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(
      find.text('Code expired. Please request a new code.'),
      findsOneWidget,
    );
    expect(find.text('Reset password'), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
  });

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

Future<void> _openEmailAuth(WidgetTester tester) async {
  await tester.tap(find.text('Sign in / Sign up'));
  await tester.pumpAndSettle();
  expect(find.text('Continue with Google'), findsOneWidget);
  expect(find.text('Continue with Apple'), findsOneWidget);
  await tester.tap(find.text('Continue with Email'));
  await tester.pumpAndSettle();
}

Future<void> _continueWithEmail(WidgetTester tester, String email) async {
  await tester.enterText(find.byType(TextFormField), email);
  await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
  await tester.pumpAndSettle();
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

AuthSession _userSession({String email = 'person@example.com'}) {
  return AuthSession(
    ownerType: OwnerType.user,
    accessToken: 'user-access',
    refreshToken: 'user-refresh',
    userId: 'user-1',
    email: email,
  );
}

class _WidgetAuthRepository implements AuthRepository {
  _WidgetAuthRepository({
    required AuthSession initialSession,
    List<String> createdAnonymousIds = const [],
    this.registerError,
    this.forgotCodeError,
    this.loginCompleter,
  }) : _currentSession = initialSession,
       _createdAnonymousIds = [...createdAnonymousIds];

  AuthSession? _currentSession;
  final List<String> _createdAnonymousIds;
  final Exception? registerError;
  final Exception? forgotCodeError;
  final Completer<AuthSession>? loginCompleter;
  var logoutRequests = 0;
  var deleteRequests = 0;
  final List<_LoginRequest> loginRequests = [];
  final List<String> registerCodeEmails = [];
  final List<_RegisterRequest> registerRequests = [];
  final List<String> forgotCodeEmails = [];
  final List<_CodeRequest> forgotVerifications = [];
  final List<_ResetRequest> resetRequests = [];

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

  @override
  Future<void> sendRegisterCode(String email) async {
    registerCodeEmails.add(email);
  }

  @override
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  }) async {
    final error = registerError;
    if (error != null) {
      throw error;
    }
    registerRequests.add(
      _RegisterRequest(
        email: email,
        code: code,
        password: password,
        anonymousId: anonymousId,
      ),
    );
    return _userSession(email: email);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    loginRequests.add(_LoginRequest(email, password));
    final completer = loginCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _userSession(email: email);
  }

  @override
  Future<void> sendForgotPasswordCode(String email) async {
    forgotCodeEmails.add(email);
  }

  @override
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) async {
    final error = forgotCodeError;
    if (error != null) {
      throw error;
    }
    forgotVerifications.add(_CodeRequest(email, code));
    return 'reset-token';
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    resetRequests.add(_ResetRequest(email, resetToken, newPassword));
  }
}

class _LoginRequest {
  const _LoginRequest(this.email, this.password);

  final String email;
  final String password;

  @override
  bool operator ==(Object other) {
    return other is _LoginRequest &&
        other.email == email &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(email, password);
}

class _RegisterRequest {
  const _RegisterRequest({
    required this.email,
    required this.code,
    required this.password,
    required this.anonymousId,
  });

  final String email;
  final String code;
  final String password;
  final String? anonymousId;

  @override
  bool operator ==(Object other) {
    return other is _RegisterRequest &&
        other.email == email &&
        other.code == code &&
        other.password == password &&
        other.anonymousId == anonymousId;
  }

  @override
  int get hashCode => Object.hash(email, code, password, anonymousId);
}

class _CodeRequest {
  const _CodeRequest(this.email, this.code);

  final String email;
  final String code;

  @override
  bool operator ==(Object other) {
    return other is _CodeRequest && other.email == email && other.code == code;
  }

  @override
  int get hashCode => Object.hash(email, code);
}

class _ResetRequest {
  const _ResetRequest(this.email, this.resetToken, this.newPassword);

  final String email;
  final String resetToken;
  final String newPassword;

  @override
  bool operator ==(Object other) {
    return other is _ResetRequest &&
        other.email == email &&
        other.resetToken == resetToken &&
        other.newPassword == newPassword;
  }

  @override
  int get hashCode => Object.hash(email, resetToken, newPassword);
}

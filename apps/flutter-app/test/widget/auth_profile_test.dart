import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/oauth_authorizer.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/ui/auth_sheet.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:kando_app/features/profile/feedback_repository.dart';
import 'package:kando_app/features/profile/profile_actions.dart';

import '../support/in_memory_onboarding_storage.dart';

void main() {
  testWidgets('email auth disables blank submit and rejects invalid email', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);

    final continueButton = find.widgetWithText(FilledButton, 'CONTINUE');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    await tester.tap(continueButton);
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    for (final email in [
      'person@@example.com',
      'person@example',
      'person @example.com',
      '@example.com',
      'person@.com',
      '${List.filled(250, 'a').join()}@example.com',
    ]) {
      await tester.enterText(find.byType(TextFormField), email);
      await tester.pump();
      await tester.tap(continueButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Please enter a valid email address.'),
        findsOneWidget,
        reason: '$email must be rejected by PRD email validation',
      );
    }
  });

  testWidgets('short login password blocks submit', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');

    await tester.enterText(find.byType(TextFormField), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'LOG IN'));
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
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, ' PERSON@example.com ');

    await tester.enterText(find.byType(TextFormField), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'LOG IN'));
    await tester.pumpAndSettle();

    expect(repository.loginRequests, [
      const _LoginRequest('person@example.com', 'password123'),
    ]);
    expect(find.byKey(const Key('email-auth-page')), findsNothing);
    expect(find.byKey(const Key('auth-sheet-panel')), findsNothing);
    expect(find.text('person@example.com'), findsWidgets);
    expect(find.text('Sign in / Sign up'), findsNothing);
  });

  testWidgets('google auth sheet button signs in with current guest id', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      result: const OAuthAuthorizationResult.google(
        code: 'mock-google:flutter-google-user:flutter.google@example.com',
      ),
    );

    await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openAuthSheet(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(authorizer.requests, [OAuthProvider.google]);
    expect(repository.googleCallbackRequests, [
      const _GoogleCallbackRequest(
        code: 'mock-google:flutter-google-user:flutter.google@example.com',
        redirectUri: 'kando://auth/google',
        anonymousId: 'anon-existing',
      ),
    ]);
    expect(find.text('flutter.google@example.com'), findsWidgets);
  });

  testWidgets('apple auth sheet button signs in with current guest id', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      result: const OAuthAuthorizationResult.apple(
        code: 'apple-auth-code',
        idToken: 'mock-apple:flutter-apple-user:flutter.apple@example.com',
      ),
    );

    await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openAuthSheet(tester);
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();

    expect(authorizer.requests, [OAuthProvider.apple]);
    expect(repository.appleCallbackRequests, [
      const _AppleCallbackRequest(
        code: 'apple-auth-code',
        idToken: 'mock-apple:flutter-apple-user:flutter.apple@example.com',
        anonymousId: 'anon-existing',
      ),
    ]);
    expect(find.text('flutter.apple@example.com'), findsWidgets);
  });

  testWidgets(
    'auth sheet shows agreement links because every sign-in method must disclose legal terms',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );
      final profileActions = _WidgetProfileActions();

      await tester.pumpWidget(
        _testApp(repository, profileActions: profileActions),
      );
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await _openAuthSheet(tester);

      final agreement = find.byKey(const Key('auth-agreement-text'));
      expect(agreement, findsOneWidget);
      final agreementText = tester
          .widget<RichText>(agreement)
          .text
          .toPlainText();
      expect(
        agreementText,
        'By continuing, you agree to our Terms of Use and Privacy Policy.',
      );
      expect(agreementText, contains('Terms of Use'));
      expect(agreementText, contains('Privacy Policy'));

      final spans = (tester.widget<RichText>(agreement).text as TextSpan)
          .children!
          .cast<TextSpan>();
      (spans[1].recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      (spans[3].recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();

      expect(profileActions.calls, ['terms', 'privacy']);
    },
  );

  testWidgets(
    'auth sheet uses the Figma bottom-panel geometry because sign-in must stay stable at the onboarding viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );

      await tester.pumpWidget(_testAuthSheetApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open auth'));
      await tester.pumpAndSettle();

      final panel = find.byKey(const Key('auth-sheet-panel'));
      final closeButton = find.byKey(const Key('auth-sheet-close'));
      expect(panel, findsOneWidget);
      expect(tester.getSize(panel), const Size(390, 343));
      expect(tester.getBottomRight(panel), const Offset(390, 844));
      expect(tester.getSize(closeButton), const Size.square(40));

      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);
      expect(repository.loginRequests, isEmpty);
      expect(repository.googleCallbackRequests, isEmpty);
      expect(repository.appleCallbackRequests, isEmpty);
    },
  );

  testWidgets('normal auth options render the Figma panel canvas', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();

    final panelCanvas = find.byKey(const Key('auth-options-panel-canvas'));
    expect(panelCanvas, findsOneWidget);
    expect(tester.widget<RepaintBoundary>(panelCanvas), isNotNull);
    expect(find.byKey(const Key('auth-options-close-canvas')), findsOneWidget);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/auth/auth_options_panel_canvas.png'),
        tester.element(panelCanvas),
      ),
    );
    await tester.pump();
    await expectLater(
      panelCanvas,
      matchesGoldenFile(
        'goldens/rendered/figma_auth_options_panel_183_11494_390x343.png',
      ),
    );
  });

  testWidgets(
    'normal auth options expose legal links because static Figma text must remain accessible',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final repository = _WidgetAuthRepository(
          initialSession: _anonymousSession('anon-existing'),
        );

        await tester.pumpWidget(_testAuthSheetApp(repository));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open auth'));
        await tester.pumpAndSettle();

        final agreement = tester.getSemantics(
          find.byKey(const Key('auth-agreement-text')),
        );
        final linkLabels = <String>[];
        agreement.visitChildren((child) {
          linkLabels.add(child.label);
          return true;
        });
        expect(linkLabels, contains('Terms of Use'));
        expect(linkLabels, contains('Privacy Policy'));
      } finally {
        semanticsHandle.dispose();
      }
    },
  );

  testWidgets('oauth failure renders the Figma panel canvas', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      error: Exception('provider failed'),
    );

    await tester.pumpWidget(
      _testAuthSheetApp(repository, authorizer: authorizer),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('auth-sheet-panel'));
    final failureCanvas = find.byKey(
      const Key('auth-options-failure-panel-canvas'),
    );
    final closeButton = find.byKey(const Key('auth-sheet-close'));
    expect(tester.getSize(panel), const Size(390, 407));
    expect(tester.getBottomRight(panel), const Offset(390, 844));
    expect(tester.getTopLeft(closeButton), const Offset(175, 381));
    expect(failureCanvas, findsOneWidget);
    expect(find.byKey(const Key('auth-options-close-canvas')), findsOneWidget);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/auth/auth_failure_panel_canvas.png'),
        tester.element(failureCanvas),
      ),
    );
    await tester.pump();
    await expectLater(
      failureCanvas,
      matchesGoldenFile(
        'goldens/rendered/figma_auth_failure_panel_183_11556_390x407.png',
      ),
    );
  });

  testWidgets('oauth failure keeps email fallback available', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      error: Exception('provider failed'),
    );

    await tester.pumpWidget(
      _testAuthSheetApp(repository, authorizer: authorizer),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();

    expect(authorizer.requests, [OAuthProvider.google]);
    expect(find.byKey(const Key('email-auth-page')), findsOneWidget);
  });

  testWidgets('oauth failure keeps Google retry available', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      error: Exception('provider failed'),
    );

    await tester.pumpWidget(
      _testAuthSheetApp(repository, authorizer: authorizer),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(authorizer.requests, [OAuthProvider.google, OAuthProvider.google]);
    expect(find.byKey(const Key('auth-oauth-warning')), findsOneWidget);
  });

  testWidgets('oauth failure allows switching to Apple', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      error: Exception('provider failed'),
    );

    await tester.pumpWidget(
      _testAuthSheetApp(repository, authorizer: authorizer),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();

    expect(authorizer.requests, [OAuthProvider.google, OAuthProvider.apple]);
    expect(find.byKey(const Key('auth-oauth-warning')), findsOneWidget);
  });

  testWidgets(
    'email option opens the Figma full-screen email flow instead of keeping the form in the auth sheet',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );

      await tester.pumpWidget(_testAuthSheetApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();

      final emailPage = find.byKey(const Key('email-auth-page'));
      expect(emailPage, findsOneWidget);
      expect(tester.getSize(emailPage), const Size(390, 844));
      expect(find.byKey(const Key('email-auth-back')), findsOneWidget);
      expect(find.text('Continue With Email'), findsOneWidget);
    },
  );

  testWidgets('oauth authorization failure shows retry copy and keeps guest', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      error: Exception('provider failed'),
    );

    await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openAuthSheet(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(
      find.text('Authorization failed. Please try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('auth-oauth-warning')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('auth-sheet-panel'))).height,
      407,
    );
    expect(repository.googleCallbackRequests, isEmpty);
  });

  testWidgets('oauth callback authorization failure shows retry copy', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      googleCallbackError: const OAuthAuthorizationException(),
    );
    final authorizer = _WidgetOAuthAuthorizer(
      result: const OAuthAuthorizationResult.google(
        code: 'mock-google:flutter-google-user:flutter.google@example.com',
      ),
    );

    await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openAuthSheet(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(
      find.text('Authorization failed. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Sign in / Sign up'), findsOneWidget);
    expect(repository._currentSession?.anonymousId, 'anon-existing');
    expect(repository.googleCallbackRequests, [
      const _GoogleCallbackRequest(
        code: 'mock-google:flutter-google-user:flutter.google@example.com',
        redirectUri: 'kando://auth/google',
        anonymousId: 'anon-existing',
      ),
    ]);
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
      await _openProfileTab(tester);
      await _openEmailAuth(tester);
      await _continueWithEmail(tester, 'person@example.com');

      await tester.enterText(find.byType(TextFormField), 'password123');
      await tester.tap(find.widgetWithText(FilledButton, 'LOG IN'));
      await tester.tap(find.widgetWithText(FilledButton, 'LOG IN'));
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
      emailRegistered: false,
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password456');
    await tester.tap(find.widgetWithText(FilledButton, 'CREATE ACCOUNT'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(repository.registerRequests, isEmpty);
  });

  testWidgets('register verification requires all six code digits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );

    expect(find.byKey(const Key('verification-code-box-0')), findsOneWidget);
    expect(find.byKey(const Key('verification-code-box-5')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '12345',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '123456',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Get verification code'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('successful register passes current anonymous id', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'CREATE ACCOUNT'));
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
    expect(find.text('Welcome\nLet’s collect the cards.'), findsOneWidget);
    expect(find.byKey(const Key('email-auth-page')), findsNothing);
  });

  testWidgets('register code error shows incorrect code and does not sign in', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      registerError: Exception('invalid_verification_code'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(find.byType(TextFormField), '123456');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Incorrect verification code.'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
    final firstBox = tester.widget<Container>(
      find.byKey(const Key('verification-code-box-0')),
    );
    final decoration = firstBox.decoration! as BoxDecoration;
    expect(decoration.border, Border.all(color: const Color(0xFFFF8787)));
    expect(
      find.widgetWithText(FilledButton, 'Get verification code'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password reset success returns to login path', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Forgot Password ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' PERSON@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'newpass123');
    await tester.enterText(fields.at(1), 'newpass123');
    await tester.tap(find.widgetWithText(FilledButton, 'RESET PASSWORD'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.forgotCodeEmails, ['person@example.com']);
    expect(repository.forgotVerifications, [
      const _CodeRequest('person@example.com', '654321'),
    ]);
    expect(repository.resetRequests, [
      const _ResetRequest('person@example.com', 'reset-token', 'newpass123'),
    ]);
    expect(find.text('Password reset successfully.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'LOG IN'), findsOneWidget);
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
    await _openProfileTab(tester);
    await _openEmailAuth(tester);
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Forgot Password ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'CONTINUE'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
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
      await _openProfileTab(tester);

      expect(find.text('Sign in / Sign up'), findsOneWidget);
      expect(find.text('Customer Support'), findsOneWidget);
      expect(find.text('Score'), findsOneWidget);
      expect(find.text('Share With Friends'), findsOneWidget);
      expect(find.text('Terms Of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Log Out'), findsNothing);
      await tester.scrollUntilVisible(find.text('Version 1.0.0'), 200);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.textContaining('+42'), findsNothing);

      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Delete Account'), findsOneWidget);
      await tester.tap(find.text('Delete Account'));
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

  testWidgets(
    'Profile never exposes the pending guest id because migration failures use a generic toast',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );

      await tester.pumpWidget(
        _testApp(
          repository,
          authController: _PendingMigrationAuthController.new,
        ),
      );
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      expect(find.textContaining('Pending guest:'), findsNothing);
      expect(find.textContaining('private-anonymous-id'), findsNothing);
    },
  );

  testWidgets('user profile navigates to account details', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _userSession(loginMethod: LoginMethod.google),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    expect(find.text('person@example.com'), findsWidgets);
    expect(find.text('ID: user-1'), findsOneWidget);
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('Customer Support'), findsOneWidget);
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Share With Friends'), findsOneWidget);
    expect(find.text('Terms Of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Sign in / Sign up'), findsNothing);
    await tester.tap(find.text('person@example.com').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-content-list')), findsOneWidget);
    expect(find.text('person@example.com'), findsWidgets);
    expect(find.text('user-1'), findsOneWidget);
    expect(find.text('GOOGLE'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Log Out'), findsOneWidget);
    expect(find.text('Delete Account'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Log Out'), 200);
    expect(find.text('Log Out'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Version 1.0.0'), 200);
    expect(find.text('Version 1.0.0'), findsOneWidget);
  });

  testWidgets(
    'Profile detail pages keep the Figma mobile canvas because account actions must not stretch on wide screens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1000);
      addTearDown(tester.view.reset);
      final repository = _WidgetAuthRepository(initialSession: _userSession());

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      expect(
        tester.getSize(find.byKey(const Key('profile-content-list'))).width,
        390,
      );

      await tester.tap(find.text('person@example.com').first);
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('account-content-list'))).width,
        390,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-back-button'))),
        const Size.square(38),
      );
      expect(find.text('Account'), findsNothing);
      expect(
        tester
            .widget<Text>(find.text('person@example.com').first)
            .style
            ?.fontFamily,
        'Fraunces',
      );

      await tester.tap(find.byKey(const Key('profile-back-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer Support'));
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.byKey(const Key('customer-support-content-list')))
            .width,
        390,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-back-button'))),
        const Size.square(38),
      );
      expect(
        tester.widget<Text>(find.text('Send Feedback')).style?.fontFamily,
        'Fraunces',
      );
    },
  );

  testWidgets(
    'Profile utility actions call native/share/browser services from their list entries',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );
      final profileActions = _WidgetProfileActions();

      await tester.pumpWidget(
        _testApp(repository, profileActions: profileActions),
      );
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      await tester.tap(find.text('Score'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share With Friends'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms Of Use'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(profileActions.calls, ['score', 'share', 'terms', 'privacy']);
    },
  );

  testWidgets(
    'Profile utility action failure shows the PRD generic failure toast',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );
      final profileActions = _WidgetProfileActions(
        failure: Exception('native share unavailable'),
      );

      await tester.pumpWidget(
        _testApp(repository, profileActions: profileActions),
      );
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      await tester.tap(find.text('Share With Friends'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to open this page. Please try again later.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'customer support submits signed-in feedback and returns to Profile',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 2000);
      addTearDown(tester.view.reset);
      final authRepository = _WidgetAuthRepository(
        initialSession: _userSession(),
      );
      final feedbackRepository = _WidgetFeedbackRepository();

      await tester.pumpWidget(
        _testApp(authRepository, feedbackRepository: feedbackRepository),
      );
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await tester.tap(find.text('Customer Support'));
      await tester.pumpAndSettle();

      expect(find.text('Send Feedback'), findsOneWidget);
      expect(find.text('Bug Report'), findsOneWidget);
      expect(find.text('Feature Request'), findsOneWidget);
      expect(find.text('Improvement'), findsOneWidget);
      expect(find.text('Other'), findsWidgets);
      expect(find.text('Subscription'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('feedback-message-field'))).height,
        178,
      );
      final emailField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('feedback-email-field')),
      );
      expect(emailField.controller?.text, 'person@example.com');

      await tester.tap(find.text('Bug Report'));
      await tester.tap(find.text('Search'));
      await tester.enterText(
        find.byKey(const ValueKey('feedback-message-field')),
        'Prices look stale.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'));
      await tester.pumpAndSettle();

      expect(feedbackRepository.submissions, [
        const _FeedbackSubmissionRecord(
          email: 'person@example.com',
          types: ['Bug Report'],
          functions: ['Search'],
          message: 'Prices look stale.',
        ),
      ]);
      expect(find.text('Feedback submitted. Thank you.'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    },
  );

  testWidgets('customer support validates guest feedback before submit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2000);
    addTearDown(tester.view.reset);
    final authRepository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );
    final feedbackRepository = _WidgetFeedbackRepository();

    await tester.pumpWidget(
      _testApp(authRepository, feedbackRepository: feedbackRepository),
    );
    await tester.pumpAndSettle();
    await _openProfileTab(tester);
    await tester.tap(find.text('Customer Support'));
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextFormField>(
      find.byKey(const ValueKey('feedback-email-field')),
    );
    expect(emailField.controller?.text, isEmpty);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your email.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-email-field')),
      'not-an-email',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-email-field')),
      'guest@example.com',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'SUBMIT FEEDBACK'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your feedback.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('feedback-message-field')),
      'x' * 1001,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Message must be 1000 characters or less.'),
      findsOneWidget,
    );
    final submitFinder = find
        .widgetWithText(FilledButton, 'SUBMIT FEEDBACK')
        .last;
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    final submitButton = tester.widget<FilledButton>(submitFinder);
    expect(submitButton.onPressed, isNull);
    expect(feedbackRepository.submissions, isEmpty);
  });

  testWidgets(
    'subscription copy is absent from Profile account and support surfaces',
    (tester) async {
      final guestRepository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
      );

      await tester.pumpWidget(_testApp(guestRepository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      _expectNoSubscriptionCopy();

      await tester.tap(find.text('Customer Support'));
      await tester.pumpAndSettle();
      _expectNoSubscriptionCopy();

      final userRepository = _WidgetAuthRepository(
        initialSession: _userSession(),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(_testApp(userRepository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      _expectNoSubscriptionCopy();

      await tester.tap(find.text('person@example.com').first);
      await tester.pumpAndSettle();
      _expectNoSubscriptionCopy();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer Support'));
      await tester.pumpAndSettle();
      _expectNoSubscriptionCopy();
    },
  );

  testWidgets(
    'logout from account creates a guest profile without previous anonymous',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _userSession(),
        createdAnonymousIds: ['anon-after-logout'],
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      await tester.tap(find.text('person@example.com').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Sign in / Sign up'), findsOneWidget);
      expect(repository._currentSession?.anonymousId, 'anon-after-logout');
      expect(find.text('Log Out'), findsNothing);
      expect(repository.logoutRequests, 1);
    },
  );

  testWidgets(
    'Profile exposes Refresh after auth startup fails because account entry must not spin forever',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
        initialSessionErrors: [Exception('offline')],
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);

      expect(find.text('No content available'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in / Sign up'), findsOneWidget);
      expect(find.text('No content available'), findsNothing);
    },
  );

  testWidgets(
    'offline logout from Profile keeps the user and shows the network toast',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _userSession(),
        logoutError: const AuthNetworkException(),
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No internet connection. Please check your network and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in / Sign up'), findsNothing);
      expect(repository._currentSession?.isUser, isTrue);
    },
  );

  testWidgets(
    'offline logout from Account keeps the user on account details',
    (tester) async {
      final repository = _WidgetAuthRepository(
        initialSession: _userSession(),
        logoutError: const AuthNetworkException(),
      );

      await tester.pumpWidget(_testApp(repository));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await tester.tap(find.text('person@example.com').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Log Out'), 200);
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-content-list')), findsOneWidget);
      expect(
        find.text(
          'No internet connection. Please check your network and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('person@example.com'), findsWidgets);
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
      await _openProfileTab(tester);

      expect(find.text('Sign in / Sign up'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).last, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.text('Sign in / Sign up'), findsOneWidget);
      expect(repository.deleteRequests, 1);
      expect(repository._currentSession?.anonymousId, 'anon-fresh');
    },
  );

  testWidgets('user delete returns to a guest profile', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _userSession(),
      createdAnonymousIds: ['anon-after-delete'],
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    await tester.tap(find.text('person@example.com').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sign in / Sign up'), findsOneWidget);
    expect(repository._currentSession?.anonymousId, 'anon-after-delete');
    expect(find.text('person@example.com'), findsNothing);
  });

  testWidgets('user delete failure keeps account details and shows failure', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _userSession(),
      deleteError: Exception('delete failed'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    await tester.tap(find.text('person@example.com').first);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to complete this action. Please try again later.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('account-content-list')), findsOneWidget);
    expect(find.text('person@example.com'), findsWidgets);
    expect(repository._currentSession?.userId, 'user-1');
  });

  testWidgets('guest delete failure keeps guest and shows failure', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-old'),
      deleteError: Exception('delete failed'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to complete this action. Please try again later.'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Sign in / Sign up'), findsOneWidget);
    expect(repository._currentSession?.anonymousId, 'anon-old');
  });
}

Future<void> _openProfileTab(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
}

void _expectNoSubscriptionCopy() {
  const subscriptionCopy = [
    'Upgrade to Pro',
    'Subscribe',
    'Subscription',
    'PRO',
    'Unlock All',
    'Go unlock',
    'Restore',
  ];

  for (final copy in subscriptionCopy) {
    expect(find.text(copy), findsNothing, reason: '$copy must stay hidden');
  }
}

Future<void> _openEmailAuth(WidgetTester tester) async {
  await _openAuthSheet(tester);
  await tester.tap(find.text('Continue with Email'));
  await tester.pumpAndSettle();
}

Future<void> _openAuthSheet(WidgetTester tester) async {
  await tester.tap(find.text('Sign in / Sign up'));
  await tester.pumpAndSettle();
  expect(find.text('Continue with Google'), findsOneWidget);
  expect(find.text('Continue with Apple'), findsOneWidget);
}

Future<void> _continueWithEmail(
  WidgetTester tester,
  String email, {
  String destinationLabel = 'Password',
}) async {
  await tester.enterText(find.byType(TextFormField), email);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'CONTINUE'));
  await tester.pumpAndSettle();
  expect(find.text(destinationLabel), findsOneWidget);
}

ProviderScope _testApp(
  _WidgetAuthRepository repository, {
  OAuthAuthorizer? authorizer,
  FeedbackRepository? feedbackRepository,
  ProfileActions? profileActions,
  AuthController Function()? authController,
}) {
  final onboardingStorage = InMemoryOnboardingStorage(completed: true);

  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      if (authController != null)
        authControllerProvider.overrideWith(authController),
      authDeviceIdProvider.overrideWithValue('widget-test-device'),
      onboardingRepositoryProvider.overrideWithValue(
        LocalOnboardingRepository(onboardingStorage),
      ),
      installedVersionReaderProvider.overrideWithValue(
        const _WidgetInstalledVersionReader(),
      ),
      if (authorizer != null)
        oauthAuthorizerProvider.overrideWithValue(authorizer),
      if (feedbackRepository != null)
        feedbackRepositoryProvider.overrideWithValue(feedbackRepository),
      if (profileActions != null)
        profileActionsProvider.overrideWithValue(profileActions),
    ],
    child: const KandoApp(),
  );
}

ProviderScope _testAuthSheetApp(
  _WidgetAuthRepository repository, {
  OAuthAuthorizer? authorizer,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      if (authorizer != null)
        oauthAuthorizerProvider.overrideWithValue(authorizer),
    ],
    child: MaterialApp(
      theme: buildKandoTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAuthSheet(context),
              child: const Text('Open auth'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PendingMigrationAuthController extends AuthController {
  @override
  AuthState build() {
    return AuthState.ready(
      session: _anonymousSession('anon-existing'),
      pendingMigrationAnonymousId: 'private-anonymous-id',
    );
  }
}

AuthSession _anonymousSession(String anonymousId) {
  return AuthSession(
    ownerType: OwnerType.anonymous,
    accessToken: '$anonymousId-access',
    refreshToken: '$anonymousId-refresh',
    anonymousId: anonymousId,
  );
}

AuthSession _userSession({
  String email = 'person@example.com',
  LoginMethod loginMethod = LoginMethod.email,
}) {
  return AuthSession(
    ownerType: OwnerType.user,
    accessToken: 'user-access',
    refreshToken: 'user-refresh',
    userId: 'user-1',
    email: email,
    loginMethod: loginMethod,
  );
}

class _WidgetAuthRepository implements AuthRepository {
  _WidgetAuthRepository({
    required AuthSession initialSession,
    List<String> createdAnonymousIds = const [],
    List<Exception> initialSessionErrors = const [],
    this.registerError,
    this.forgotCodeError,
    this.loginCompleter,
    this.googleCallbackError,
    this.logoutError,
    this.deleteError,
    this.emailRegistered = true,
  }) : _currentSession = initialSession,
       _createdAnonymousIds = [...createdAnonymousIds],
       _initialSessionErrors = [...initialSessionErrors];

  AuthSession? _currentSession;
  final List<String> _createdAnonymousIds;
  final List<Exception> _initialSessionErrors;
  final Exception? registerError;
  final Exception? forgotCodeError;
  final Completer<AuthSession>? loginCompleter;
  final Exception? googleCallbackError;
  final Exception? logoutError;
  final Exception? deleteError;
  final bool emailRegistered;
  var logoutRequests = 0;
  var deleteRequests = 0;
  final List<_LoginRequest> loginRequests = [];
  final List<String> registerCodeEmails = [];
  final List<_RegisterRequest> registerRequests = [];
  final List<_GoogleCallbackRequest> googleCallbackRequests = [];
  final List<_AppleCallbackRequest> appleCallbackRequests = [];
  final List<String> forgotCodeEmails = [];
  final List<_CodeRequest> forgotVerifications = [];
  final List<_ResetRequest> resetRequests = [];

  @override
  Future<AuthSession?> currentSessionFromStorage() async {
    if (_initialSessionErrors.isNotEmpty) {
      throw _initialSessionErrors.removeAt(0);
    }
    return _currentSession;
  }

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
      final error = logoutError;
      if (error != null) {
        throw error;
      }
      logoutRequests++;
      _currentSession = null;
    }
  }

  @override
  Future<void> clearAnonymousSession() async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    deleteRequests++;
    if (_currentSession?.isAnonymous ?? false) {
      _currentSession = null;
    }
  }

  @override
  Future<void> deleteCurrentAccount(AuthSession session) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    deleteRequests++;
    if (identical(_currentSession, session)) {
      _currentSession = null;
    }
  }

  @override
  Future<void> sendRegisterCode(String email) async {
    registerCodeEmails.add(email);
    if (emailRegistered) {
      throw const AuthApiException(
        'Email is already registered.',
        code: 'CONFLICT',
      );
    }
  }

  @override
  Future<void> verifyRegisterCode({
    required String email,
    required String code,
  }) async {
    final error = registerError;
    if (error != null) throw error;
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
  Future<AuthSession> googleCallback({
    required String code,
    required String redirectUri,
    String? anonymousId,
  }) async {
    googleCallbackRequests.add(
      _GoogleCallbackRequest(
        code: code,
        redirectUri: redirectUri,
        anonymousId: anonymousId,
      ),
    );
    final error = googleCallbackError;
    if (error != null) {
      throw error;
    }
    return _userSession(email: 'flutter.google@example.com');
  }

  @override
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  }) async {
    appleCallbackRequests.add(
      _AppleCallbackRequest(
        code: code,
        idToken: idToken,
        anonymousId: anonymousId,
      ),
    );
    return _userSession(email: 'flutter.apple@example.com');
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

class _WidgetOAuthAuthorizer implements OAuthAuthorizer {
  _WidgetOAuthAuthorizer({this.result, this.error});

  final OAuthAuthorizationResult? result;
  final Exception? error;
  final List<OAuthProvider> requests = [];

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) async {
    requests.add(provider);
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return result;
  }
}

class _WidgetFeedbackRepository implements FeedbackRepository {
  final List<_FeedbackSubmissionRecord> submissions = [];

  @override
  Future<FeedbackReceipt> submit(
    AuthSession session,
    FeedbackSubmission submission,
  ) async {
    submissions.add(
      _FeedbackSubmissionRecord(
        email: submission.email,
        types: submission.types,
        functions: submission.functions,
        message: submission.message,
      ),
    );
    return const FeedbackReceipt(id: 'feedback-1');
  }
}

class _WidgetInstalledVersionReader implements InstalledVersionReader {
  const _WidgetInstalledVersionReader();

  @override
  Future<String> currentVersion() async => '1.0.0+42';
}

class _WidgetProfileActions implements ProfileActions {
  _WidgetProfileActions({this.failure});

  final Exception? failure;
  final List<String> calls = [];

  @override
  Future<void> openPrivacy() => _record('privacy');

  @override
  Future<void> openTerms() => _record('terms');

  @override
  Future<void> requestScore() => _record('score');

  @override
  Future<void> shareWithFriends() => _record('share');

  Future<void> _record(String call) async {
    calls.add(call);
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
  }
}

class _FeedbackSubmissionRecord {
  const _FeedbackSubmissionRecord({
    required this.email,
    required this.types,
    required this.functions,
    required this.message,
  });

  final String email;
  final List<String> types;
  final List<String> functions;
  final String message;

  @override
  bool operator ==(Object other) {
    return other is _FeedbackSubmissionRecord &&
        other.email == email &&
        _listEquals(other.types, types) &&
        _listEquals(other.functions, functions) &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(
    email,
    Object.hashAll(types),
    Object.hashAll(functions),
    message,
  );
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
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

class _GoogleCallbackRequest {
  const _GoogleCallbackRequest({
    required this.code,
    required this.redirectUri,
    required this.anonymousId,
  });

  final String code;
  final String redirectUri;
  final String? anonymousId;

  @override
  bool operator ==(Object other) {
    return other is _GoogleCallbackRequest &&
        other.code == code &&
        other.redirectUri == redirectUri &&
        other.anonymousId == anonymousId;
  }

  @override
  int get hashCode => Object.hash(code, redirectUri, anonymousId);
}

class _AppleCallbackRequest {
  const _AppleCallbackRequest({
    required this.code,
    required this.idToken,
    required this.anonymousId,
  });

  final String code;
  final String idToken;
  final String? anonymousId;

  @override
  bool operator ==(Object other) {
    return other is _AppleCallbackRequest &&
        other.code == code &&
        other.idToken == idToken &&
        other.anonymousId == anonymousId;
  }

  @override
  int get hashCode => Object.hash(code, idToken, anonymousId);
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

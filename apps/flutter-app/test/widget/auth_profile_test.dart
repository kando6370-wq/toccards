import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/app/theme.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/oauth_authorizer.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/ui/auth_sheet.dart';
import 'package:kando_app/features/auth/ui/email_auth_pages.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/onboarding/onboarding_controller.dart';
import 'package:kando_app/features/onboarding/onboarding_repository.dart';
import 'package:kando_app/features/profile/customer_support_page.dart';
import 'package:kando_app/features/profile/feedback_repository.dart';
import 'package:kando_app/features/profile/profile_actions.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/features/subscription/subscription_entitlement_cache.dart';
import 'package:kando_app/features/subscription/subscription_page.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';

import '../support/in_memory_onboarding_storage.dart';
import '../support/mock_home_repository.dart';

void main() {
  testWidgets('email auth validates input before enabling submit', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();

    final continueButton = find.widgetWithText(FilledButton, 'CONTINUE');
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
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
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      expect(
        find.text('Please enter a valid email address.'),
        findsOneWidget,
        reason: '$email must be rejected by PRD email validation',
      );
    }

    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.pump();

    expect(find.text('Please enter a valid email address.'), findsNothing);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
  });

  testWidgets('email continue shows loading while checking registration', (
    tester,
  ) async {
    final registerCodeCompleter = Completer<void>();
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      registerCodeCompleter: registerCodeCompleter,
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'person@example.com');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'CONTINUE'));
    await tester.pump();

    final loadingButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Loading...'),
    );
    expect(loadingButton.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.registerCodeEmails, ['person@example.com']);

    registerCodeCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('short login password blocks submit', (tester) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(tester, 'person@example.com');

    await tester.enterText(find.byType(TextFormField), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'SIGN IN'));
    await tester.pumpAndSettle();

    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(repository.loginRequests, isEmpty);
  });

  testWidgets('successful email login shows the Figma welcome back modal', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(tester, ' PERSON@example.com ');

    final passwordField = find.byType(TextFormField);
    await tester.enterText(passwordField, 'password123');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).textInputAction,
      TextInputAction.go,
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(repository.loginRequests, [
      const _LoginRequest('person@example.com', 'password123'),
    ]);
    expect(find.byKey(const Key('email-auth-page')), findsNothing);
    expect(find.byKey(const Key('auth-sheet-panel')), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Let’s collect the cards.'), findsOneWidget);
    final successToast = find.byKey(const Key('auth-success-toast'));
    expect(successToast, findsOneWidget);
    expect(tester.getSize(successToast), const Size(260, 122));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('google auth returns home with the current guest migrated', (
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
        idToken: 'mock-google:flutter-google-user:flutter.google@example.com',
        anonymousId: 'anon-existing',
      ),
    ]);
    expect(find.byKey(const Key('home-normal-content')), findsOneWidget);
  });

  testWidgets(
    'google auth shows full-screen loading while callback is pending',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final authorizationCompleter = Completer<OAuthAuthorizationResult?>();
      final callbackCompleter = Completer<AuthSession>();
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
        googleCallbackCompleter: callbackCompleter,
      );
      final authorizer = _WidgetOAuthAuthorizer(
        resultFuture: authorizationCompleter.future,
      );

      await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await _openAuthSheet(tester);
      await tester.tap(find.text('Continue with Google'));
      await tester.pump();

      final loadingOverlay = find.byKey(
        const Key('auth-oauth-loading-overlay'),
      );
      expect(authorizer.requests, [OAuthProvider.google]);
      expect(loadingOverlay, findsNothing);
      expect(repository.googleCallbackRequests, isEmpty);

      authorizationCompleter.complete(
        const OAuthAuthorizationResult.google(
          code: 'mock-google:flutter-google-user:flutter.google@example.com',
        ),
      );
      await tester.pump();

      expect(loadingOverlay, findsOneWidget);
      expect(tester.getSize(loadingOverlay), const Size(390, 844));
      expect(find.text('Signing in with Google'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.googleCallbackRequests, [
        const _GoogleCallbackRequest(
          idToken: 'mock-google:flutter-google-user:flutter.google@example.com',
          anonymousId: 'anon-existing',
        ),
      ]);

      callbackCompleter.complete(
        _userSession(email: 'flutter.google@example.com'),
      );
      await tester.pumpAndSettle();

      expect(loadingOverlay, findsNothing);
      expect(find.byKey(const Key('home-normal-content')), findsOneWidget);
    },
  );

  testWidgets('apple auth returns home with the current guest migrated', (
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
    expect(find.byKey(const Key('home-normal-content')), findsOneWidget);
  });

  testWidgets(
    'apple auth shows full-screen loading while callback is pending',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final authorizationCompleter = Completer<OAuthAuthorizationResult?>();
      final callbackCompleter = Completer<AuthSession>();
      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
        appleCallbackCompleter: callbackCompleter,
      );
      final authorizer = _WidgetOAuthAuthorizer(
        resultFuture: authorizationCompleter.future,
      );

      await tester.pumpWidget(_testApp(repository, authorizer: authorizer));
      await tester.pumpAndSettle();
      await _openProfileTab(tester);
      await _openAuthSheet(tester);
      await tester.tap(find.text('Continue with Apple'));
      await tester.pump();

      final loadingOverlay = find.byKey(
        const Key('auth-oauth-loading-overlay'),
      );
      expect(authorizer.requests, [OAuthProvider.apple]);
      expect(loadingOverlay, findsNothing);
      expect(repository.appleCallbackRequests, isEmpty);

      authorizationCompleter.complete(
        const OAuthAuthorizationResult.apple(
          code: 'apple-auth-code',
          idToken: 'mock-apple:flutter-apple-user:flutter.apple@example.com',
        ),
      );
      await tester.pump();

      expect(loadingOverlay, findsOneWidget);
      expect(tester.getSize(loadingOverlay), const Size(390, 844));
      expect(find.text('Signing in with Apple'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.appleCallbackRequests, [
        const _AppleCallbackRequest(
          code: 'apple-auth-code',
          idToken: 'mock-apple:flutter-apple-user:flutter.apple@example.com',
          anonymousId: 'anon-existing',
        ),
      ]);

      callbackCompleter.complete(
        _userSession(email: 'flutter.apple@example.com'),
      );
      await tester.pumpAndSettle();

      expect(loadingOverlay, findsNothing);
      expect(find.byKey(const Key('home-normal-content')), findsOneWidget);
    },
  );

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
      final agreementCopy = tester.widget<Text>(
        find.byKey(const Key('auth-agreement-copy')),
      );
      final agreementLinks = tester.widget<RichText>(
        find.byKey(const Key('auth-agreement-links')),
      );
      final agreementText =
          '${agreementCopy.data} ${agreementLinks.text.toPlainText()}';
      expect(
        agreementText,
        'By continuing, you agree to our Terms of Use and Privacy Policy',
      );
      expect(agreementText, contains('Terms of Use'));
      expect(agreementText, contains('Privacy Policy'));

      final spans = (agreementLinks.text as TextSpan).children!
          .cast<TextSpan>();
      (spans[0].recognizer! as TapGestureRecognizer).onTap!();
      await tester.pumpAndSettle();
      (spans[2].recognizer! as TapGestureRecognizer).onTap!();
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
      expect(
        tester.getSize(find.byKey(const Key('auth-home-indicator'))),
        const Size(390, 25.154),
      );

      await tester.tap(closeButton);
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);
      expect(repository.loginRequests, isEmpty);
      expect(repository.googleCallbackRequests, isEmpty);
      expect(repository.appleCallbackRequests, isEmpty);
    },
  );

  testWidgets('normal auth options render sharp native controls', (
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
    expect(find.byKey(const Key('auth-options-close-canvas')), findsOneWidget);
    expect(find.byKey(const Key('auth-home-indicator')), findsOneWidget);
    expect(find.byKey(const Key('auth-google-option')), findsOneWidget);
    expect(find.byKey(const Key('auth-apple-option')), findsOneWidget);
    expect(find.byKey(const Key('auth-email-option')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('auth-google-option'))),
      const Size(342, 56),
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
          find.byKey(const Key('auth-agreement-links')),
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

  testWidgets('oauth failure renders sharp native controls', (tester) async {
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
    expect(find.byKey(const Key('auth-home-indicator')), findsOneWidget);
    expect(find.byKey(const Key('auth-oauth-warning')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('auth-email-option'))),
      const Size(342, 56),
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

  testWidgets('email auth back returns to the auth options sheet', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('email-auth-back')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('email-auth-page')), findsNothing);
    expect(find.byKey(const Key('auth-sheet-panel')), findsOneWidget);
    expect(find.text('Continue with Email'), findsOneWidget);
  });

  testWidgets(
    'email auth keeps back action at one fixed height across steps because navigation must not jump',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final repository = _WidgetAuthRepository(
        initialSession: _anonymousSession('anon-existing'),
        emailRegistered: false,
      );

      await tester.pumpWidget(_testAuthSheetApp(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open auth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Email'));
      await tester.pumpAndSettle();

      final backButton = find.byKey(const Key('email-auth-back'));
      final emailPageBackY = tester.getTopLeft(backButton).dy;

      await _continueWithEmail(
        tester,
        'new@example.com',
        destinationLabel: 'Verification Code',
      );

      expect(tester.getTopLeft(backButton).dy, emailPageBackY);
    },
  );

  testWidgets('email auth back steps from password entry to email entry', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(tester, 'person@example.com');

    await tester.tap(find.byKey(const Key('email-auth-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email-auth-page')), findsOneWidget);
    expect(find.text('Continue With Email'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'CONTINUE'), findsOneWidget);
  });

  testWidgets('login password field keeps focus while keyboard resizes page', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);

    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(tester, 'person@example.com');

    final passwordField = find.byType(TextFormField);
    await tester.tap(passwordField);
    await tester.pump();

    var editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await tester.pumpAndSettle();

    editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.focusNode.hasFocus, isTrue);

    await tester.enterText(passwordField, 'password123');
    await tester.pump();

    editableText = tester.widget<EditableText>(find.byType(EditableText));
    expect(editableText.controller.text, 'password123');
    expect(editableText.focusNode.hasFocus, isTrue);
  });

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
        idToken: 'mock-google:flutter-google-user:flutter.google@example.com',
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
      await tester.tap(find.widgetWithText(FilledButton, 'SIGN IN'));
      await tester.tap(find.widgetWithText(FilledButton, 'SIGN IN'));
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

  testWidgets('register password page matches figma validation states', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '123456',
    );
    await tester.pumpAndSettle();

    expect(find.text('Set Password'), findsOneWidget);
    expect(find.text('Set New Password'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Create Account'), findsOneWidget);
    final emptyCreateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create Account'),
    );
    expect(emptyCreateButton.onPressed, isNull);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    final fields = find.byType(TextFormField);
    final editableFields = find.byType(EditableText);
    expect(find.text('Your password'), findsOneWidget);
    expect(find.text('Confirm your password'), findsOneWidget);
    expect(
      tester.widget<EditableText>(editableFields.at(0)).obscureText,
      isTrue,
    );
    expect(
      tester.widget<EditableText>(editableFields.at(1)).obscureText,
      isTrue,
    );

    await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(
      tester.widget<EditableText>(editableFields.at(0)).obscureText,
      isFalse,
    );
    expect(
      tester.widget<EditableText>(editableFields.at(1)).obscureText,
      isTrue,
    );

    await tester.enterText(fields.at(0), 'short');
    await tester.enterText(fields.at(1), 'password456');
    await tester.pump();

    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('Inconsistent with last input'), findsOneWidget);
    final invalidCreateButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create Account'),
    );
    expect(invalidCreateButton.onPressed, isNull);
    expect(repository.registerRequests, isEmpty);
  });

  testWidgets('register code page starts the resend countdown after sending', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );

    final emailField = tester.widget<TextFormField>(
      find.byKey(const Key('register-code-email-input')),
    );
    expect(emailField.controller?.text, 'person@example.com');
    final toast = find.byKey(const Key('code-sent-toast'));
    expect(toast, findsOneWidget);
    expect(tester.getSize(toast), const Size(260, 122));
    expect(find.text('Code sent'), findsOneWidget);
    expect(
      find.text('Check your email to continue creating your account.'),
      findsOneWidget,
    );
    final toastTitle = tester.widget<Text>(find.text('Code sent'));
    expect(toastTitle.textAlign, TextAlign.center);
    expect(toastTitle.style?.color, const Color(0xFFF1FE70));
    expect(toastTitle.style?.fontSize, 24);
    expect(toastTitle.style?.decoration, TextDecoration.none);

    expect(find.text("Didn't get the code? Check your spam"), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Retry in 60 seconds'),
      findsOneWidget,
    );
  });

  testWidgets('register automatically verifies after all six code digits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
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
    expect(repository.registerCodeVerifications, isEmpty);

    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '123456',
    );
    await tester.pumpAndSettle();

    expect(find.text('Set Password'), findsOneWidget);
    expect(repository.registerCodeVerifications, [
      const _CodeRequest('person@example.com', '123456'),
    ]);
  });

  testWidgets('register code back returns directly to auth options', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );
    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'new@example.com',
      destinationLabel: 'Verification Code',
    );

    await tester.tap(find.byKey(const Key('email-auth-back')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('email-auth-page')), findsNothing);
    expect(find.text('Continue with Email'), findsOneWidget);
  });

  testWidgets('changing register email rechecks account before sending', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
      registeredEmails: const {'member@example.com'},
    );
    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'new@example.com',
      destinationLabel: 'Verification Code',
    );

    await tester.enterText(
      find.byKey(const Key('register-code-email-input')),
      'member@example.com',
    );
    await tester.pump();
    expect(
      find.widgetWithText(FilledButton, 'Get verification code'),
      findsOneWidget,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'SIGN IN'), findsOneWidget);
    expect(repository.registerCodeEmails, [
      'new@example.com',
      'member@example.com',
    ]);
  });

  testWidgets('changing to an unregistered email restarts resend countdown', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );
    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'first@example.com',
      destinationLabel: 'Verification Code',
    );

    await tester.enterText(
      find.byKey(const Key('register-code-email-input')),
      'second@example.com',
    );
    await tester.pump();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pump();

    expect(find.byKey(const Key('register-code-email-input')), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Retry in 60 seconds'),
      findsOneWidget,
    );
    expect(repository.registerCodeEmails, [
      'first@example.com',
      'second@example.com',
    ]);
  });

  testWidgets('successful register passes current anonymous id', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '123456',
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'password123');
    await tester.enterText(fields.at(1), 'password123');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
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
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Let’s collect the cards.'), findsOneWidget);
    expect(find.byKey(const Key('kando-modal-frame')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byKey(const Key('email-auth-page')), findsNothing);
  });

  testWidgets('register code error resends a fresh empty code after cooldown', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
      registerError: Exception('invalid_verification_code'),
      emailRegistered: false,
    );

    await tester.pumpWidget(_testAuthSheetApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open auth'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Email'));
    await tester.pumpAndSettle();
    await _continueWithEmail(
      tester,
      'person@example.com',
      destinationLabel: 'Verification Code',
    );
    await tester.enterText(
      find.byKey(const Key('verification-code-input')),
      '123456',
    );
    await tester.pumpAndSettle();

    final errorText = tester.widget<Text>(
      find.text('Incorrect verification code'),
    );
    expect(errorText.maxLines, 1);
    expect(errorText.softWrap, isFalse);
    expect(find.text('Signed in'), findsNothing);
    final firstBox = tester.widget<Container>(
      find.byKey(const Key('verification-code-box-0')),
    );
    final decoration = firstBox.decoration! as BoxDecoration;
    expect(decoration.border, Border.all(color: const Color(0xFFFF8787)));
    expect(
      find.widgetWithText(FilledButton, 'Retry in 60 seconds'),
      findsOneWidget,
    );
    expect(repository.registerCodeVerifications, [
      const _CodeRequest('person@example.com', '123456'),
    ]);

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pump();

    final codeInput = tester.widget<TextFormField>(
      find.byKey(const Key('verification-code-input')),
    );
    expect(codeInput.controller?.text, isEmpty);
    expect(find.text('Incorrect verification code'), findsNothing);
    expect(repository.registerCodeEmails, [
      'person@example.com',
      'person@example.com',
    ]);
  });

  testWidgets('forgot password reset success returns to login path', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testEmailAuthPageApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open email auth'));
    await tester.pumpAndSettle();
    await _continueWithEmail(tester, 'person@example.com');
    await tester.tap(find.text('Forgot Password ?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' PERSON@example.com ');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'newpass123');
    await tester.enterText(fields.at(1), 'newpass123');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
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
    expect(find.text('Let’s collect the cards'), findsOneWidget);
    expect(
      find.byKey(const Key('password-reset-success-icon')),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    final successToast = find.byKey(const Key('password-reset-success-toast'));
    expect(successToast, findsOneWidget);
    expect(tester.getSize(successToast), const Size(260, 220));
    expect(find.widgetWithText(FilledButton, 'SIGN IN'), findsOneWidget);
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
    await tester.tap(
      find.widgetWithText(FilledButton, 'Get verification code'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '654321');
    await tester.pumpAndSettle();

    expect(find.text('Code expired. Request a new one'), findsOneWidget);
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
      await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
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
    await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
    expect(find.text('Terms Of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Sign in / Sign up'), findsNothing);
    await tester.fling(
      find.byKey(const Key('profile-content-list')),
      const Offset(0, 1200),
      2000,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('person@example.com').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-content-list')), findsOneWidget);
    expect(find.byKey(const Key('account-pull-to-refresh')), findsOneWidget);
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
    'Profile content uses the standard top spacing below the safe area',
    (tester) async {
      final repository = _WidgetAuthRepository(initialSession: _userSession());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(repository),
            installedVersionReaderProvider.overrideWithValue(
              const _WidgetInstalledVersionReader(),
            ),
          ],
          child: MaterialApp(
            theme: buildKandoTheme(),
            home: const ProfilePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(
        find.byKey(const Key('profile-content-list')),
      );

      expect(
        listView.padding,
        const EdgeInsets.fromLTRB(20, KandoLayout.mainTabTopPadding, 20, 96),
      );
      expect(find.byIcon(Icons.shield_outlined), findsNothing);
      await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
      final privacyIcon = tester.widget<SvgPicture>(
        find.byKey(const Key('profile-privacy-policy-icon')),
      );
      expect(
        (privacyIcon.bytesLoader as SvgAssetLoader).assetName,
        'assets/profile/privacy_policy.svg',
      );

      for (final label in const [
        'Customer Support',
        'Score',
        'Share With Friends',
        'Terms Of Use',
        'Privacy Policy',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200);
        final row = tester.widget<InkWell>(
          find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
        );
        expect(
          row.overlayColor?.resolve({WidgetState.pressed}),
          const Color(0x14F0FE6F),
        );
      }

      final menuMaterials = tester.widgetList<Material>(
        find.ancestor(
          of: find.text('Customer Support'),
          matching: find.byType(Material),
        ),
      );
      expect(
        menuMaterials.any(
          (material) => material.type == MaterialType.transparency,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'Profile tab fills wide screens while detail pages keep the mobile canvas',
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
        800,
      );
      expect(
        tester.getSize(find.byKey(const Key('profile-upgrade-banner'))).width,
        760,
      );
      expect(find.byKey(const Key('profile-pull-to-refresh')), findsOneWidget);

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

      await tester.ensureVisible(find.text('Score'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Score'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Share With Friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share With Friends'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Terms Of Use'), 200);
      await tester.drag(
        find.byKey(const Key('profile-content-list')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Terms Of Use'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Privacy Policy'), 200);
      await tester.tap(find.text('Privacy Policy'));
      await tester.pumpAndSettle();

      expect(profileActions.calls, ['score', 'share', 'terms', 'privacy']);
      expect(profileActions.sharePositionOrigin, isNotNull);
      expect(profileActions.sharePositionOrigin?.isEmpty, isFalse);
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

      await tester.ensureVisible(find.text('Share With Friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share With Friends'));
      await tester.pumpAndSettle();

      expect(
        find.text('Unable to open this page. Please try again later.'),
        findsOneWidget,
      );
      await _dismissTopToast(tester);
    },
  );

  testWidgets('customer support field labels use consistent typography', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2000);
    addTearDown(tester.view.reset);
    final authRepository = _WidgetAuthRepository(
      initialSession: _userSession(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(authRepository)],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const CustomerSupportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final emailLabel = tester.widget<Text>(find.text('Email Address'));
    final messageLabel = tester.widget<Text>(find.text('Your Message'));
    expect(emailLabel.style?.fontSize, 14);
    expect(messageLabel.style?.fontSize, emailLabel.style?.fontSize);

    for (final fieldKey in const [
      ValueKey('feedback-email-field'),
      ValueKey('feedback-message-field'),
    ]) {
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(fieldKey),
          matching: find.byType(TextField),
        ),
      );
      final border = field.decoration?.enabledBorder as OutlineInputBorder;
      expect(border.borderSide.color, KandoColors.border);
      expect(border.borderSide.width, 1);
      expect(border.borderRadius, BorderRadius.circular(8));
      expect(field.decoration?.contentPadding, const EdgeInsets.all(16));
    }

    expect(find.byIcon(Icons.send_outlined), findsNothing);
    final submitIcon = tester.widget<SvgPicture>(
      find.byKey(const Key('feedback-submit-icon')),
    );
    expect(submitIcon.width, 24);
    expect(submitIcon.height, 24);
    expect(
      (submitIcon.bytesLoader as SvgAssetLoader).assetName,
      'assets/profile/send_feedback.svg',
    );

    for (final fieldKey in const [
      ValueKey('feedback-email-field'),
      ValueKey('feedback-message-field'),
    ]) {
      final fieldFinder = find.byKey(fieldKey);
      final editableText = tester.widget<EditableText>(
        find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
      );

      await tester.tap(fieldFinder);
      await tester.pump();
      expect(editableText.focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Send Feedback'));
      await tester.pump();
      expect(editableText.focusNode.hasFocus, isFalse);
    }
  });

  testWidgets('customer support keeps Submit fixed while form scrolls', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final authRepository = _WidgetAuthRepository(
      initialSession: _userSession(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(authRepository)],
        child: MaterialApp(
          theme: buildKandoTheme(),
          home: const CustomerSupportPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('feedback-submit-button'));
    final contentList = find.byKey(const Key('customer-support-content-list'));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: contentList, matching: find.byType(Scrollable)),
    );
    final submitBeforeScroll = tester.getRect(submit);
    final scrollOffsetBefore = scrollable.position.pixels;

    await tester.drag(contentList, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getRect(submit), submitBeforeScroll);
    expect(scrollable.position.pixels, greaterThan(scrollOffsetBefore));
  });

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
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const Key('kando-top-toast')),
                matching: find.byIcon(Icons.check_rounded),
              ),
            )
            .color,
        KandoColors.gain,
      );
      expect(
        find.byKey(const Key('profile-premium-page-title')),
        findsOneWidget,
      );
      await _dismissTopToast(tester);
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

  testWidgets('unsubscribed Profile banner opens the Subscription sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final repository = _WidgetAuthRepository(
      initialSession: _anonymousSession('anon-existing'),
    );

    await tester.pumpWidget(_testApp(repository));
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    expect(find.text('Upgrade Now'), findsOneWidget);
    final bannerSize = tester.getSize(
      find.byKey(const Key('profile-upgrade-banner')),
    );
    expect(bannerSize, const Size(350, 152));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await expectLater(
      find.byKey(const Key('profile-upgrade-banner')),
      matchesGoldenFile(
        '../goldens/rendered/'
        'figma_profile_upgrade_banner_2210_17750_350x152.png',
      ),
    );

    tester.view.physicalSize = const Size(430, 932);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('profile-upgrade-banner'))),
      const Size(390, 152),
    );
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Upgrade Now'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SubscriptionPage>(find.byType(SubscriptionPage)).sheet,
      isTrue,
    );
    expect(find.text('Choose Your Plan'), findsOneWidget);
    expect(find.text('Unlimited Card Scanning'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    final purchaseButton = find.byKey(
      const Key('subscription-purchase-button'),
    );
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(purchaseButton, findsWidgets);
  });

  testWidgets('subscribed profile exposes restore without upgrade banner', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(initialSession: _userSession());

    await tester.pumpWidget(
      _testApp(
        repository,
        subscriptionController: _ProSubscriptionController.new,
      ),
    );
    await tester.pumpAndSettle();
    await _openProfileTab(tester);

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('PRO'), findsNothing);
    expect(find.text('Upgrade to Pro'), findsNothing);
    expect(find.text('Upgrade Now'), findsNothing);
    expect(find.text('SUBSCRIBE'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('person@example.com').first);
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsNothing);
  });

  testWidgets('Profile restore blocks page actions and back navigation', (
    tester,
  ) async {
    final repository = _WidgetAuthRepository(initialSession: _userSession());

    await tester.pumpWidget(
      _testApp(
        repository,
        subscriptionController: _RestoringSubscriptionController.new,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester
          .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
          .any((widget) => widget.absorbing),
      isTrue,
    );
    expect(
      tester
          .widgetList<PopScope>(find.byType(PopScope))
          .any((widget) => !widget.canPop),
      isTrue,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Customer Support'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Customer Support'), findsOneWidget);
  });

  testWidgets(
    'subscription success confirms the Pro benefits unlocked by the purchase',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildKandoTheme(),
          home: const SubscriptionSuccessPage(),
        ),
      );

      expect(find.text("You're Premium!"), findsOneWidget);
      expect(
        find.text('Your premium features are now unlocked.'),
        findsOneWidget,
      );
      expect(find.text('Unlimited Card Scanning'), findsOneWidget);
      expect(find.text('Unlimited Portfolio Folders'), findsOneWidget);
      expect(find.text('Extended Price History'), findsOneWidget);
      expect(find.text('Track Portfolio Performance'), findsOneWidget);
      expect(find.text('PREMIUM ACTIVE'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('subscription-success-badge'))),
        const Size(208, 208),
      );
      expect(
        find.byKey(const Key('subscription-success-continue')),
        findsOneWidget,
      );
      expect(find.text('START EXPLORING'), findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFF070905),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('subscription-success-benefit-0-reveal')),
        ),
        const Size(350, 58),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('subscription-success-button-reveal')),
        ),
        const Size(350, 56),
      );
    },
  );

  testWidgets(
    'subscription success follows Figma 2090:17166 geometry while wider phones keep 20px margins',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 59);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(
        _subscriptionGoldenApp(const SubscriptionSuccessPage()),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('subscription-success-premium-active')),
            )
            .dy,
        59,
      );
      expect(
        tester
            .getTopLeft(find.byKey(const Key('subscription-success-badge')))
            .dy,
        136,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('subscription-success-title-reveal')),
            )
            .dy,
        358,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('subscription-success-benefit-0-reveal')),
            )
            .dy,
        454,
      );
      expect(
        tester
            .getTopLeft(
              find.byKey(const Key('subscription-success-button-reveal')),
            )
            .dy,
        755,
      );

      tester.view.physicalSize = const Size(430, 932);
      await tester.pump();
      expect(
        tester
            .getSize(
              find.byKey(const Key('subscription-success-benefit-0-reveal')),
            )
            .width,
        390,
      );
      expect(
        tester
            .getSize(
              find.byKey(const Key('subscription-success-button-reveal')),
            )
            .width,
        390,
      );
    },
  );

  testWidgets(
    'subscription success reveals once and stays complete because purchase confirmation must not replay',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildKandoTheme(),
          home: const SubscriptionSuccessPage(),
        ),
      );

      double opacityFor(Key key) {
        final keyed = find.byKey(key);
        final widget = tester.widget(keyed);
        return (widget is Opacity
                ? widget
                : tester.widget<Opacity>(
                    find
                        .descendant(of: keyed, matching: find.byType(Opacity))
                        .first,
                  ))
            .opacity;
      }

      expect(opacityFor(const Key('subscription-success-title-reveal')), 0);
      expect(opacityFor(const Key('subscription-success-benefit-0-reveal')), 0);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(opacityFor(const Key('subscription-success-title-reveal')), 1);
      expect(
        opacityFor(const Key('subscription-success-benefit-0-reveal')),
        greaterThan(0),
      );

      await tester.pump(const Duration(milliseconds: 800));
      expect(opacityFor(const Key('subscription-success-benefit-0-reveal')), 1);
      expect(opacityFor(const Key('subscription-success-benefit-2-reveal')), 1);
      expect(
        opacityFor(const Key('subscription-success-button-reveal')),
        greaterThan(0),
      );

      await tester.pump(const Duration(milliseconds: 550));
      expect(opacityFor(const Key('subscription-success-title-reveal')), 1);
      expect(opacityFor(const Key('subscription-success-benefit-0-reveal')), 1);
      expect(opacityFor(const Key('subscription-success-benefit-2-reveal')), 1);
      expect(opacityFor(const Key('subscription-success-button-reveal')), 1);
    },
  );

  testWidgets('subscription success follows the Figma motion timeline once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKandoTheme(),
        home: const SubscriptionSuccessPage(),
      ),
    );

    double opacityFor(Key key) {
      final keyed = find.byKey(key);
      final widget = tester.widget(keyed);
      return (widget is Opacity
              ? widget
              : tester.widget<Opacity>(
                  find
                      .descendant(of: keyed, matching: find.byType(Opacity))
                      .first,
                ))
          .opacity;
    }

    const outerGlow = Key('subscription-success-glow-outer');
    const medallion = Key('subscription-success-medallion');
    const trophy = Key('subscription-success-trophy');
    const confetti = Key('subscription-success-confetti-0');
    const checkmark = Key('subscription-success-checkmark-0');
    expect(opacityFor(outerGlow), 0);
    expect(opacityFor(medallion), 0);
    expect(opacityFor(trophy), 0);
    expect(opacityFor(confetti), 0);
    expect(opacityFor(checkmark), 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(opacityFor(outerGlow), greaterThan(0));
    expect(opacityFor(medallion), 1);
    expect(opacityFor(trophy), 1);
    expect(opacityFor(confetti), greaterThan(0));
    expect(opacityFor(const Key('subscription-success-title-reveal')), 0);

    await tester.pump(const Duration(milliseconds: 2050));
    expect(opacityFor(outerGlow), 0);
    expect(opacityFor(confetti), 0);
    expect(opacityFor(checkmark), 1);
    expect(opacityFor(const Key('subscription-success-title-reveal')), 1);
    expect(opacityFor(const Key('subscription-success-button-reveal')), 1);

    await tester.pump(const Duration(milliseconds: 2350));
    expect(opacityFor(outerGlow), 0);
    expect(opacityFor(confetti), 0);
    expect(opacityFor(checkmark), 1);
    expect(opacityFor(const Key('subscription-success-button-reveal')), 1);
  });

  testWidgets('subscription success matches the Figma 300ms motion frame', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      _subscriptionGoldenApp(
        const SubscriptionSuccessPage(),
        disableAnimations: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byKey(const Key('subscription-golden-boundary')),
      matchesGoldenFile(
        'goldens/rendered/figma_subscription_success_motion_300ms_390x844.png',
      ),
    );
  });

  for (final goldenCase in [
    (
      name: 'bottom sheet',
      file: 'figma_subscription_sheet_1651_9467_390x844.png',
      child: const SubscriptionPage(sheet: true),
    ),
    (
      name: 'success page',
      file: 'figma_subscription_success_2090_17166_390x844.png',
      child: const SubscriptionSuccessPage(),
    ),
  ]) {
    testWidgets(
      'v1.1 PRD subscription ${goldenCase.name} keeps the 390x844 baseline',
      (tester) async {
        final overridesPlatform = goldenCase.name == 'bottom sheet';
        if (overridesPlatform) {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        }
        try {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          if (goldenCase.name == 'success page') {
            tester.view.padding = const FakeViewPadding(top: 59);
            addTearDown(tester.view.resetPadding);
          }

          await tester.pumpWidget(_subscriptionGoldenApp(goldenCase.child));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();

          await expectLater(
            find.byKey(const Key('subscription-golden-boundary')),
            matchesGoldenFile('goldens/rendered/${goldenCase.file}'),
          );
        } finally {
          if (overridesPlatform) {
            debugDefaultTargetPlatformOverride = null;
          }
        }
      },
    );
  }

  testWidgets('subscription video background follows the available width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_subscriptionGoldenApp(const SubscriptionPage()));
    await tester.pump();

    expect(
      find.byKey(const Key('subscription-video-background')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('subscription-video-background')),
          )
          .color,
      Colors.black,
    );
    final videoFrame = find.byKey(const Key('subscription-video-frame'));
    expect(tester.getSize(videoFrame).width, 430);
    expect(tester.getSize(videoFrame).height, closeTo(763.82, 0.01));
  });

  testWidgets('Android sheet uses video while iOS keeps its updated image', (
    tester,
  ) async {
    Iterable<String> renderedAssetNames() => tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName);

    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        _subscriptionGoldenApp(const SubscriptionPage(sheet: true)),
      );
      await tester.pumpAndSettle();

      expect(
        renderedAssetNames(),
        isNot(contains('assets/subscription/sheet_background_1651_9915.png')),
      );
      expect(
        find.byKey(const Key('subscription-video-background')),
        findsOneWidget,
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(
        _subscriptionGoldenApp(const SubscriptionPage(sheet: true)),
      );
      await tester.pumpAndSettle();

      expect(
        renderedAssetNames(),
        contains('assets/subscription/sheet_background_1651_9915.png'),
      );
      expect(
        find.byKey(const Key('subscription-video-background')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
      await _openProfileTab(tester);

      await tester.tap(find.text('person@example.com').first);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile-premium-page-title')),
        findsOneWidget,
      );
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
      expect(find.text('REFRESH'), findsOneWidget);

      await tester.tap(find.text('REFRESH'));
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
      expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('kando-top-toast')),
          matching: find.byIcon(Icons.wifi_off_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('Sign in / Sign up'), findsNothing);
      expect(repository._currentSession?.isUser, isTrue);
      await _dismissTopToast(tester);
    },
  );

  testWidgets('offline logout from Account keeps the user on account details', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('kando-top-toast')),
        matching: find.byIcon(Icons.wifi_off_rounded),
      ),
      findsOneWidget,
    );
    expect(find.text('person@example.com'), findsWidgets);
    await _dismissTopToast(tester);
  });

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

    expect(find.byKey(const Key('profile-premium-page-title')), findsOneWidget);
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
    await _dismissTopToast(tester);
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
    await _dismissTopToast(tester);
  });
}

Future<void> _dismissTopToast(WidgetTester tester) async {
  final toast = find.byKey(const Key('kando-top-toast'));
  expect(toast, findsOneWidget);
  await tester.tap(
    find.descendant(of: toast, matching: find.byTooltip('Close')),
  );
  await tester.pump();
  expect(toast, findsNothing);
}

Future<void> _openProfileTab(WidgetTester tester) async {
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
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
  SubscriptionController Function()? subscriptionController,
}) {
  final onboardingStorage = InMemoryOnboardingStorage(completed: true);

  return ProviderScope(
    overrides: [
      appStartupPreloaderProvider.overrideWith((ref) async {}),
      onboardingControllerProvider.overrideWith(
        _CompletedOnboardingController.new,
      ),
      homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
      authRepositoryProvider.overrideWithValue(repository),
      if (authController != null)
        authControllerProvider.overrideWith(authController),
      subscriptionControllerProvider.overrideWith(
        subscriptionController ?? _FreeSubscriptionController.new,
      ),
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

class _ProSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(isPro: true);

  @override
  Future<void> restore({
    SubscriptionRestoreSource source =
        SubscriptionRestoreSource.subscriptionPage,
  }) async {}
}

class _RestoringSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(
    premiumState: AppPremiumState.premium,
    isRestoring: true,
    isLoading: true,
  );
}

class _FreeSubscriptionController extends SubscriptionController {
  @override
  SubscriptionState build() => const SubscriptionState(
    premiumState: AppPremiumState.free,
    isConfigured: true,
    displayPrices: {
      subscriptionWeeklyPlanId: r'$4.99',
      subscriptionYearlyPlanId: r'$49.99',
      subscriptionLifetimePlanId: r'$79.99',
    },
    availablePlanIds: {
      subscriptionWeeklyPlanId,
      subscriptionYearlyPlanId,
      subscriptionLifetimePlanId,
    },
  );

  @override
  Future<void> restore({
    SubscriptionRestoreSource source =
        SubscriptionRestoreSource.subscriptionPage,
  }) async {}
}

ProviderScope _subscriptionGoldenApp(
  Widget child, {
  bool disableAnimations = true,
}) {
  return ProviderScope(
    overrides: [
      subscriptionControllerProvider.overrideWith(
        _FreeSubscriptionController.new,
      ),
    ],
    child: MaterialApp(
      theme: buildKandoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: RepaintBoundary(
        key: const Key('subscription-golden-boundary'),
        child: child,
      ),
    ),
  );
}

class _CompletedOnboardingController extends OnboardingController {
  @override
  Future<bool> build() async => true;
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

ProviderScope _testEmailAuthPageApp(_WidgetAuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp(
      theme: buildKandoTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final message = await showEmailAuthPage(context);
                if (message != null && context.mounted) {
                  final toastCopy = _successToastCopy(message);
                  if (toastCopy != null) {
                    unawaited(
                      showGeneralDialog<void>(
                        context: context,
                        barrierDismissible: true,
                        barrierLabel: toastCopy.title,
                        barrierColor: Colors.transparent,
                        transitionDuration: Duration.zero,
                        pageBuilder: (_, _, _) => Center(
                          child: _TestAuthSuccessToast(
                            title: toastCopy.title,
                            message: toastCopy.message,
                          ),
                        ),
                      ),
                    );
                    return;
                  }

                  final modalCopy = _successModalCopy(message);
                  if (modalCopy == null) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(message)));
                    return;
                  }
                  unawaited(
                    showKandoWelcomeModal(
                      context,
                      title: modalCopy.title,
                      message: modalCopy.message,
                    ),
                  );
                }
              },
              child: const Text('Open email auth'),
            ),
          ),
        ),
      ),
    ),
  );
}

({String title, String message})? _successModalCopy(String message) {
  final parts = message.split('\n');
  if (parts.length >= 2) {
    return (title: parts.first, message: parts.skip(1).join('\n'));
  }
  return null;
}

({String title, String message})? _successToastCopy(String message) {
  if (message == 'Welcome back') {
    return (title: 'Welcome back', message: 'Let’s collect the cards.');
  }
  return null;
}

class _TestAuthSuccessToast extends StatelessWidget {
  const _TestAuthSuccessToast({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('auth-success-toast'),
      width: 260,
      height: 122,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontSize: 24, height: 32 / 24),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textScaler: TextScaler.noScaling,
            style: const TextStyle(fontSize: 15, height: 22 / 15),
          ),
        ],
      ),
    );
  }
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
    this.registerCodeCompleter,
    this.forgotCodeError,
    this.loginCompleter,
    this.googleCallbackError,
    this.googleCallbackCompleter,
    this.appleCallbackCompleter,
    this.logoutError,
    this.deleteError,
    this.emailRegistered = true,
    this.registeredEmails = const {},
  }) : _currentSession = initialSession,
       _createdAnonymousIds = [...createdAnonymousIds],
       _initialSessionErrors = [...initialSessionErrors];

  AuthSession? _currentSession;
  final List<String> _createdAnonymousIds;
  final List<Exception> _initialSessionErrors;
  final Exception? registerError;
  final Completer<void>? registerCodeCompleter;
  final Exception? forgotCodeError;
  final Completer<AuthSession>? loginCompleter;
  final Exception? googleCallbackError;
  final Completer<AuthSession>? googleCallbackCompleter;
  final Completer<AuthSession>? appleCallbackCompleter;
  final Exception? logoutError;
  final Exception? deleteError;
  final bool emailRegistered;
  final Set<String> registeredEmails;
  var logoutRequests = 0;
  var deleteRequests = 0;
  final List<_LoginRequest> loginRequests = [];
  final List<String> registerCodeEmails = [];
  final List<_CodeRequest> registerCodeVerifications = [];
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
    final completer = registerCodeCompleter;
    if (completer != null) {
      await completer.future;
    }
    if (emailRegistered || registeredEmails.contains(email)) {
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
    registerCodeVerifications.add(_CodeRequest(email, code));
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
    required String idToken,
    String? anonymousId,
  }) async {
    googleCallbackRequests.add(
      _GoogleCallbackRequest(idToken: idToken, anonymousId: anonymousId),
    );
    final error = googleCallbackError;
    if (error != null) {
      throw error;
    }
    final completer = googleCallbackCompleter;
    if (completer != null) {
      return completer.future;
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
    final completer = appleCallbackCompleter;
    if (completer != null) {
      return completer.future;
    }
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
  _WidgetOAuthAuthorizer({this.result, this.resultFuture, this.error});

  final OAuthAuthorizationResult? result;
  final Future<OAuthAuthorizationResult?>? resultFuture;
  final Exception? error;
  final List<OAuthProvider> requests = [];

  @override
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider) async {
    requests.add(provider);
    final error = this.error;
    if (error != null) {
      throw error;
    }
    final resultFuture = this.resultFuture;
    if (resultFuture != null) {
      return resultFuture;
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
  Rect? sharePositionOrigin;

  @override
  Future<void> openPrivacy() => _record('privacy');

  @override
  Future<void> openTerms() => _record('terms');

  @override
  Future<void> requestScore() => _record('score');

  @override
  Future<void> shareWithFriends({Rect? sharePositionOrigin}) {
    this.sharePositionOrigin = sharePositionOrigin;
    return _record('share');
  }

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
    required this.idToken,
    required this.anonymousId,
  });

  final String idToken;
  final String? anonymousId;

  @override
  bool operator ==(Object other) {
    return other is _GoogleCallbackRequest &&
        other.idToken == idToken &&
        other.anonymousId == anonymousId;
  }

  @override
  int get hashCode => Object.hash(idToken, anonymousId);
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

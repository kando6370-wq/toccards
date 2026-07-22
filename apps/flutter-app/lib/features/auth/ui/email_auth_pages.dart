import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';
import 'package:kando_app/shared/validation/email.dart';

import '../auth_controller.dart';

const _shortPasswordMessage = 'Password must be at least 8 characters.';
const _passwordMismatchMessage = 'Passwords do not match.';
const _incorrectCodeMessage = 'Incorrect verification code';
const _expiredCodeMessage = 'Code expired. Please request a new code.';

enum _EmailPage {
  email,
  login,
  registerCode,
  registerPassword,
  forgotEmail,
  forgotCode,
  forgotPassword,
}

Future<String?> showEmailAuthPage(BuildContext context) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder<String>(
      pageBuilder: (_, _, _) => const EmailAuthPages(fullScreen: true),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}

class EmailAuthPages extends ConsumerStatefulWidget {
  const EmailAuthPages({super.key, this.fullScreen = false});

  final bool fullScreen;

  @override
  ConsumerState<EmailAuthPages> createState() => _EmailAuthPagesState();
}

class _EmailAuthPagesState extends ConsumerState<EmailAuthPages> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  var _page = _EmailPage.email;
  var _loading = false;
  String? _email;
  String? _code;
  String? _resetToken;
  String? _errorText;
  Timer? _resendTimer;
  Timer? _codeSentToastTimer;
  Timer? _passwordResetSuccessTimer;
  var _resendSeconds = 0;
  var _isCodeSentToastVisible = false;
  var _isPasswordResetSuccessVisible = false;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeSentToastTimer?.cancel();
    _passwordResetSuccessTimer?.cancel();
    _emailController.removeListener(_syncEmailValidationState);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_syncEmailValidationState);
  }

  @override
  Widget build(BuildContext context) {
    final form = Form(
      key: _formKey,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: _buildPage(context),
      ),
    );

    if (!widget.fullScreen) {
      return form;
    }

    return Stack(
      children: [
        _EmailAuthFullScreen(page: _page, onBack: _handleBack, child: form),
        if (_isCodeSentToastVisible)
          const Positioned.fill(
            child: IgnorePointer(child: Center(child: _CodeSentToast())),
          ),
        if (_isPasswordResetSuccessVisible)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(child: _PasswordResetSuccessToast()),
            ),
          ),
      ],
    );
  }

  Widget _buildPage(BuildContext context) {
    final body = switch (_page) {
      _EmailPage.email => _EmailInputPage(
        controller: _emailController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _beginEmailAuth,
        fullScreen: widget.fullScreen,
      ),
      _EmailPage.login => _PasswordPage(
        title: _email ?? '',
        controller: _passwordController,
        loading: _loading,
        buttonLabel: 'Log in',
        errorText: _errorText,
        onSubmit: _login,
        secondaryLabel: 'Create account',
        onSecondary: _sendRegisterCode,
        onForgotPassword: () => _setPage(_EmailPage.forgotEmail),
        fullScreen: widget.fullScreen,
      ),
      _EmailPage.registerCode => _CodePage(
        controller: _codeController,
        email: _email ?? '',
        emailController: _emailController,
        onEmailChanged: _handleRegisterEmailChanged,
        title: 'Sign up',
        fullScreen: widget.fullScreen,
        loading: _loading,
        errorText: _errorText,
        onContinue: _continueToRegisterPassword,
        resendSeconds: _resendSeconds,
        resendEnabled: _hasValidEmailInput(_emailController.text),
        onResend: _resendRegisterCode,
      ),
      _EmailPage.registerPassword => _PasswordPairPage(
        passwordController: _passwordController,
        confirmController: _confirmPasswordController,
        loading: _loading,
        buttonLabel: 'Create account',
        errorText: _errorText,
        onSubmit: _verifyRegister,
        fullScreen: widget.fullScreen,
      ),
      _EmailPage.forgotEmail => _EmailOnlyPage(
        controller: _emailController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _sendForgotCode,
        fullScreen: widget.fullScreen,
      ),
      _EmailPage.forgotCode => _CodePage(
        controller: _codeController,
        email: _email ?? '',
        title: 'Reset Password',
        fullScreen: widget.fullScreen,
        isForgotFlow: true,
        loading: _loading,
        errorText: _errorText,
        onContinue: _verifyForgotCode,
        resendSeconds: _resendSeconds,
        onResend: _resendForgotCode,
      ),
      _EmailPage.forgotPassword => _PasswordPairPage(
        passwordController: _passwordController,
        confirmController: _confirmPasswordController,
        loading: _loading,
        buttonLabel: 'Confirm',
        errorText: _errorText,
        onSubmit: _resetPassword,
        fullScreen: widget.fullScreen,
      ),
    };

    return KeyedSubtree(key: ValueKey(_page), child: body);
  }

  void _setPage(_EmailPage page) {
    _formKey.currentState?.reset();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _codeController.clear();
    final errorText = _showsEmailInputValidation(page)
        ? _visibleEmailValidationMessage()
        : null;
    if (!_isCodePage(page)) {
      _codeSentToastTimer?.cancel();
    }
    setState(() {
      _errorText = errorText;
      _page = page;
      if (!_isCodePage(page)) {
        _isCodeSentToastVisible = false;
      }
    });
  }

  bool _isCodePage(_EmailPage page) {
    return page == _EmailPage.registerCode || page == _EmailPage.forgotCode;
  }

  void _syncEmailValidationState() {
    if (!_showsEmailInputValidation(_page)) {
      return;
    }
    final nextErrorText = _visibleEmailValidationMessage();
    if (_errorText == nextErrorText) {
      return;
    }
    setState(() => _errorText = nextErrorText);
  }

  bool _showsEmailInputValidation(_EmailPage page) {
    return page == _EmailPage.email || page == _EmailPage.forgotEmail;
  }

  String? _visibleEmailValidationMessage() {
    final email = _normalizedEmail();
    if (email.isEmpty) {
      return null;
    }
    return _emailValidationMessage(email);
  }

  void _handleBack() {
    if (_loading) {
      return;
    }

    switch (_page) {
      case _EmailPage.email:
        Navigator.of(context).pop();
      case _EmailPage.login:
        _setPage(_EmailPage.email);
      case _EmailPage.registerCode:
        if (widget.fullScreen) {
          Navigator.of(context).pop();
        } else {
          _setPage(_EmailPage.email);
        }
      case _EmailPage.registerPassword:
        _setPage(_EmailPage.registerCode);
      case _EmailPage.forgotEmail:
        _setPage(_email == null ? _EmailPage.email : _EmailPage.login);
      case _EmailPage.forgotCode:
        _setPage(_EmailPage.forgotEmail);
      case _EmailPage.forgotPassword:
        _setPage(_EmailPage.forgotCode);
    }
  }

  Future<void> _beginEmailAuth() async {
    final email = _normalizedEmail();
    if (!_validateEmail(email)) {
      return;
    }

    await _run(() async {
      final destination = await ref
          .read(authControllerProvider.notifier)
          .beginEmailAuth(email);
      if (!mounted) return;
      _clearSensitiveInputs();
      setState(() {
        _email = email;
        _page = destination == EmailAuthDestination.login
            ? _EmailPage.login
            : _EmailPage.registerCode;
      });
      if (destination == EmailAuthDestination.registerCode) {
        _startResendCountdown();
        _revealCodeSentToast();
      }
    });
  }

  Future<void> _login() async {
    if (!_validatePassword(_passwordController.text)) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email!, password: _passwordController.text);
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      _completeSignIn('Welcome back');
    });
  }

  Future<void> _sendRegisterCode() async {
    await _run(() async {
      await ref.read(authControllerProvider.notifier).sendRegisterCode(_email!);
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      setState(() => _page = _EmailPage.registerCode);
      _startResendCountdown();
      _revealCodeSentToast();
    });
  }

  Future<void> _continueToRegisterPassword() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .verifyRegisterCode(email: _email!, code: code);
      if (!mounted) return;
      _codeSentToastTimer?.cancel();
      setState(() {
        _code = code;
        _page = _EmailPage.registerPassword;
        _isCodeSentToastVisible = false;
      });
      _clearSensitiveInputs();
    });
  }

  Future<void> _verifyRegister() async {
    if (!_validatePasswordPair()) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .verifyRegister(
            email: _email!,
            code: _code!,
            password: _passwordController.text,
          );
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      _completeSignIn('Welcome\nLet’s collect the cards.');
    });
  }

  Future<void> _sendForgotCode() async {
    final email = _normalizedEmail();
    if (!_validateEmail(email)) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .sendForgotPasswordCode(email);
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      setState(() {
        _email = email;
        _page = _EmailPage.forgotCode;
      });
      _startResendCountdown();
      _revealCodeSentToast();
    });
  }

  Future<void> _verifyForgotCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      return;
    }

    await _run(() async {
      final token = await ref
          .read(authControllerProvider.notifier)
          .verifyForgotPasswordCode(email: _email!, code: code);
      if (!mounted) {
        return;
      }
      _codeSentToastTimer?.cancel();
      _clearSensitiveInputs();
      setState(() {
        _code = code;
        _resetToken = token;
        _page = _EmailPage.forgotPassword;
        _isCodeSentToastVisible = false;
      });
    });
  }

  Future<void> _resetPassword() async {
    if (!_validatePasswordPair()) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .resetPassword(
            email: _email!,
            resetToken: _resetToken!,
            newPassword: _passwordController.text,
          );
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      setState(() => _page = _EmailPage.login);
      _showPasswordResetSuccess();
    });
  }

  void _handleRegisterEmailChanged(String value) {
    if (_page != _EmailPage.registerCode || normalizedEmail(value) == _email) {
      return;
    }
    _resendTimer?.cancel();
    _codeSentToastTimer?.cancel();
    _codeController.clear();
    setState(() {
      _resendSeconds = 0;
      _errorText = null;
      _isCodeSentToastVisible = false;
    });
  }

  Future<void> _resendRegisterCode() async {
    if (_resendSeconds > 0) return;
    final email = _normalizedEmail();
    if (!_validateEmail(email)) return;

    await _run(() async {
      final destination = await ref
          .read(authControllerProvider.notifier)
          .beginEmailAuth(email);
      if (!mounted) return;
      _clearSensitiveInputs();
      setState(() {
        _email = email;
        _page = destination == EmailAuthDestination.login
            ? _EmailPage.login
            : _EmailPage.registerCode;
      });
      if (destination == EmailAuthDestination.registerCode) {
        _startResendCountdown();
        _revealCodeSentToast();
      }
    });
  }

  Future<void> _resendForgotCode() => _resendCode(
    () => ref
        .read(authControllerProvider.notifier)
        .sendForgotPasswordCode(_email!),
    showCodeSentToast: true,
  );

  Future<void> _resendCode(
    Future<void> Function() send, {
    bool showCodeSentToast = false,
  }) async {
    if (_resendSeconds > 0) return;
    await _run(() async {
      await send();
      if (!mounted) return;
      _codeController.clear();
      _startResendCountdown();
      if (showCodeSentToast) {
        _revealCodeSentToast();
      }
    });
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds--);
    });
  }

  void _revealCodeSentToast() {
    _codeSentToastTimer?.cancel();
    setState(() => _isCodeSentToastVisible = true);
    _codeSentToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isCodeSentToastVisible = false);
      }
    });
  }

  void _revealPasswordResetSuccess() {
    _passwordResetSuccessTimer?.cancel();
    setState(() => _isPasswordResetSuccessVisible = true);
    _passwordResetSuccessTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isPasswordResetSuccessVisible = false);
      }
    });
  }

  void _showPasswordResetSuccess() {
    if (widget.fullScreen) {
      _revealPasswordResetSuccess();
      return;
    }

    _passwordResetSuccessTimer?.cancel();
    var dismissed = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Password reset successfully.',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            const Center(child: _PasswordResetSuccessToast()),
      ).whenComplete(() => dismissed = true),
    );
    _passwordResetSuccessTimer = Timer(const Duration(seconds: 2), () {
      if (!dismissed && navigator.mounted) {
        navigator.pop();
      }
    });
  }

  void _completeSignIn(String message) {
    if (widget.fullScreen) {
      Navigator.of(context).pop(message);
      return;
    }
    showKandoToast(context, message: message);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _errorText = _displayError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _normalizedEmail() => normalizedEmail(_emailController.text);

  bool _validateEmail(String email) {
    final message = _emailValidationMessage(email);
    setState(() => _errorText = message);
    return message == null;
  }

  String? _emailValidationMessage(String email) {
    return emailValidationMessage(email);
  }

  bool _validatePassword(String password) {
    if (password.length < 8) {
      setState(() => _errorText = _shortPasswordMessage);
      return false;
    }
    setState(() => _errorText = null);
    return true;
  }

  bool _validatePasswordPair() {
    if (!_validatePassword(_passwordController.text)) {
      return false;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorText = _passwordMismatchMessage);
      return false;
    }
    return true;
  }

  String _displayError(Exception error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    final normalized = message.toLowerCase();

    if (_looksLikeCodeError(normalized) &&
        (normalized.contains('invalid') ||
            normalized.contains('incorrect') ||
            normalized.contains('wrong'))) {
      return _incorrectCodeMessage;
    }
    if (_looksLikeCodeError(normalized) &&
        (normalized.contains('expired') || normalized.contains('expire'))) {
      return _expiredCodeMessage;
    }

    return message;
  }

  bool _looksLikeCodeError(String message) {
    return message.contains('code') || message.contains('verification');
  }

  void _clearSensitiveInputs() {
    _passwordController.clear();
    _confirmPasswordController.clear();
    _codeController.clear();
  }
}

class _EmailInputPage extends StatelessWidget {
  const _EmailInputPage({
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.onContinue,
    required this.fullScreen,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final emailField = _LabeledField(
      label: 'Email Address',
      child: TextFormField(
        controller: controller,
        autofocus: fullScreen,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.go,
        onFieldSubmitted: (_) {
          if (_hasValidEmailInput(controller.text)) {
            onContinue();
          }
        },
        style: _fieldTextStyle,
        decoration: _fieldDecoration(
          hint: 'name@exclusive.com',
          hasError: hasError,
        ),
      ),
    );

    if (!fullScreen) {
      return _SheetColumn(
        errorText: errorText,
        children: [
          emailField,
          const SizedBox(height: 16),
          _PrimaryButton(
            label: 'Continue',
            loading: loading,
            onPressed: onContinue,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        emailField,
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const Spacer(),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => _PrimaryButton(
            label: 'Continue',
            loading: loading,
            enabled: _hasValidEmailInput(value.text),
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _EmailOnlyPage extends StatelessWidget {
  const _EmailOnlyPage({
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.onContinue,
    this.fullScreen = false,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    if (fullScreen) {
      return _FullScreenFormViewport(
        minHeightForAnchoredActions: 520,
        builder: (context, anchorActionsToBottom) => _ForgotEmailContent(
          controller: controller,
          loading: loading,
          errorText: errorText,
          onContinue: onContinue,
          anchorActionsToBottom: anchorActionsToBottom,
        ),
      );
    }

    return _SheetColumn(
      errorText: errorText,
      children: [
        _LabeledField(
          label: 'Email Address',
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            style: _fieldTextStyle,
            decoration: _fieldDecoration(
              hint: 'name@exclusive.com',
              hasError: hasError,
            ),
          ),
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => _PrimaryButton(
            label: 'Continue',
            loading: loading,
            enabled: _hasValidEmailInput(value.text),
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _ForgotEmailContent extends StatelessWidget {
  const _ForgotEmailContent({
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.onContinue,
    required this.anchorActionsToBottom,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final bool anchorActionsToBottom;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FigmaAuthTitle('Reset Password'),
        const SizedBox(height: 32),
        _LabeledField(
          label: 'Email Address',
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.go,
            onFieldSubmitted: (_) {
              if (_hasValidEmailInput(controller.text)) {
                onContinue();
              }
            },
            style: _fieldTextStyle,
            decoration: _fieldDecoration(
              hint: 'Your Address',
              hintStyle: const TextStyle(
                color: Color(0xFF615D3B),
                fontSize: 15,
                height: 22 / 15,
              ),
              hasError: hasError,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          errorText ??
              'Enter the email associated with your Collection Vault account.',
          style: TextStyle(
            color: hasError ? const Color(0xFFE57373) : const Color(0xFF615D3B),
            fontSize: 11,
            height: 18 / 11,
          ),
        ),
        if (anchorActionsToBottom)
          const Spacer()
        else
          const SizedBox(height: 32),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => _CodeActionButton(
            label: 'Get verification code',
            loading: loading,
            enabled: _hasValidEmailInput(value.text),
            onPressed: onContinue,
          ),
        ),
      ],
    );
  }
}

class _PasswordPage extends StatelessWidget {
  const _PasswordPage({
    required this.title,
    required this.controller,
    required this.loading,
    required this.buttonLabel,
    required this.errorText,
    required this.onSubmit,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.onForgotPassword,
    this.fullScreen = false,
  });

  final String title;
  final TextEditingController controller;
  final bool loading;
  final String buttonLabel;
  final String? errorText;
  final VoidCallback onSubmit;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback onForgotPassword;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    if (fullScreen) {
      return _FullScreenFormViewport(
        minHeightForAnchoredActions: 620,
        builder: (context, anchorActionsToBottom) => _FigmaPasswordContent(
          email: title,
          controller: controller,
          loading: loading,
          errorText: errorText,
          onSubmit: onSubmit,
          secondaryLabel: secondaryLabel,
          onSecondary: onSecondary,
          onForgotPassword: onForgotPassword,
          anchorActionsToBottom: anchorActionsToBottom,
        ),
      );
    }

    return _SheetColumn(
      errorText: errorText,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: KandoColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 24),
        _LabeledField(
          label: 'Password',
          child: _PasswordField(controller: controller),
        ),
        const SizedBox(height: 8),
        _LinkButton(
          label: 'Forgot Password ?',
          loading: loading,
          onPressed: onForgotPassword,
          alignment: Alignment.centerRight,
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: buttonLabel,
          loading: loading,
          onPressed: onSubmit,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              "Don't have an account?",
              style: TextStyle(color: KandoColors.mutedText),
            ),
            _LinkButton(
              label: secondaryLabel,
              loading: loading,
              onPressed: onSecondary,
            ),
          ],
        ),
      ],
    );
  }
}

class _FigmaPasswordContent extends StatelessWidget {
  const _FigmaPasswordContent({
    required this.email,
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.onSubmit,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.onForgotPassword,
    required this.anchorActionsToBottom,
  });

  final String email;
  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onSubmit;
  final String secondaryLabel;
  final VoidCallback onSecondary;
  final VoidCallback onForgotPassword;
  final bool anchorActionsToBottom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Sign in',
          style: TextStyle(
            color: KandoColors.text,
            fontFamily: 'Fraunces',
            fontSize: 32,
            height: 40 / 32,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter your email and password to login',
          style: TextStyle(
            color: Color(0xFF92927D),
            fontSize: 11,
            height: 18 / 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 32),
        _LabeledField(
          label: 'Email Address',
          child: _ReadOnlyEmailField(email: email),
        ),
        const SizedBox(height: 32),
        _LabeledField(
          label: 'Password',
          child: _PasswordField(controller: controller),
        ),
        const SizedBox(height: 8),
        _LinkButton(
          label: 'Forgot Password ?',
          loading: loading,
          onPressed: onForgotPassword,
          alignment: Alignment.centerRight,
        ),
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: const TextStyle(
              color: KandoColors.errorText,
              fontSize: 12,
              height: 18 / 12,
            ),
          ),
        ],
        if (anchorActionsToBottom)
          const Spacer()
        else
          const SizedBox(height: 32),
        _PrimaryButton(label: 'Sign in', loading: loading, onPressed: onSubmit),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              "Don't have an account?",
              style: TextStyle(
                color: Color(0xFF837D40),
                fontSize: 16,
                height: 24 / 16,
              ),
            ),
            const SizedBox(width: 4),
            _InlineLinkButton(
              label: secondaryLabel,
              loading: loading,
              onPressed: onSecondary,
            ),
          ],
        ),
      ],
    );
  }
}

class _CodePage extends StatefulWidget {
  const _CodePage({
    required this.controller,
    required this.email,
    required this.title,
    required this.fullScreen,
    required this.loading,
    required this.errorText,
    required this.onContinue,
    required this.resendSeconds,
    required this.onResend,
    this.resendEnabled = true,
    this.emailController,
    this.onEmailChanged,
    this.isForgotFlow = false,
  });

  final TextEditingController controller;
  final String email;
  final String title;
  final bool fullScreen;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final int resendSeconds;
  final VoidCallback onResend;
  final bool resendEnabled;
  final TextEditingController? emailController;
  final ValueChanged<String>? onEmailChanged;
  final bool isForgotFlow;

  @override
  State<_CodePage> createState() => _CodePageState();
}

class _CodePageState extends State<_CodePage> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final complete = value.text.length == 6;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VerificationCodeInput(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: widget.fullScreen,
              errorText: widget.errorText,
              onSubmitted: widget.onContinue,
            ),
            if (widget.fullScreen)
              const Spacer()
            else
              const SizedBox(height: 24),
            _CodeActionButton(
              label: complete
                  ? 'Get verification code'
                  : widget.resendSeconds > 0
                  ? 'Retry in ${widget.resendSeconds} seconds'
                  : 'Resend code',
              loading: widget.loading,
              enabled:
                  complete ||
                  (widget.resendSeconds == 0 && widget.resendEnabled),
              onPressed: complete ? widget.onContinue : widget.onResend,
            ),
          ],
        );
      },
    );

    if (!widget.fullScreen) return content;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FigmaAuthTitle(widget.title),
        if (!widget.isForgotFlow) ...[
          const SizedBox(height: 8),
          const Text(
            'Enter the correct email CAPTCHA login',
            style: TextStyle(
              color: Color(0xFF92927D),
              fontSize: 11,
              height: 18 / 11,
            ),
          ),
        ],
        const SizedBox(height: 32),
        const Text(
          'Email Address',
          style: TextStyle(
            color: Color(0xFF92927D),
            fontSize: 11,
            height: 18 / 11,
          ),
        ),
        const SizedBox(height: 8),
        if (widget.emailController == null)
          _ReadOnlyEmailField(email: widget.email)
        else
          TextFormField(
            key: const Key('register-code-email-input'),
            controller: widget.emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onChanged: widget.onEmailChanged,
            style: _fieldTextStyle,
            decoration: _fieldDecoration(hint: 'name@exclusive.com'),
          ),
        const SizedBox(height: 32),
        Expanded(child: content),
      ],
    );
  }
}

class _VerificationCodeInput extends StatelessWidget {
  const _VerificationCodeInput({
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.errorText,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final String? errorText;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Verification Code',
              style: TextStyle(color: Color(0xFF92927D), fontSize: 12),
            ),
            if (hasError) ...[
              const Spacer(),
              Flexible(
                child: Text(
                  errorText!,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: const TextStyle(
                    color: Color(0xFFFF8787),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final boxWidth = ((constraints.maxWidth - 60) / 6)
                .clamp(0.0, 48.0)
                .toDouble();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: focusNode.requestFocus,
              child: Stack(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      final text = controller.text;
                      final isActive = !hasError && index == text.length;
                      return Container(
                        key: Key('verification-code-box-$index'),
                        width: boxWidth,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0F08),
                          border: Border.all(
                            color: hasError
                                ? const Color(0xFFFF8787)
                                : isActive
                                ? KandoColors.accent
                                : KandoColors.border,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          index < text.length ? text[index] : '',
                          style: const TextStyle(
                            color: KandoColors.text,
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),
                      );
                    }),
                  ),
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0,
                      child: TextFormField(
                        key: const Key('verification-code-input'),
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: autofocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onFieldSubmitted: (_) {
                          if (controller.text.length == 6) {
                            onSubmitted();
                          }
                        },
                        decoration: const InputDecoration(counterText: ''),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          "Didn't get the code? Check your spam",
          style: TextStyle(
            color: Color(0xFF615D3B),
            fontSize: 11,
            height: 18 / 11,
          ),
        ),
      ],
    );
  }
}

class _FullScreenFormViewport extends StatelessWidget {
  const _FullScreenFormViewport({
    required this.minHeightForAnchoredActions,
    required this.builder,
  });

  final double minHeightForAnchoredActions;
  final Widget Function(BuildContext context, bool anchorActionsToBottom)
  builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: builder(
                context,
                constraints.maxHeight >= minHeightForAnchoredActions,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CodeActionButton extends StatelessWidget {
  const _CodeActionButton({
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        backgroundColor: KandoColors.accent,
        foregroundColor: const Color(0xFF2C3400),
        disabledBackgroundColor: KandoColors.elevatedSurface,
        disabledForegroundColor: const Color(0xFF615D3B),
        textStyle: const TextStyle(
          fontSize: 16,
          height: 24 / 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      onPressed: loading || !enabled ? null : onPressed,
      child: loading
          ? const _LoadingButtonContent(
              foregroundColor: Color(0xFF615D3B),
              indicatorColor: KandoColors.accent,
              strokeWidth: 2,
            )
          : Text(label),
    );
  }
}

class _PasswordPairPage extends StatelessWidget {
  const _PasswordPairPage({
    required this.passwordController,
    required this.confirmController,
    required this.loading,
    required this.buttonLabel,
    required this.errorText,
    required this.onSubmit,
    this.fullScreen = false,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool loading;
  final String buttonLabel;
  final String? errorText;
  final VoidCallback onSubmit;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    if (fullScreen) {
      return _FullScreenFormViewport(
        minHeightForAnchoredActions: 560,
        builder: (context, anchorActionsToBottom) => _FigmaPasswordPairContent(
          passwordController: passwordController,
          confirmController: confirmController,
          loading: loading,
          buttonLabel: buttonLabel,
          errorText: errorText,
          onSubmit: onSubmit,
          anchorActionsToBottom: anchorActionsToBottom,
        ),
      );
    }

    return _SheetColumn(
      errorText: errorText,
      children: [
        _LabeledField(
          label: 'Password',
          child: _PasswordField(controller: passwordController),
        ),
        const SizedBox(height: 16),
        _LabeledField(
          label: 'Confirm password',
          child: _PasswordField(controller: confirmController),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: buttonLabel,
          loading: loading,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _FigmaPasswordPairContent extends StatelessWidget {
  const _FigmaPasswordPairContent({
    required this.passwordController,
    required this.confirmController,
    required this.loading,
    required this.buttonLabel,
    required this.errorText,
    required this.onSubmit,
    required this.anchorActionsToBottom,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool loading;
  final String buttonLabel;
  final String? errorText;
  final VoidCallback onSubmit;
  final bool anchorActionsToBottom;

  @override
  Widget build(BuildContext context) {
    final isCreateAccount = buttonLabel.toLowerCase().contains('create');
    final title = isCreateAccount ? 'Set Password' : 'Set New Password';

    return AnimatedBuilder(
      animation: Listenable.merge([passwordController, confirmController]),
      builder: (context, _) {
        final password = passwordController.text;
        final confirmPassword = confirmController.text;
        final passwordError =
            (password.isNotEmpty && password.length < 8) ||
                errorText == _shortPasswordMessage
            ? 'At least 8 characters'
            : null;
        final confirmError =
            (confirmPassword.isNotEmpty && confirmPassword != password) ||
                errorText == _passwordMismatchMessage
            ? 'Inconsistent with last input'
            : null;
        final canSubmit =
            password.length >= 8 &&
            confirmPassword.isNotEmpty &&
            confirmPassword == password;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FigmaAuthTitle(title),
            const SizedBox(height: 32),
            _LabeledField(
              label: 'Password',
              child: _PasswordField(
                controller: passwordController,
                hint: 'Your password',
                hasError: passwordError != null,
                textInputAction: TextInputAction.next,
                autofocus: true,
              ),
            ),
            if (passwordError != null) ...[
              const SizedBox(height: 8),
              _FieldErrorText(passwordError),
            ],
            const SizedBox(height: 32),
            _LabeledField(
              label: 'Confirm Password',
              child: _PasswordField(
                controller: confirmController,
                hint: 'Confirm your password',
                hasError: confirmError != null,
                textInputAction: TextInputAction.go,
                onSubmitted: canSubmit ? onSubmit : null,
              ),
            ),
            if (confirmError != null) ...[
              const SizedBox(height: 8),
              _FieldErrorText(confirmError),
            ],
            if (anchorActionsToBottom)
              const Spacer()
            else
              const SizedBox(height: 32),
            _CodeActionButton(
              label: isCreateAccount ? 'Create Account' : buttonLabel,
              loading: loading,
              enabled: canSubmit,
              onPressed: onSubmit,
            ),
          ],
        );
      },
    );
  }
}

const _fieldTextStyle = TextStyle(
  color: KandoColors.text,
  fontSize: 15,
  height: 22 / 15,
  fontWeight: FontWeight.w400,
);

bool _hasValidEmailInput(String value) {
  return emailValidationMessage(normalizedEmail(value)) == null;
}

InputDecoration _fieldDecoration({
  String? hint,
  TextStyle? hintStyle,
  Widget? suffixIcon,
  bool hasError = false,
}) {
  const normalBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: KandoColors.border),
  );
  const errorBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: Color(0xFFFF8787)),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: hintStyle ?? _fieldTextStyle,
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
    constraints: const BoxConstraints.tightFor(height: 52),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: hasError ? errorBorder : normalBorder,
    enabledBorder: hasError ? errorBorder : normalBorder,
    focusedBorder: hasError
        ? errorBorder
        : const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: KandoColors.accent),
          ),
    errorBorder: errorBorder,
    focusedErrorBorder: errorBorder,
  );
}

class _FigmaAuthTitle extends StatelessWidget {
  const _FigmaAuthTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: KandoColors.text,
        fontFamily: 'Fraunces',
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _FieldErrorText extends StatelessWidget {
  const _FieldErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFFE57373),
        fontSize: 11,
        height: 18 / 11,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF92927D),
              fontSize: 11,
              height: 18 / 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ReadOnlyEmailField extends StatelessWidget {
  const _ReadOnlyEmailField({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: KandoColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        email.isEmpty ? 'name@exclusive.com' : email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _fieldTextStyle,
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    this.hasError = false,
    this.hint = '••••••••',
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool hasError;
  final String hint;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  var _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      style: _fieldTextStyle,
      decoration: _fieldDecoration(
        hint: widget.hint,
        hintStyle: const TextStyle(
          color: Color(0xFF615D3B),
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w400,
        ),
        hasError: widget.hasError,
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _obscure = !_obscure),
            child: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20,
              color: const Color(0xFF92927D),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        backgroundColor: KandoColors.accent,
        foregroundColor: KandoColors.primaryOnDefault,
        disabledBackgroundColor: KandoColors.elevatedSurface,
        disabledForegroundColor: KandoColors.mutedText.withValues(alpha: 0.45),
        textStyle: const TextStyle(
          fontSize: 16,
          height: 24 / 16,
          fontWeight: FontWeight.w400,
        ),
      ),
      onPressed: loading || !enabled ? null : onPressed,
      child: loading
          ? const _LoadingButtonContent(
              foregroundColor: KandoColors.mutedText,
              indicatorColor: KandoColors.accent,
              strokeWidth: 2.4,
            )
          : Text(label.toUpperCase()),
    );
  }
}

class _LoadingButtonContent extends StatelessWidget {
  const _LoadingButtonContent({
    required this.foregroundColor,
    required this.indicatorColor,
    required this.strokeWidth,
  });

  final Color foregroundColor;
  final Color indicatorColor;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: strokeWidth,
            color: indicatorColor,
          ),
        ),
        const SizedBox(width: 8),
        Text('Loading...', style: TextStyle(color: foregroundColor)),
      ],
    );
  }
}

class _CodeSentToast extends StatelessWidget {
  const _CodeSentToast();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('code-sent-toast'),
      width: 260,
      height: 122,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 4),
            blurRadius: 60,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Code sent',
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Color(0xFFF1FE70),
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      height: 32 / 24,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Check your email to continue creating your account.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Color(0xFFE3E3D6),
                      fontSize: 15,
                      height: 22 / 15,
                      fontWeight: FontWeight.w400,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordResetSuccessToast extends StatelessWidget {
  const _PasswordResetSuccessToast();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('password-reset-success-toast'),
      width: 260,
      height: 122,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 4),
            blurRadius: 60,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Success',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Color(0xFFF1FE70),
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      height: 32 / 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Password reset successfully.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Color(0xFFE3E3D6),
                      fontSize: 15,
                      height: 22 / 15,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailAuthFullScreen extends StatelessWidget {
  const _EmailAuthFullScreen({
    required this.page,
    required this.onBack,
    required this.child,
  });

  final _EmailPage page;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showEmailHeading = page == _EmailPage.email;
    final usesFigmaTopNavigation = !showEmailHeading;

    return SizedBox.expand(
      key: const Key('email-auth-page'),
      child: Scaffold(
        backgroundColor: KandoColors.ink,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              usesFigmaTopNavigation ? 2 : 28,
              20,
              32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    key: const Key('email-auth-back'),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                    iconSize: 24,
                    color: KandoColors.text,
                    style: IconButton.styleFrom(
                      backgroundColor: KandoColors.elevatedSurface,
                      fixedSize: const Size.square(40),
                    ),
                  ),
                ),
                SizedBox(height: usesFigmaTopNavigation ? 42 : 35),
                if (showEmailHeading) ...[
                  const Text(
                    'Continue With Email',
                    style: TextStyle(
                      color: KandoColors.text,
                      fontFamily: 'Fraunces',
                      fontSize: 31,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your credentials to access your secure digital\nrepository.',
                    style: TextStyle(
                      color: KandoColors.mutedText,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                ],
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineLinkButton extends StatelessWidget {
  const _InlineLinkButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !loading,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading ? null : onPressed,
        child: Text(
          label,
          style: const TextStyle(
            color: KandoColors.accent,
            fontSize: 16,
            height: 24 / 16,
          ),
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.alignment = Alignment.center,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: KandoColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: loading ? null : onPressed,
        child: Text(label),
      ),
    );
  }
}

class _SheetColumn extends StatelessWidget {
  const _SheetColumn({required this.children, this.errorText});

  final List<Widget> children;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...children,
        if (errorText != null) ...[
          const SizedBox(height: 12),
          Text(
            errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

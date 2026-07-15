import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';
import 'package:kando_app/shared/validation/email.dart';

import '../auth_controller.dart';

const _shortPasswordMessage = 'Password must be at least 8 characters.';
const _passwordMismatchMessage = 'Passwords do not match.';
const _incorrectCodeMessage = 'Incorrect verification code.';
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
  var _resendSeconds = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
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

    return _EmailAuthFullScreen(
      page: _page,
      onBack: () => Navigator.of(context).pop(false),
      child: form,
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
      ),
      _EmailPage.registerCode => _CodePage(
        controller: _codeController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _continueToRegisterPassword,
        resendSeconds: _resendSeconds,
        onResend: _resendRegisterCode,
      ),
      _EmailPage.registerPassword => _PasswordPairPage(
        passwordController: _passwordController,
        confirmController: _confirmPasswordController,
        loading: _loading,
        buttonLabel: 'Create account',
        errorText: _errorText,
        onSubmit: _verifyRegister,
      ),
      _EmailPage.forgotEmail => _EmailOnlyPage(
        controller: _emailController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _sendForgotCode,
      ),
      _EmailPage.forgotCode => _CodePage(
        controller: _codeController,
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
        buttonLabel: 'Reset password',
        errorText: _errorText,
        onSubmit: _resetPassword,
      ),
    };

    return KeyedSubtree(key: ValueKey(_page), child: body);
  }

  void _setPage(_EmailPage page) {
    _formKey.currentState?.reset();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _codeController.clear();
    setState(() {
      _errorText = null;
      _page = page;
    });
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
    });
  }

  Future<void> _continueToRegisterPassword() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      return;
    }

    await _run(() async {
      await ref
          .read(authControllerProvider.notifier)
          .verifyRegisterCode(email: _email!, code: code);
      if (!mounted) return;
      setState(() {
        _code = code;
        _page = _EmailPage.registerPassword;
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
    });
  }

  Future<void> _verifyForgotCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      return;
    }

    await _run(() async {
      final token = await ref
          .read(authControllerProvider.notifier)
          .verifyForgotPasswordCode(email: _email!, code: code);
      if (!mounted) {
        return;
      }
      _clearSensitiveInputs();
      setState(() {
        _code = code;
        _resetToken = token;
        _page = _EmailPage.forgotPassword;
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
      showKandoToast(context, message: 'Password reset successfully.');
    });
  }

  Future<void> _resendRegisterCode() => _resendCode(
    () => ref.read(authControllerProvider.notifier).sendRegisterCode(_email!),
  );

  Future<void> _resendForgotCode() => _resendCode(
    () => ref
        .read(authControllerProvider.notifier)
        .sendForgotPasswordCode(_email!),
  );

  Future<void> _resendCode(Future<void> Function() send) async {
    if (_resendSeconds > 0) return;
    await _run(() async {
      await send();
      if (!mounted) return;
      _codeController.clear();
      _startResendCountdown();
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
    final emailField = _LabeledField(
      label: 'Email Address',
      child: TextFormField(
        controller: controller,
        autofocus: fullScreen,
        keyboardType: TextInputType.emailAddress,
        style: _fieldTextStyle,
        decoration: _fieldDecoration(hint: 'name@exclusive.com'),
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
            enabled: value.text.trim().isNotEmpty,
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
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _SheetColumn(
      errorText: errorText,
      children: [
        _LabeledField(
          label: 'Email Address',
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            style: _fieldTextStyle,
            decoration: _fieldDecoration(hint: 'name@exclusive.com'),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Continue',
          loading: loading,
          onPressed: onContinue,
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

  @override
  Widget build(BuildContext context) {
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
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
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

class _CodePage extends StatelessWidget {
  const _CodePage({
    required this.controller,
    required this.loading,
    required this.errorText,
    required this.onContinue,
    required this.resendSeconds,
    required this.onResend,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final int resendSeconds;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return _SheetColumn(
      errorText: errorText,
      children: [
        _LabeledField(
          label: 'Verification code',
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: _fieldTextStyle,
            decoration: _fieldDecoration(hint: 'Enter code'),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Continue',
          loading: loading,
          onPressed: onContinue,
        ),
        const SizedBox(height: 8),
        _LinkButton(
          label: resendSeconds > 0
              ? 'Resend code in ${resendSeconds}s'
              : 'Resend code',
          loading: loading || resendSeconds > 0,
          onPressed: onResend,
        ),
      ],
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
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool loading;
  final String buttonLabel;
  final String? errorText;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
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

const _fieldTextStyle = TextStyle(fontSize: 15, color: KandoColors.text);

InputDecoration _fieldDecoration({String? hint, Widget? suffixIcon}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: KandoColors.border),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: KandoColors.mutedText, fontSize: 15),
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border,
    enabledBorder: border,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: KandoColors.accent),
    ),
  );
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
            style: const TextStyle(color: KandoColors.mutedText, fontSize: 12),
          ),
        ),
        child,
      ],
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller});

  final TextEditingController controller;

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
      style: _fieldTextStyle,
      decoration: _fieldDecoration(
        hint: '••••••••',
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: KandoColors.mutedText,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
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
        foregroundColor: KandoColors.ink,
        disabledBackgroundColor: KandoColors.elevatedSurface,
        disabledForegroundColor: KandoColors.mutedText.withValues(alpha: 0.45),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      onPressed: loading || !enabled ? null : onPressed,
      child: Text(loading ? 'Loading...' : label.toUpperCase()),
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

    return SizedBox.expand(
      key: const Key('email-auth-page'),
      child: Scaffold(
        backgroundColor: KandoColors.ink,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
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
                const SizedBox(height: 35),
                if (showEmailHeading) ...[
                  const Text(
                    'Continue With Email',
                    style: TextStyle(
                      color: KandoColors.text,
                      fontFamily: 'Georgia',
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

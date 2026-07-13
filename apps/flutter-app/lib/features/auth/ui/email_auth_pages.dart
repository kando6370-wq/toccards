import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
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

class EmailAuthPages extends ConsumerStatefulWidget {
  const EmailAuthPages({super.key});

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 120),
        child: _buildPage(context),
      ),
    );
  }

  Widget _buildPage(BuildContext context) {
    final body = switch (_page) {
      _EmailPage.email => _EmailInputPage(
        controller: _emailController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _continueToLogin,
        onForgotPassword: () => _setPage(_EmailPage.forgotEmail),
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
      ),
      _EmailPage.registerCode => _CodePage(
        controller: _codeController,
        loading: _loading,
        errorText: _errorText,
        onContinue: _continueToRegisterPassword,
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

  void _continueToLogin() {
    final email = _normalizedEmail();
    if (!_validateEmail(email)) {
      return;
    }

    _clearSensitiveInputs();
    setState(() {
      _email = email;
      _errorText = null;
      _page = _EmailPage.login;
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
      Navigator.of(context).pop();
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
    });
  }

  void _continueToRegisterPassword() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      return;
    }

    setState(() {
      _code = code;
      _errorText = null;
      _page = _EmailPage.registerPassword;
    });
    _clearSensitiveInputs();
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
      Navigator.of(context).pop();
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
    });
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
    required this.onForgotPassword,
  });

  final TextEditingController controller;
  final bool loading;
  final String? errorText;
  final VoidCallback onContinue;
  final VoidCallback onForgotPassword;

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
        const SizedBox(height: 8),
        _LinkButton(
          label: 'Forgot password ?',
          loading: loading,
          onPressed: onForgotPassword,
          alignment: Alignment.centerRight,
        ),
        const SizedBox(height: 16),
        _PrimaryButton(
          label: 'Continue',
          loading: loading,
          onPressed: onContinue,
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
  });

  final String title;
  final TextEditingController controller;
  final bool loading;
  final String buttonLabel;
  final String? errorText;
  final VoidCallback onSubmit;
  final String secondaryLabel;
  final VoidCallback onSecondary;

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
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        backgroundColor: KandoColors.accent,
        foregroundColor: KandoColors.ink,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      onPressed: loading ? null : onPressed,
      child: Text(loading ? 'Loading...' : label.toUpperCase()),
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

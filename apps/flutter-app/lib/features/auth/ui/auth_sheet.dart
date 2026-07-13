import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../auth_controller.dart';
import 'email_auth_pages.dart';
import '../../profile/profile_actions.dart';

Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _AuthSheet(),
  );
}

class _AuthSheet extends ConsumerStatefulWidget {
  const _AuthSheet();

  @override
  ConsumerState<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<_AuthSheet> {
  var _showEmail = false;
  var _loading = false;
  String? _errorText;
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () =>
          _openLegalLink(ref.read(profileActionsProvider).openTerms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () =>
          _openLegalLink(ref.read(profileActionsProvider).openPrivacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: 24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _showEmail
            ? const EmailAuthPages()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('Continue with Google'),
                    enabled: !_loading,
                    onTap: _loading ? null : _continueWithGoogle,
                  ),
                  ListTile(
                    title: const Text('Continue with Apple'),
                    enabled: !_loading,
                    onTap: _loading ? null : _continueWithApple,
                  ),
                  ListTile(
                    title: const Text('Continue with Email'),
                    enabled: !_loading,
                    onTap: _loading
                        ? null
                        : () => setState(() {
                            _errorText = null;
                            _showEmail = true;
                          }),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _AgreementText(
                    termsRecognizer: _termsRecognizer,
                    privacyRecognizer: _privacyRecognizer,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _continueWithGoogle() {
    return _run(() {
      return ref.read(authControllerProvider.notifier).continueWithGoogle();
    });
  }

  Future<void> _continueWithApple() {
    return _run(() {
      return ref.read(authControllerProvider.notifier).continueWithApple();
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
      if (!mounted) {
        return;
      }
      final session = ref.read(authControllerProvider).session;
      if (session?.isUser ?? false) {
        Navigator.of(context).pop();
      }
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

  String _displayError(Exception error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  Future<void> _openLegalLink(Future<void> Function() action) async {
    try {
      await action();
    } on Exception {
      if (mounted) {
        showKandoToast(context, message: profileActionFailureText);
      }
    }
  }
}

class _AgreementText extends StatelessWidget {
  const _AgreementText({
    required this.termsRecognizer,
    required this.privacyRecognizer,
  });

  final GestureRecognizer termsRecognizer;
  final GestureRecognizer privacyRecognizer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodySmall;
    final linkStyle = bodyStyle?.copyWith(
      color: colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    return RichText(
      key: const Key('auth-agreement-text'),
      textAlign: TextAlign.center,
      text: TextSpan(
        style: bodyStyle,
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Terms of Use',
            style: linkStyle,
            recognizer: termsRecognizer,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: privacyRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

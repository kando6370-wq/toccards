import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../auth_controller.dart';
import 'email_auth_pages.dart';
import '../../profile/profile_actions.dart';

Future<void> showAuthSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    backgroundColor: Colors.transparent,
    builder: (context) => const _AuthSheetFrame(),
  );
}

class _AuthSheetFrame extends StatelessWidget {
  const _AuthSheetFrame();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 399,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            key: const Key('auth-sheet-panel'),
            width: double.infinity,
            height: 343,
            decoration: const BoxDecoration(
              color: KandoColors.ink,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
            child: const _AuthSheet(),
          ),
          Positioned(
            top: 0,
            child: Material(
              key: const Key('auth-sheet-close'),
              color: KandoColors.ink,
              shape: const CircleBorder(
                side: BorderSide(color: Color(0x14FFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: KandoColors.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 57),
      child: SingleChildScrollView(
        child: _showEmail
            ? const EmailAuthPages()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OptionButton(
                    icon: Icons.g_mobiledata,
                    label: 'Continue with Google',
                    enabled: !_loading,
                    onTap: _loading ? null : _continueWithGoogle,
                  ),
                  const SizedBox(height: 14),
                  _OptionButton(
                    icon: Icons.apple,
                    label: 'Continue with Apple',
                    enabled: !_loading,
                    onTap: _loading ? null : _continueWithApple,
                  ),
                  const SizedBox(height: 14),
                  _OptionButton(
                    icon: Icons.mail_outline,
                    label: 'Continue with Email',
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
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
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

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: KandoColors.elevatedSurface,
        shape: const StadiumBorder(side: BorderSide(color: KandoColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: KandoColors.text),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: KandoColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: KandoColors.text, fontSize: 12);
    final linkStyle = bodyStyle?.copyWith(color: KandoColors.accent);

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

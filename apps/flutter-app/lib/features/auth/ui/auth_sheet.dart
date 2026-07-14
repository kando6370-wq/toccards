import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

class _AuthSheetFrame extends StatefulWidget {
  const _AuthSheetFrame();

  @override
  State<_AuthSheetFrame> createState() => _AuthSheetFrameState();
}

class _AuthSheetFrameState extends State<_AuthSheetFrame> {
  var _showOAuthWarning = false;

  @override
  Widget build(BuildContext context) {
    final panelHeight = _showOAuthWarning ? 407.0 : 343.0;

    return SizedBox(
      height: panelHeight + 56,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            key: const Key('auth-sheet-panel'),
            width: double.infinity,
            height: panelHeight,
            decoration: const BoxDecoration(
              color: KandoColors.ink,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
            child: _AuthSheet(
              onOAuthWarningChanged: (value) {
                if (_showOAuthWarning != value) {
                  setState(() => _showOAuthWarning = value);
                }
              },
            ),
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
  const _AuthSheet({required this.onOAuthWarningChanged});

  final ValueChanged<bool> onOAuthWarningChanged;

  @override
  ConsumerState<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<_AuthSheet> {
  var _showOAuthWarning = false;
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
    final options = _showOAuthWarning
        ? [_emailOption(), _googleOption(), _appleOption()]
        : [_googleOption(), _appleOption(), _emailOption()];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 57),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < options.length; index += 1) ...[
              if (index > 0) const SizedBox(height: 14),
              options[index],
            ],
            if (_showOAuthWarning) ...[
              const SizedBox(height: 12),
              _OAuthWarning(
                message: _errorText ?? authAuthorizationFailedMessage,
              ),
            ],
            if (_errorText != null && !_showOAuthWarning) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    }, isOAuth: true);
  }

  Future<void> _continueWithApple() {
    return _run(() {
      return ref.read(authControllerProvider.notifier).continueWithApple();
    }, isOAuth: true);
  }

  _OptionButton _googleOption() {
    return _OptionButton(
      icon: SvgPicture.asset(
        'assets/auth/google.svg',
        key: const Key('auth-google-icon'),
        width: 24,
        height: 24,
      ),
      label: 'Continue with Google',
      enabled: !_loading,
      onTap: _loading ? null : _continueWithGoogle,
    );
  }

  _OptionButton _appleOption() {
    return _OptionButton(
      icon: SvgPicture.asset(
        'assets/auth/apple.svg',
        key: const Key('auth-apple-icon'),
        width: 24,
        height: 24,
      ),
      label: 'Continue with Apple',
      enabled: !_loading,
      onTap: _loading ? null : _continueWithApple,
    );
  }

  _OptionButton _emailOption() {
    return _OptionButton(
      icon: SvgPicture.asset(
        'assets/auth/email.svg',
        key: const Key('auth-email-icon'),
        width: 24,
        height: 24,
      ),
      label: 'Continue with Email',
      enabled: !_loading,
      onTap: _loading ? null : _openEmailAuthPage,
    );
  }

  Future<void> _openEmailAuthPage() async {
    final signedIn = await showEmailAuthPage(context);
    if (signedIn && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required bool isOAuth,
  }) async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
      _errorText = null;
      _showOAuthWarning = false;
    });
    widget.onOAuthWarningChanged(false);
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
        setState(() {
          _errorText = _displayError(error);
          _showOAuthWarning = isOAuth;
        });
        widget.onOAuthWarningChanged(isOAuth);
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

class _OAuthWarning extends StatelessWidget {
  const _OAuthWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('auth-oauth-warning'),
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1FFACC15),
        border: Border.all(color: KandoColors.accent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: KandoColors.accent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 14,
                height: 24 / 14,
                color: KandoColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: KandoColors.elevatedSurface,
        shape: const StadiumBorder(side: BorderSide(color: Color(0x14FFFFFF))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 24, height: 24, child: icon),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontFamily: 'Geist',
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

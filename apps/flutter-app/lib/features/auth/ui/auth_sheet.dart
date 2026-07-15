import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../auth_controller.dart';
import 'email_auth_pages.dart';
import '../../profile/profile_actions.dart';

Future<void> showAuthSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss authentication options',
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (context, _, _) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
            const Align(
              alignment: Alignment.bottomCenter,
              child: _AuthSheetFrame(),
            ),
          ],
        ),
      );
    },
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: panelHeight,
            child: DecoratedBox(
              key: const Key('auth-sheet-panel'),
              decoration: _showOAuthWarning
                  ? const BoxDecoration(
                      color: KandoColors.ink,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: Border.fromBorderSide(
                        BorderSide(color: Color(0x14FFFFFF)),
                      ),
                    )
                  : const BoxDecoration(),
              child: _AuthSheet(
                onOAuthWarningChanged: (value) {
                  if (_showOAuthWarning != value) {
                    setState(() => _showOAuthWarning = value);
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            child: _FigmaAuthCloseAction(
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaAuthCloseAction extends StatelessWidget {
  const _FigmaAuthCloseAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: const Key('auth-sheet-close'),
      dimension: 40,
      child: Tooltip(
        message: 'Dismiss authentication options',
        child: Semantics(
          button: true,
          label: 'Dismiss authentication options',
          onTap: onPressed,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              child: const Image(
                key: Key('auth-options-close-canvas'),
                image: AssetImage('assets/auth/auth_options_close.png'),
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FigmaAuthAction extends StatelessWidget {
  const _FigmaAuthAction({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: onPressed != null,
      onKeyEvent: (_, event) {
        if (onPressed != null &&
            event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          label: label,
          onTap: onPressed,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Opacity(opacity: 0, child: child),
          ),
        ),
      ),
    );
  }
}

class _FigmaAuthOptions extends StatelessWidget {
  const _FigmaAuthOptions({
    required this.onGooglePressed,
    required this.onApplePressed,
    required this.onEmailPressed,
    required this.agreement,
  });

  final VoidCallback? onGooglePressed;
  final VoidCallback? onApplePressed;
  final VoidCallback? onEmailPressed;
  final Widget agreement;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalScale = constraints.maxWidth / 390;
        final verticalScale = constraints.maxHeight / 343;
        return Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                key: Key('auth-options-panel-canvas'),
                child: Image(
                  image: AssetImage(
                    'assets/auth/auth_options_panel_canvas.png',
                  ),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 28 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Google',
                onPressed: onGooglePressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/google.svg',
                    key: const Key('auth-google-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Google',
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 98 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Apple',
                onPressed: onApplePressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/apple.svg',
                    key: const Key('auth-apple-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Apple',
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 168 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Email',
                onPressed: onEmailPressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/email.svg',
                    key: const Key('auth-email-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Email',
                ),
              ),
            ),
            Positioned(
              left: 68 * horizontalScale,
              top: 250 * verticalScale,
              width: 255 * horizontalScale,
              height: 40 * verticalScale,
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: agreement,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HiddenAuthOptionContent extends StatelessWidget {
  const _HiddenAuthOptionContent({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 24, height: 24, child: icon),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _FigmaOAuthFailureOptions extends StatelessWidget {
  const _FigmaOAuthFailureOptions({
    required this.message,
    required this.onGooglePressed,
    required this.onApplePressed,
    required this.onEmailPressed,
    required this.agreement,
  });

  final String message;
  final VoidCallback? onGooglePressed;
  final VoidCallback? onApplePressed;
  final VoidCallback? onEmailPressed;
  final Widget agreement;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalScale = constraints.maxWidth / 390;
        final verticalScale = constraints.maxHeight / 407;
        return Stack(
          children: [
            const Positioned.fill(
              child: RepaintBoundary(
                key: Key('auth-options-failure-panel-canvas'),
                child: Image(
                  image: AssetImage(
                    'assets/auth/auth_failure_panel_canvas.png',
                  ),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 28 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Email',
                onPressed: onEmailPressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/email.svg',
                    key: const Key('auth-email-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Email',
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 98 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Google',
                onPressed: onGooglePressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/google.svg',
                    key: const Key('auth-google-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Google',
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 168 * verticalScale,
              width: 347 * horizontalScale,
              height: 56 * verticalScale,
              child: _FigmaAuthAction(
                label: 'Continue with Apple',
                onPressed: onApplePressed,
                child: _HiddenAuthOptionContent(
                  icon: SvgPicture.asset(
                    'assets/auth/apple.svg',
                    key: const Key('auth-apple-icon'),
                    width: 24,
                    height: 24,
                  ),
                  label: 'Continue with Apple',
                ),
              ),
            ),
            Positioned(
              left: 24 * horizontalScale,
              top: 244 * verticalScale,
              width: 347 * horizontalScale,
              height: 44 * verticalScale,
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: _OAuthWarning(message: message),
              ),
            ),
            Positioned(
              left: 68 * horizontalScale,
              top: 320 * verticalScale,
              width: 255 * horizontalScale,
              height: 40 * verticalScale,
              child: Opacity(
                opacity: 0,
                alwaysIncludeSemantics: true,
                child: agreement,
              ),
            ),
          ],
        );
      },
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
    final agreement = _AgreementText(
      termsRecognizer: _termsRecognizer,
      privacyRecognizer: _privacyRecognizer,
    );
    if (_showOAuthWarning) {
      return _FigmaOAuthFailureOptions(
        message: _errorText ?? authAuthorizationFailedMessage,
        onGooglePressed: _loading ? null : _continueWithGoogle,
        onApplePressed: _loading ? null : _continueWithApple,
        onEmailPressed: _loading ? null : _openEmailAuthPage,
        agreement: agreement,
      );
    }
    if (!_showOAuthWarning && _errorText == null) {
      return _FigmaAuthOptions(
        onGooglePressed: _loading ? null : _continueWithGoogle,
        onApplePressed: _loading ? null : _continueWithApple,
        onEmailPressed: _loading ? null : _openEmailAuthPage,
        agreement: agreement,
      );
    }

    final options = [_googleOption(), _appleOption(), _emailOption()];

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
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 32),
            agreement,
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
    final successMessage = await showEmailAuthPage(context);
    if (successMessage != null && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(buildKandoToast(successMessage));
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

import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/ui/kando_modal.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../auth_controller.dart';
import 'email_auth_pages.dart';
import '../../home/home_controller.dart';
import '../../profile/profile_actions.dart';

Future<void> showAuthSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss authentication options',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, _) =>
        _AuthSheetDialog(animation: animation),
  );
}

class _AuthSheetDialog extends StatelessWidget {
  const _AuthSheetDialog({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final overlayAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final sheetAnimation = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: overlayAnimation,
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
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FadeTransition(
              opacity: sheetAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(sheetAnimation),
                child: const _AuthSheetFrame(),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
              decoration: const BoxDecoration(),
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
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
              child: Material(
                color: KandoColors.ink,
                shape: const CircleBorder(
                  side: BorderSide(color: KandoColors.borderSubtle),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: const Center(
                    child: SizedBox(
                      key: Key('auth-options-close-canvas'),
                      width: 11,
                      height: 6,
                      child: CustomPaint(painter: _DownChevronPainter()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownChevronPainter extends CustomPainter {
  const _DownChevronPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = KandoColors.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(0.5, 0.75)
      ..lineTo(size.width / 2, size.height - 0.75)
      ..lineTo(size.width - 0.5, 0.75);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    return _AuthOptionsPanel(
      key: const Key('auth-options-panel-canvas'),
      footer: agreement,
      children: [
        _OptionButton(
          key: const Key('auth-google-option'),
          icon: const _GoogleAuthIcon(key: Key('auth-google-icon')),
          label: 'Continue with Google',
          enabled: onGooglePressed != null,
          onTap: onGooglePressed,
        ),
        _OptionButton(
          key: const Key('auth-apple-option'),
          icon: const Icon(
            Icons.apple,
            key: Key('auth-apple-icon'),
            color: KandoColors.softAccent,
            size: 28,
          ),
          label: 'Continue with Apple',
          enabled: onApplePressed != null,
          onTap: onApplePressed,
        ),
        _OptionButton(
          key: const Key('auth-email-option'),
          icon: const Icon(
            Icons.mail_outline_rounded,
            key: Key('auth-email-icon'),
            color: KandoColors.text,
            size: 24,
          ),
          label: 'Continue with Email',
          enabled: onEmailPressed != null,
          onTap: onEmailPressed,
        ),
      ],
    );
  }
}

class _GoogleAuthIcon extends StatelessWidget {
  const _GoogleAuthIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.square(
      dimension: 24,
      child: CustomPaint(painter: _GoogleAuthIconPainter()),
    );
  }
}

class _GoogleAuthIconPainter extends CustomPainter {
  const _GoogleAuthIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.scale(scale);

    const strokeWidth = 4.2;
    final rect = Rect.fromCircle(center: const Offset(12, 12), radius: 8.1);

    Paint stroke(Color color) {
      return Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
    }

    canvas.drawArc(rect, -0.05, 1.23, false, stroke(const Color(0xFF38BDF8)));
    canvas.drawArc(rect, 1.12, 1.48, false, stroke(const Color(0xFF4ADE80)));
    canvas.drawArc(rect, 2.50, 0.92, false, stroke(const Color(0xFFFFF6AF)));
    canvas.drawArc(rect, 3.36, 1.62, false, stroke(const Color(0xFFFF8989)));

    final blue = stroke(const Color(0xFF38BDF8))..strokeCap = StrokeCap.square;
    canvas.drawLine(const Offset(12, 12), const Offset(20.4, 12), blue);
    canvas.drawLine(const Offset(20.4, 12), const Offset(20.4, 12.1), blue);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AuthOptionsPanel extends StatelessWidget {
  const _AuthOptionsPanel({
    required this.children,
    required this.footer,
    this.warning,
    super.key,
  });

  final List<Widget> children;
  final Widget? warning;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: KandoColors.ink,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0x14FFFFFF)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index += 1) ...[
                    if (index > 0) const SizedBox(height: 14),
                    children[index],
                  ],
                  SizedBox(height: warning == null ? 21 : 20),
                  if (warning != null) ...[
                    warning!,
                    const SizedBox(height: 21),
                  ],
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: footer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const _AuthHomeIndicator(),
      ],
    );
  }
}

class _AuthHomeIndicator extends StatelessWidget {
  const _AuthHomeIndicator();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KandoColors.ink,
      child: SizedBox(
        key: const Key('auth-home-indicator'),
        height: 25.154,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: KandoColors.softAccent,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: const SizedBox(width: 134, height: 5),
              ),
            ),
          ],
        ),
      ),
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
    return _AuthOptionsPanel(
      key: const Key('auth-options-failure-panel-canvas'),
      warning: _OAuthWarning(message: message),
      footer: agreement,
      children: [
        _OptionButton(
          key: const Key('auth-email-option'),
          icon: const Icon(
            Icons.mail_outline_rounded,
            key: Key('auth-email-icon'),
            color: KandoColors.text,
            size: 24,
          ),
          label: 'Continue with Email',
          enabled: onEmailPressed != null,
          onTap: onEmailPressed,
        ),
        _OptionButton(
          key: const Key('auth-google-option'),
          icon: const _GoogleAuthIcon(key: Key('auth-google-icon')),
          label: 'Continue with Google',
          enabled: onGooglePressed != null,
          onTap: onGooglePressed,
        ),
        _OptionButton(
          key: const Key('auth-apple-option'),
          icon: const Icon(
            Icons.apple,
            key: Key('auth-apple-icon'),
            color: KandoColors.softAccent,
            size: 28,
          ),
          label: 'Continue with Apple',
          enabled: onApplePressed != null,
          onTap: onApplePressed,
        ),
      ],
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
      icon: const _GoogleAuthIcon(key: Key('auth-google-icon')),
      label: 'Continue with Google',
      enabled: !_loading,
      onTap: _loading ? null : _continueWithGoogle,
    );
  }

  _OptionButton _appleOption() {
    return _OptionButton(
      icon: const Icon(
        Icons.apple,
        key: Key('auth-apple-icon'),
        color: KandoColors.softAccent,
        size: 28,
      ),
      label: 'Continue with Apple',
      enabled: !_loading,
      onTap: _loading ? null : _continueWithApple,
    );
  }

  _OptionButton _emailOption() {
    return _OptionButton(
      icon: const Icon(
        Icons.mail_outline_rounded,
        key: Key('auth-email-icon'),
        color: KandoColors.text,
        size: 24,
      ),
      label: 'Continue with Email',
      enabled: !_loading,
      onTap: _loading ? null : _openEmailAuthPage,
    );
  }

  Future<void> _openEmailAuthPage() async {
    final successMessage = await showEmailAuthPage(context);
    if (successMessage != null && mounted) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      final rootContext = rootNavigator.context;
      final messenger = ScaffoldMessenger.of(context);
      final router = GoRouter.of(context);
      ref.read(homeControllerProvider);
      Navigator.of(context).pop();
      _goHomeAfterAuthSettles(router);

      final toastCopy = _successToastCopy(successMessage);
      if (toastCopy != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!rootNavigator.mounted) {
            return;
          }
          _showCenteredAuthSuccessToast(
            rootContext,
            title: toastCopy.title,
            message: toastCopy.message,
          );
        });
        return;
      }

      final modalCopy = _successModalCopy(successMessage);
      if (modalCopy == null) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            buildKandoToast(
              successMessage,
              onClose: messenger.hideCurrentSnackBar,
            ),
          );
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!rootNavigator.mounted) {
          return;
        }
        unawaited(
          showKandoWelcomeModal(
            rootContext,
            title: modalCopy.title,
            message: modalCopy.message,
          ),
        );
      });
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
        final router = GoRouter.of(context);
        ref.read(homeControllerProvider);
        Navigator.of(context).pop();
        _goHomeAfterAuthSettles(router);
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

  void _showCenteredAuthSuccessToast(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: title,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => Center(
          child: _AuthSuccessToast(title: title, message: message),
        ),
      ),
    );
  }

  void _goHomeAfterAuthSettles(GoRouter router) {
    WidgetsBinding.instance.addPostFrameCallback((_) => router.go('/home'));
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

class _AuthSuccessToast extends StatelessWidget {
  const _AuthSuccessToast({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('auth-success-toast'),
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
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: Color(0xFFF1FE70),
                      fontFamily: 'Fraunces',
                      fontSize: 24,
                      height: 32 / 24,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(
                      color: Color(0xFFE3E3D6),
                      fontFamily: 'Geist',
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
    super.key,
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
    const bodyStyle = TextStyle(
      color: KandoColors.text,
      fontFamily: 'Geist',
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
    );
    const linkStyle = TextStyle(
      color: KandoColors.accent,
      fontFamily: 'Geist',
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
    );

    return SizedBox(
      key: const Key('auth-agreement-text'),
      width: 300,
      height: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'By continuing, you agree to our',
            key: Key('auth-agreement-copy'),
            textAlign: TextAlign.center,
            maxLines: 1,
            textScaler: TextScaler.noScaling,
            textHeightBehavior: TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: bodyStyle,
          ),
          RichText(
            key: const Key('auth-agreement-links'),
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            text: TextSpan(
              style: bodyStyle,
              children: [
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

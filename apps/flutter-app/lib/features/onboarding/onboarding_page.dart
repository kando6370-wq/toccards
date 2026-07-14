import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

import '../auth/auth_controller.dart';
import '../auth/ui/auth_sheet.dart';
import 'onboarding_controller.dart';

class OnboardingPage extends ConsumerWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _OnboardingEntry(
      onAuthenticate: () async {
        await showAuthSheet(context);
        if (ref.read(authControllerProvider).session?.isUser ?? false) {
          ref.read(onboardingControllerProvider.notifier).complete();
        }
      },
      onContinueAsGuest: () {
        ref.read(onboardingControllerProvider.notifier).complete();
      },
    );
  }
}

class _OnboardingEntry extends StatelessWidget {
  const _OnboardingEntry({
    required this.onAuthenticate,
    required this.onContinueAsGuest,
  });

  final VoidCallback onAuthenticate;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('onboarding-entry'),
      backgroundColor: KandoColors.ink,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalScale = constraints.maxWidth / 390;
          final verticalScale = constraints.maxHeight / 844;
          return Stack(
            children: [
              const Positioned.fill(
                child: Image(
                  key: ValueKey('figma-onboarding-entry-canvas'),
                  image: AssetImage('assets/onboarding/entry_canvas.png'),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.none,
                ),
              ),
              Positioned(
                left: 20 * horizontalScale,
                top: 647 * verticalScale,
                width: 350 * horizontalScale,
                height: 56 * verticalScale,
                child: _FigmaEntryAction(
                  tooltip: 'Sign In / Sign Up',
                  onPressed: onAuthenticate,
                ),
              ),
              Positioned(
                left: 110 * horizontalScale,
                top: 715 * verticalScale,
                width: 170 * horizontalScale,
                height: 48 * verticalScale,
                child: _FigmaEntryAction(
                  tooltip: 'Skip and start now',
                  onPressed: onContinueAsGuest,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FigmaEntryAction extends StatelessWidget {
  const _FigmaEntryAction({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Tooltip(
            message: tooltip,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  button: true,
                  label: tooltip,
                  onTap: onPressed,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onPressed,
                    child: const SizedBox.expand(),
                  ),
                ),
                if (hasFocus)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: KandoColors.accent, width: 2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

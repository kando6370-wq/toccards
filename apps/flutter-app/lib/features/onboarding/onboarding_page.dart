import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: constraints.maxHeight >= 844 ? 141.154 : 116,
                  child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: onAuthenticate,
                      style: FilledButton.styleFrom(
                        backgroundColor: KandoColors.accent,
                        foregroundColor: KandoColors.ink,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                          letterSpacing: 0,
                        ),
                      ),
                      child: const Text('Sign In / Sign Up'),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: constraints.maxHeight >= 844 ? 102.154 : 77,
                  child: Center(
                    child: TextButton(
                      onPressed: onContinueAsGuest,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF92927D),
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 16 / 13,
                          letterSpacing: 0,
                        ),
                      ),
                      child: const Text('Skip and start now'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

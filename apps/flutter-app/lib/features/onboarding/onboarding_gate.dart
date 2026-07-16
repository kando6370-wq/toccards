import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../shared/ui/kando_style.dart';
import 'onboarding_controller.dart';
import 'onboarding_page.dart';

class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({required this.home, super.key});

  final Widget home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(onboardingControllerProvider)
        .when(
          data: (completed) => completed ? home : const OnboardingPage(),
          loading: () => const _StartupPage(),
          error: (_, _) => const OnboardingPage(),
        );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const ValueKey('onboarding-loading'),
      color: KandoColors.ink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / 390;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: constraints.maxHeight * 295 / 884,
                child: SizedBox(
                  width: 112 * scale,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 112 * scale,
                        height: 112 * scale,
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/branding/card_ai_mark.svg',
                            width: 80 * scale,
                            height: 80 * scale,
                          ),
                        ),
                      ),
                      SizedBox(height: 8 * scale),
                      Text(
                        'Card AI',
                        style: TextStyle(
                          color: KandoColors.accent,
                          fontFamily: 'Fraunces',
                          fontSize: 24 * scale,
                          fontWeight: FontWeight.w600,
                          height: 32 / 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: constraints.maxHeight * 103 / 884,
                child: SizedBox(
                  width: 280 * scale,
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          24 * scale,
                          0,
                          24 * scale,
                          16 * scale,
                        ),
                        child: LinearProgressIndicator(
                          minHeight: 2 * scale,
                          color: KandoColors.accent,
                          backgroundColor: const Color(0xFF34362D),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                      Text(
                        'LOADING YOUR COLLECTION...',
                        style: TextStyle(
                          color: KandoColors.mutedText,
                          fontSize: 12 * scale,
                          height: 16 / 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

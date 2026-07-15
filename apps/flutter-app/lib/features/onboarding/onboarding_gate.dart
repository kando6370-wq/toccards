import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          loading: () => const ColoredBox(
            key: ValueKey('onboarding-loading'),
            color: KandoColors.ink,
          ),
          error: (_, _) => const OnboardingPage(),
        );
  }
}

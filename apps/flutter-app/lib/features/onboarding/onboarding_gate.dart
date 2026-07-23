import 'dart:math' as math;

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
          loading: () => const _StartupPage(),
          error: (_, _) => const OnboardingPage(),
        );
  }
}

class _StartupPage extends StatefulWidget {
  const _StartupPage();

  @override
  State<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<_StartupPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: OnboardingController.minimumSplashDuration,
    )..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('onboarding-loading'),
      color: KandoColors.ink,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = math.min(
            constraints.maxWidth / 390,
            constraints.maxHeight / 844,
          );
          final verticalInset = (constraints.maxHeight - 844 * scale) / 2;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: verticalInset + 255 * scale,
                child: SizedBox(
                  key: const ValueKey('onboarding-loading-branding'),
                  width: 116 * scale,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 112 * scale,
                        height: 112 * scale,
                        child: Center(
                          child: Image.asset(
                            'assets/onboarding/splash_mark.png',
                            width: 90 * scale,
                            height: 90 * scale,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      SizedBox(height: 8 * scale),
                      SizedBox(
                        width: 116 * scale,
                        height: 40 * scale,
                        child: Text(
                          'Card AI',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: KandoColors.accent,
                            fontFamily: 'Fraunces',
                            fontSize: 32 * scale,
                            fontWeight: FontWeight.w400,
                            height: 40 / 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: verticalInset + 103 * scale,
                child: SizedBox(
                  key: const ValueKey('onboarding-loading-progress'),
                  width: 280 * scale,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 232 * scale,
                        height: 2 * scale,
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return Semantics(
                              value:
                                  '${(_progressController.value * 100).round()}%',
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  key: const ValueKey(
                                    'onboarding-loading-progress-fill',
                                  ),
                                  width:
                                      232 * scale * _progressController.value,
                                  height: 2 * scale,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: KandoColors.accent,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16 * scale),
                      SizedBox(
                        width: 170 * scale,
                        height: 16 * scale,
                        child: Text(
                          'LOADING YOUR COLLECTION...',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: KandoColors.mutedText,
                            fontSize: 12 * scale,
                            height: 16 / 12,
                          ),
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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_startup_preloader.dart';
import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import '../../shared/ui/kando_style.dart';
import 'onboarding_controller.dart';
import 'onboarding_page.dart';

class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({required this.home, this.firstLaunchHome, super.key});

  final Widget home;
  final Widget? firstLaunchHome;

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  var _requiredOnboarding = false;

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(onboardingControllerProvider)
        .when(
          data: (completed) {
            if (!completed) {
              _requiredOnboarding = true;
              return const OnboardingPage();
            }
            return _requiredOnboarding
                ? widget.firstLaunchHome ?? widget.home
                : widget.home;
          },
          loading: () => const _StartupPage(),
          error: (_, _) => const OnboardingPage(),
        );
  }
}

class _StartupPage extends ConsumerStatefulWidget {
  const _StartupPage();

  @override
  ConsumerState<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends ConsumerState<_StartupPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.splashView);
    _progressController = AnimationController(vsync: this, value: 0);
    unawaited(_runPendingProgress());
  }

  Future<void> _runPendingProgress() async {
    try {
      await _progressController.animateTo(
        .8,
        duration: OnboardingController.minimumSplashDuration,
        curve: Curves.easeOutCubic,
      );
      if (!mounted || ref.read(startupProgressFinishingProvider)) return;
      await _progressController.animateTo(
        .99,
        duration:
            appStartupPreloadTimeout -
            OnboardingController.minimumSplashDuration,
        curve: Curves.easeOut,
      );
    } on TickerCanceled {
      // A completion animation superseded the pending animation.
    }
  }

  Future<void> _finishProgress() async {
    try {
      await _progressController.animateTo(
        1,
        duration: OnboardingController.progressCompletionDuration,
        curve: Curves.easeOut,
      );
    } on TickerCanceled {
      // The splash was disposed while the route changed.
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useIosLaunchMark = defaultTargetPlatform == TargetPlatform.iOS;
    ref.listen<bool>(startupProgressFinishingProvider, (previous, next) {
      if (next && previous != true) unawaited(_finishProgress());
    });
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
          final brandingTop = useIosLaunchMark
              ? constraints.maxHeight * (311 / 844) - 56 * scale
              : constraints.maxHeight / 2 - 56 * scale;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: brandingTop,
                child: SizedBox(
                  key: const ValueKey('onboarding-loading-branding'),
                  width: 116 * scale,
                  child: Column(
                    children: [
                      SizedBox(
                        width: 112 * scale,
                        height: 112 * scale,
                        child: Center(
                          child: useIosLaunchMark
                              ? Image.asset(
                                  'assets/onboarding/splash_mark_ios.png',
                                  key: const ValueKey(
                                    'onboarding-loading-logo',
                                  ),
                                  width: 76,
                                  height: 92,
                                  filterQuality: FilterQuality.high,
                                )
                              : Image.asset(
                                  'assets/onboarding/splash_mark.png',
                                  key: const ValueKey(
                                    'onboarding-loading-logo',
                                  ),
                                  width: 76,
                                  height: 92,
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
                        height: 3 * scale,
                        child: DecoratedBox(
                          key: const ValueKey(
                            'onboarding-loading-progress-track',
                          ),
                          decoration: BoxDecoration(
                            color: KandoColors.border,
                            borderRadius: BorderRadius.circular(9999),
                          ),
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
                                    height: 3 * scale,
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

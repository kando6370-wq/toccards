import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_startup_preloader.dart';
import '../../shared/attribution/app_attribution.dart';
import 'onboarding_repository.dart';

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

final startupProgressFinishingProvider =
    NotifierProvider<StartupProgressFinishingController, bool>(
      StartupProgressFinishingController.new,
    );

class StartupProgressFinishingController extends Notifier<bool> {
  @override
  bool build() => false;

  void finish() => state = true;
}

class OnboardingController extends AsyncNotifier<bool> {
  static const minimumSplashDuration = Duration(seconds: 3);
  static const progressCompletionDuration = Duration(milliseconds: 180);
  static const completedProgressHoldDuration = Duration(milliseconds: 120);

  @override
  Future<bool> build() async {
    final completed = ref.watch(onboardingRepositoryProvider).readCompleted();
    await Future.wait<void>([
      Future<void>.delayed(minimumSplashDuration),
      ref.watch(appStartupPreloaderProvider.future),
    ]);
    final completedValue = await completed;
    await ref
        .read(appAttributionCoordinatorProvider)
        .prepareForStartup(firstInstall: !completedValue);
    ref.read(startupProgressFinishingProvider.notifier).finish();
    await Future<void>.delayed(
      progressCompletionDuration + completedProgressHoldDuration,
    );
    return completedValue;
  }

  Future<bool> complete() async {
    try {
      await ref.read(onboardingRepositoryProvider).markCompleted();
      if (!ref.mounted) return false;
      state = const AsyncData(true);
      return true;
    } catch (_) {
      return false;
    }
  }
}

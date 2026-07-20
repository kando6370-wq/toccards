import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_repository.dart';

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends AsyncNotifier<bool> {
  static const minimumSplashDuration = Duration(milliseconds: 1200);

  @override
  Future<bool> build() async {
    final completed = ref.watch(onboardingRepositoryProvider).readCompleted();
    await Future<void>.delayed(minimumSplashDuration);
    return completed;
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

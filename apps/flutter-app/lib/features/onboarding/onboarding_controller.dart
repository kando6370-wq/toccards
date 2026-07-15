import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_repository.dart';

final onboardingControllerProvider =
    AsyncNotifierProvider<OnboardingController, bool>(OnboardingController.new);

class OnboardingController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(onboardingRepositoryProvider).readCompleted();
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

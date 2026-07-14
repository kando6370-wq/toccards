import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'onboarding_repository.dart';

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingState {
  const OnboardingState({required this.slides, required this.completed});

  final List<OnboardingSlide> slides;
  final bool completed;

  bool get shouldShow => !completed;

  OnboardingState copyWith({bool? completed}) {
    return OnboardingState(
      slides: slides,
      completed: completed ?? this.completed,
    );
  }
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() {
    final repository = ref.watch(onboardingRepositoryProvider);
    return OnboardingState(
      slides: repository.loadSlides(),
      completed: repository.readCompleted(),
    );
  }

  void complete() {
    ref.read(onboardingRepositoryProvider).markCompleted();
    state = state.copyWith(completed: true);
  }
}

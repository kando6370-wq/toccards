import 'package:kando_app/features/onboarding/onboarding_repository.dart';

class InMemoryOnboardingStorage implements OnboardingStorage {
  InMemoryOnboardingStorage({bool completed = false}) : _completed = completed;

  bool _completed;

  @override
  Future<bool> readCompleted() async => _completed;

  @override
  Future<void> writeCompleted() async {
    _completed = true;
  }
}

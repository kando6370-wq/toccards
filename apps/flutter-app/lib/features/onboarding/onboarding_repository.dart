import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final onboardingStorageProvider = Provider<OnboardingStorage>((ref) {
  return const PreferencesOnboardingStorage();
});

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return LocalOnboardingRepository(ref.watch(onboardingStorageProvider));
});

abstract interface class OnboardingStorage {
  Future<bool> readCompleted();
  Future<void> writeCompleted();
}

class PreferencesOnboardingStorage implements OnboardingStorage {
  const PreferencesOnboardingStorage();

  static const _completedKey = 'onboarding.completed';

  @override
  Future<bool> readCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_completedKey) ?? false;
  }

  @override
  Future<void> writeCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_completedKey, true);
  }
}

abstract interface class OnboardingRepository {
  Future<bool> readCompleted();
  Future<void> markCompleted();
}

class LocalOnboardingRepository implements OnboardingRepository {
  const LocalOnboardingRepository(this._storage);

  final OnboardingStorage _storage;

  @override
  Future<bool> readCompleted() => _storage.readCompleted();

  @override
  Future<void> markCompleted() => _storage.writeCompleted();
}

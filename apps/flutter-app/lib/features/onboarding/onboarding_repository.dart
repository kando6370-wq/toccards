import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final onboardingStorageProvider = Provider<OnboardingStorage>((ref) {
  return const SecureOnboardingStorage();
});

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return LocalOnboardingRepository(ref.watch(onboardingStorageProvider));
});

abstract interface class OnboardingStorage {
  Future<bool> readCompleted();
  Future<void> writeCompleted();
}

class SecureOnboardingStorage implements OnboardingStorage {
  const SecureOnboardingStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _completedKey = 'onboarding.completed';

  final FlutterSecureStorage _storage;

  @override
  Future<bool> readCompleted() async {
    return await _storage.read(key: _completedKey) == 'true';
  }

  @override
  Future<void> writeCompleted() {
    return _storage.write(key: _completedKey, value: 'true');
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

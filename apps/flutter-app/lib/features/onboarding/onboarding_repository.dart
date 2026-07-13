import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingStorageProvider = Provider<InMemoryOnboardingStorage>((ref) {
  return InMemoryOnboardingStorage();
});

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return LocalOnboardingRepository(ref.watch(onboardingStorageProvider));
});

class OnboardingSlide {
  const OnboardingSlide({
    required this.imageUrl,
    required this.title,
    required this.body,
  });

  final String imageUrl;
  final String title;
  final String body;
}

class InMemoryOnboardingStorage {
  bool _completed;

  InMemoryOnboardingStorage({bool completed = false}) : _completed = completed;

  bool readCompleted() => _completed;

  void writeCompleted() {
    _completed = true;
  }
}

abstract class OnboardingRepository {
  List<OnboardingSlide> loadSlides();
  bool readCompleted();
  void markCompleted();
}

class LocalOnboardingRepository implements OnboardingRepository {
  LocalOnboardingRepository(this._storage, {List<OnboardingSlide>? slides})
    : _slides = List.unmodifiable(slides ?? _defaultSlides);

  static const _defaultSlides = [
    OnboardingSlide(
      imageUrl: 'local://onboarding/collection',
      title: 'Track your collection',
      body: 'Keep your cards, folders, and wishlist organized in one place.',
    ),
    OnboardingSlide(
      imageUrl: 'local://onboarding/market',
      title: 'Follow market moves',
      body: 'See portfolio value, price changes, and trending cards quickly.',
    ),
    OnboardingSlide(
      imageUrl: 'local://onboarding/scan',
      title: 'Scan and add cards',
      body: 'Use the scan flow to move from card discovery to collection.',
    ),
  ];

  final InMemoryOnboardingStorage _storage;
  final List<OnboardingSlide> _slides;

  @override
  List<OnboardingSlide> loadSlides() => _slides;

  @override
  bool readCompleted() => _storage.readCompleted();

  @override
  void markCompleted() {
    _storage.writeCompleted();
  }
}

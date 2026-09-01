import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/collection/collection_controller.dart';
import '../features/home/home_controller.dart';
import '../features/search/search_controller.dart';
import '../shared/ui/load_state.dart';

const appStartupPreloadTimeout = Duration(seconds: 8);
const searchImagePreloadLimit = 20;

typedef NetworkImagePreloader = Future<void> Function(List<String> imageUrls);

final networkImagePreloaderProvider = Provider<NetworkImagePreloader>((ref) {
  return _preloadNetworkImages;
});

final appStartupPreloaderProvider = FutureProvider<void>((ref) async {
  var initialPreloadPending = true;
  ref.listen(authControllerProvider, (previous, next) {
    final session = next.session;
    if (initialPreloadPending ||
        session == null ||
        identical(previous?.session, session)) {
      return;
    }

    unawaited(
      Future<void>.microtask(() async {
        if (ref.mounted) await _preloadForCurrentSession(ref);
      }),
    );
  });

  final initialPreload = _preloadInitialSession(ref).whenComplete(() {
    initialPreloadPending = false;
  });
  try {
    await initialPreload.timeout(appStartupPreloadTimeout);
  } on TimeoutException {
    if (ref.mounted && ref.read(authControllerProvider).session != null) {
      _startSecondaryTabPreload(ref);
    }
  }
});

Future<void> _preloadInitialSession(Ref ref) async {
  await ref.read(authControllerProvider.notifier).startupComplete;
  if (!ref.mounted || ref.read(authControllerProvider).session == null) {
    return;
  }

  // Auth-dependent providers are invalidated in the same notification cycle.
  // Start tab reads after that propagation so all requests use the new session.
  await Future<void>.delayed(Duration.zero);
  if (!ref.mounted) return;
  await _preloadForCurrentSession(ref);
}

Future<void> _preloadForCurrentSession(Ref ref) async {
  ref.read(homeControllerProvider);
  final home = ref.read(homeControllerProvider.notifier);
  final coreResult = await home.coreLoadComplete;
  if (!ref.mounted) return;
  if (coreResult == HomeCoreLoadResult.content) {
    final scheduledImageUrls = <String>{};
    final state = ref.read(homeControllerProvider);
    unawaited(
      _preloadImageUrls(
        ref,
        state.mostValuableCards.map((card) => card.imageUrl),
        scheduledImageUrls,
      ),
    );
    unawaited(
      _preloadHomeTrendingImages(
        ref,
        home.trendingLoadComplete,
        scheduledImageUrls,
      ),
    );
  }
  if (ref.mounted) _startSecondaryTabPreload(ref);
}

Future<void> _preloadHomeTrendingImages(
  Ref ref,
  Future<void> trendingLoad,
  Set<String> scheduledImageUrls,
) async {
  await trendingLoad;
  if (!ref.mounted) return;
  final state = ref.read(homeControllerProvider);
  if (state.isUnavailable || state.trendingStatus != KandoLoadStatus.content) {
    return;
  }
  await _preloadImageUrls(
    ref,
    state.dashboard.trending.map((card) => card.imageUrl),
    scheduledImageUrls,
  );
}

void _startSecondaryTabPreload(Ref ref) {
  if (!ref.mounted) return;
  final collection = ref.read(collectionControllerProvider.notifier);
  final search = ref.read(searchControllerProvider.notifier);

  // These loads warm secondary tabs but never delay entry into Home.
  unawaited(
    Future.wait<void>([
      collection.loadComplete,
      _preloadSearchImages(ref, search.loadComplete),
    ]),
  );
}

Future<void> _preloadSearchImages(Ref ref, Future<void> searchLoad) async {
  await searchLoad;
  if (!ref.mounted) return;
  final state = ref.read(searchControllerProvider);
  if (state.isLoading || state.isUnavailable) return;

  final imageUrls = state.visibleCards
      .take(searchImagePreloadLimit)
      .map((card) => card.imageUrl?.trim())
      .toList(growable: false);
  await _preloadImageUrls(ref, imageUrls, <String>{});
}

Future<void> _preloadImageUrls(
  Ref ref,
  Iterable<String?> candidateUrls,
  Set<String> scheduledImageUrls,
) async {
  final imageUrls = candidateUrls
      .map((url) => url?.trim())
      .whereType<String>()
      .where((url) => url.isNotEmpty && scheduledImageUrls.add(url))
      .toList(growable: false);
  if (imageUrls.isEmpty) return;

  try {
    await ref.read(networkImagePreloaderProvider)(imageUrls);
  } catch (_) {
    // Image warming is best effort and must not affect app startup.
  }
}

Future<void> _preloadNetworkImages(List<String> imageUrls) {
  return Future.wait<void>(imageUrls.map(_preloadNetworkImage));
}

Future<void> _preloadNetworkImage(String imageUrl) {
  final completer = Completer<void>();
  final stream = NetworkImage(imageUrl).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (_, _) {
      if (!completer.isCompleted) completer.complete();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        stream.removeListener(listener);
      });
    },
    onError: (_, _) {
      if (!completer.isCompleted) completer.complete();
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

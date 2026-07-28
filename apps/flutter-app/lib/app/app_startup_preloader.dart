import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/collection/collection_controller.dart';
import '../features/home/home_controller.dart';
import '../features/search/search_controller.dart';
import '../shared/ui/load_state.dart';

const appStartupPreloadTimeout = Duration(seconds: 8);

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
        if (ref.mounted) await _preloadMainTabs(ref);
      }),
    );
  });

  await ref.read(authControllerProvider.notifier).startupComplete;
  if (!ref.mounted || ref.read(authControllerProvider).session == null) {
    initialPreloadPending = false;
    return;
  }

  // Auth-dependent providers are invalidated in the same notification cycle.
  // Start tab reads after that propagation so all requests use the new session.
  await Future<void>.delayed(Duration.zero);
  if (ref.mounted) await _preloadMainTabs(ref);
  initialPreloadPending = false;
});

Future<void> _preloadMainTabs(Ref ref) async {
  ref.read(homeControllerProvider);
  final collection = ref.read(collectionControllerProvider.notifier);
  final search = ref.read(searchControllerProvider.notifier);

  try {
    await Future.wait<void>([
      _waitForHome(ref),
      collection.loadComplete,
      search.loadComplete,
    ]).timeout(appStartupPreloadTimeout);
  } on TimeoutException {
    // Continue into the app; individual pages retain their loading/failure UI.
  }
}

Future<void> _waitForHome(Ref ref) async {
  while (ref.mounted) {
    final state = ref.read(homeControllerProvider);
    if (!state.isLoading && state.trendingStatus != KandoLoadStatus.loading) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

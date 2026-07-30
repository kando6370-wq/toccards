import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import '../features/collection/collection_controller.dart';
import '../features/home/home_controller.dart';
import '../features/search/search_controller.dart';

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
  await ref.read(homeControllerProvider.notifier).coreLoadComplete;
  if (ref.mounted) _startSecondaryTabPreload(ref);
}

void _startSecondaryTabPreload(Ref ref) {
  if (!ref.mounted) return;
  final collection = ref.read(collectionControllerProvider.notifier);
  final search = ref.read(searchControllerProvider.notifier);

  // These loads warm secondary tabs but never delay entry into Home.
  unawaited(Future.wait<void>([collection.loadComplete, search.loadComplete]));
}

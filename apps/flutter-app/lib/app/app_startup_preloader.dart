import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_controller.dart';
import '../features/search/search_controller.dart';

final appStartupPreloaderProvider = Provider<void>((ref) {
  // Home owns the startup critical path. Search warms only after Home settles
  // so cold start does not burst both modules' requests at once.
  ref.listen(homeControllerProvider, (_, next) {
    if (!next.isLoading) {
      ref.read(searchControllerProvider);
    }
  }, fireImmediately: true);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_controller.dart';
import '../features/search/search_controller.dart';

final appStartupPreloaderProvider = Provider<void>((ref) {
  // Keep both controllers active so they react when auth restoration completes.
  // Their listeners own the cache; neither page is built offstage.
  ref.listen(homeControllerProvider, (_, _) {});
  ref.listen(searchControllerProvider, (_, _) {});
});

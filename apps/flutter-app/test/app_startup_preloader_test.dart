import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';

import 'support/mock_home_repository.dart';
import 'support/mock_search_repository.dart';

void main() {
  test(
    'startup preloader initializes Home and Search data controllers',
    () async {
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(const MockHomeRepository()),
          searchRepositoryProvider.overrideWithValue(
            const MockSearchRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(appStartupPreloaderProvider);
      await container.read(searchControllerProvider.notifier).loadComplete;

      expect(container.read(homeControllerProvider).isLoading, isFalse);
      expect(container.read(searchControllerProvider).isLoading, isFalse);
    },
  );

  test(
    'startup preloader waits for Home before Search because the first screen owns cold-start bandwidth',
    () async {
      final home = _PendingHomeRepository();
      final search = _CountingSearchRepository();
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(home),
          searchRepositoryProvider.overrideWithValue(search),
        ],
      );
      addTearDown(container.dispose);

      container.read(appStartupPreloaderProvider);
      await Future<void>.delayed(Duration.zero);
      expect(search.loadCount, 0);

      home.result.complete(mockHomeDashboard);
      for (var attempt = 0; attempt < 10 && search.loadCount == 0; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(search.loadCount, 1);
      await container.read(searchControllerProvider.notifier).loadComplete;
    },
  );
}

class _PendingHomeRepository implements HomeRepository {
  final result = Completer<HomeDashboard>();

  @override
  Future<HomeDashboard> loadDashboard() => result.future;
}

class _CountingSearchRepository extends MockSearchRepository {
  int loadCount = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    loadCount++;
    return super.loadCatalog();
  }
}

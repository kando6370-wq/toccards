import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/app/app_startup_preloader.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/search/search_controller.dart';

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
}

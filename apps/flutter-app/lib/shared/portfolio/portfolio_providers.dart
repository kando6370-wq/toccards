import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_request_log.dart';
import '../debug/app_debug_overlay.dart';
import 'portfolio_api_client.dart';

final portfolioDioProvider = Provider((ref) {
  final dio = createPortfolioDio();
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  addAppDebugHttpLogging(dio);
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
  );
  ref.onDispose(dio.close);
  return dio;
});

final portfolioApiClientProvider = Provider<PortfolioApiClient>((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});

final portfolioManagementApiProvider = Provider<PortfolioManagementApi>((ref) {
  return PortfolioApiClient(ref.watch(portfolioDioProvider));
});

final selectedPortfolioFolderProvider =
    NotifierProvider<SelectedPortfolioFolderController, String?>(
      SelectedPortfolioFolderController.new,
    );

class SelectedPortfolioFolderController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String folderId) {
    state = folderId;
  }
}

abstract interface class PortfolioAmountHiddenStorage {
  Future<bool> readAmountHidden();
  Future<void> writeAmountHidden(bool amountHidden);
}

class PreferencesPortfolioAmountHiddenStorage
    implements PortfolioAmountHiddenStorage {
  const PreferencesPortfolioAmountHiddenStorage();

  static const storageKey = 'portfolio.amount_hidden';

  @override
  Future<bool> readAmountHidden() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(storageKey) ?? false;
  }

  @override
  Future<void> writeAmountHidden(bool amountHidden) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(storageKey, amountHidden);
  }
}

final portfolioAmountHiddenStorageProvider =
    Provider<PortfolioAmountHiddenStorage>((ref) {
      return const PreferencesPortfolioAmountHiddenStorage();
    });

final initialPortfolioAmountHiddenProvider = Provider<bool>((ref) => false);

final portfolioAmountHiddenProvider =
    NotifierProvider<PortfolioAmountHiddenController, bool?>(
      PortfolioAmountHiddenController.new,
    );

class PortfolioAmountHiddenController extends Notifier<bool?> {
  Future<void> _writeTail = Future<void>.value();
  var _selectionGeneration = 0;

  @override
  bool? build() => ref.watch(initialPortfolioAmountHiddenProvider);

  Future<bool> select(bool amountHidden) async {
    if (state == amountHidden) return true;

    final previous = state;
    final generation = ++_selectionGeneration;
    state = amountHidden;
    final write = _writeTail.then(
      (_) => ref
          .read(portfolioAmountHiddenStorageProvider)
          .writeAmountHidden(amountHidden),
    );
    _writeTail = _ignoreFailure(write);
    try {
      await write;
      return true;
    } catch (_) {
      if (generation == _selectionGeneration) state = previous;
      return false;
    }
  }

  Future<void> _ignoreFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // A later selection must still be persisted after an earlier write fails.
    }
  }
}

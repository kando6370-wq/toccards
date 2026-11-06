import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_request_log.dart';
import '../api/app_http_transport.dart';
import '../debug/app_debug_overlay.dart';
import 'portfolio_api_client.dart';

final portfolioDioProvider = Provider((ref) {
  final dio = createPortfolioDio(
    transport: ref.watch(appHttpTransportProvider),
  );
  dio.interceptors.add(
    ApiRequestTimingInterceptor(ref.read(apiRequestLogProvider.notifier)),
  );
  addAppDebugHttpLogging(dio);
  dio.interceptors.add(
    AuthSessionInterceptor(dio: dio, storage: ref.watch(authStorageProvider)),
  );
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
  String? build() {
    ref.watch(
      authControllerProvider.select((auth) {
        final current = auth.session;
        return (
          current?.platform,
          current?.dataSpaceId,
          current?.userId,
          current?.anonymousId,
        );
      }),
    );
    return null;
  }

  void select(String folderId) {
    state = folderId;
  }
}

abstract interface class PortfolioAmountHiddenStorage {
  Future<bool> readAmountHidden();
  Future<void> writeAmountHidden(bool amountHidden);
}

abstract interface class ScopedPortfolioAmountHiddenStorage
    implements PortfolioAmountHiddenStorage {
  Future<bool> readAmountHiddenForScope(String scope);
  Future<void> writeAmountHiddenForScope(String scope, bool amountHidden);
}

class PreferencesPortfolioAmountHiddenStorage
    implements ScopedPortfolioAmountHiddenStorage {
  const PreferencesPortfolioAmountHiddenStorage();

  static const storageKey = 'portfolio.amount_hidden';
  static const migrationOwnerKey = '$storageKey.migration_owner';

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

  @override
  Future<bool> readAmountHiddenForScope(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool('$storageKey.$scope') ?? false;
  }

  Future<bool> migrateLegacyAmountHiddenToScope(String scope) async {
    final preferences = await SharedPreferences.getInstance();
    final scopedKey = '$storageKey.$scope';
    final scopedValue = preferences.getBool(scopedKey);
    final migrationOwner = preferences.getString(migrationOwnerKey);
    if (migrationOwner != null && migrationOwner != scope) {
      return scopedValue ?? false;
    }
    final legacyValue = preferences.getBool(storageKey);
    if (scopedValue != null) {
      if (legacyValue != null) {
        await _claimMigration(preferences, scope, migrationOwner);
        final removed = await preferences.remove(storageKey);
        if (removed) await preferences.remove(migrationOwnerKey);
      } else if (migrationOwner == scope) {
        await preferences.remove(migrationOwnerKey);
      }
      return scopedValue;
    }
    if (legacyValue == null) {
      if (migrationOwner == scope) await preferences.remove(migrationOwnerKey);
      return false;
    }
    await _claimMigration(preferences, scope, migrationOwner);
    final persisted = await preferences.setBool(scopedKey, legacyValue);
    if (!persisted) {
      throw StateError('Failed to persist scoped amount visibility.');
    }
    final removed = await preferences.remove(storageKey);
    if (removed) await preferences.remove(migrationOwnerKey);
    return legacyValue;
  }

  Future<void> _claimMigration(
    SharedPreferences preferences,
    String scope,
    String? migrationOwner,
  ) async {
    if (migrationOwner == scope) return;
    final claimed = await preferences.setString(migrationOwnerKey, scope);
    if (!claimed) {
      throw StateError('Failed to claim legacy amount visibility.');
    }
  }

  @override
  Future<void> writeAmountHiddenForScope(
    String scope,
    bool amountHidden,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$storageKey.$scope', amountHidden);
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
  String? _activeScope;
  bool? _activeValue;

  @override
  bool? build() {
    final generation = ++_selectionGeneration;
    final session = ref.watch(authControllerProvider).session;
    final scope = _scopeForSession(session);
    final initialValue = _activeScope == scope
        ? _activeValue ?? ref.watch(initialPortfolioAmountHiddenProvider)
        : ref.watch(initialPortfolioAmountHiddenProvider);
    if (_activeScope != scope) {
      _activeScope = scope;
      _activeValue = null;
    }
    final storage = ref.watch(portfolioAmountHiddenStorageProvider);
    if (storage is ScopedPortfolioAmountHiddenStorage) {
      Future<void>.microtask(() async {
        bool value;
        try {
          final legacyIosOwner = _legacyIosOwner(session);
          if (storage is PreferencesPortfolioAmountHiddenStorage &&
              legacyIosOwner != null &&
              ref.read(appCommercialPolicyProvider).usesAppleSubscription) {
            final migration = _writeTail.then(
              (_) => storage.migrateLegacyAmountHiddenToScope(scope),
            );
            _writeTail = _ignoreFailure(migration.then<void>((_) {}));
            value = await migration;
          } else {
            value = await storage.readAmountHiddenForScope(scope);
          }
        } on Object {
          value = false;
        }
        if (ref.mounted &&
            generation == _selectionGeneration &&
            _currentScope() == scope) {
          _activeValue = value;
          state = value;
        }
      });
    }
    return initialValue;
  }

  Future<bool> select(bool amountHidden) async {
    if (state == amountHidden) return true;

    final previous = state;
    final generation = ++_selectionGeneration;
    _activeValue = amountHidden;
    state = amountHidden;
    final scope = _currentScope();
    final storage = ref.read(portfolioAmountHiddenStorageProvider);
    final write = _writeTail.then((_) {
      if (storage is ScopedPortfolioAmountHiddenStorage) {
        return storage.writeAmountHiddenForScope(scope, amountHidden);
      }
      return storage.writeAmountHidden(amountHidden);
    });
    _writeTail = _ignoreFailure(write);
    try {
      await write;
      return true;
    } catch (_) {
      if (generation == _selectionGeneration && _currentScope() == scope) {
        _activeValue = previous;
        state = previous;
      }
      return false;
    }
  }

  String _currentScope() {
    return _scopeForSession(ref.read(authControllerProvider).session);
  }

  Future<void> _ignoreFailure(Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      // A later selection must still be persisted after an earlier write fails.
    }
  }
}

String _scopeForSession(AuthSession? session) {
  return session?.dataSpaceId ??
      _legacyIosOwner(session) ??
      '${session?.platform?.name ?? 'legacy'}:'
          '${session?.userId ?? session?.anonymousId ?? 'none'}';
}

String? _legacyIosOwner(AuthSession? session) {
  if (session == null ||
      session.dataSpaceId != null ||
      session.platform == AppPlatform.android) {
    return null;
  }
  return session.userId ?? session.anonymousId;
}

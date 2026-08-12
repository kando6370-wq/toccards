import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ScanQuotaStorage {
  Future<int> readUsedScans();

  Future<void> writeUsedScans(int value);
}

class SharedPreferencesScanQuotaStorage implements ScanQuotaStorage {
  const SharedPreferencesScanQuotaStorage();

  static const _usedScansKey = 'subscription.free_scan.used_count';

  @override
  Future<int> readUsedScans() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getInt(_usedScansKey) ?? 0;
  }

  @override
  Future<void> writeUsedScans(int value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_usedScansKey, value);
  }
}

class InMemoryScanQuotaStorage implements ScanQuotaStorage {
  InMemoryScanQuotaStorage({this.usedScans = 0});

  int usedScans;

  @override
  Future<int> readUsedScans() async => usedScans;

  @override
  Future<void> writeUsedScans(int value) async => usedScans = value;
}

final freeScanLimitProvider = Provider<int>((ref) {
  const configured = int.fromEnvironment(
    'SUBSCRIPTION_FREE_SCAN_LIMIT',
    defaultValue: 10,
  );
  return configured < 0 ? 0 : configured;
});

final scanQuotaStorageProvider = Provider<ScanQuotaStorage>((ref) {
  return const SharedPreferencesScanQuotaStorage();
});

final scanQuotaControllerProvider =
    NotifierProvider<ScanQuotaController, ScanQuotaState>(
      ScanQuotaController.new,
    );

class ScanQuotaState {
  const ScanQuotaState({
    required this.limit,
    required this.usedScans,
    this.isLoading = false,
  });

  final int limit;
  final int usedScans;
  final bool isLoading;

  int get remainingScans => (limit - usedScans).clamp(0, limit);

  ScanQuotaState copyWith({int? usedScans, bool? isLoading}) {
    return ScanQuotaState(
      limit: limit,
      usedScans: usedScans ?? this.usedScans,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ScanQuotaController extends Notifier<ScanQuotaState> {
  @override
  ScanQuotaState build() {
    final limit = ref.watch(freeScanLimitProvider);
    Future<void>.microtask(_load);
    return ScanQuotaState(limit: limit, usedScans: 0, isLoading: true);
  }

  bool tryConsume() {
    if (state.isLoading || state.remainingScans == 0) return false;
    final usedScans = state.usedScans + 1;
    state = state.copyWith(usedScans: usedScans);
    unawaited(ref.read(scanQuotaStorageProvider).writeUsedScans(usedScans));
    return true;
  }

  Future<void> _load() async {
    var usedScans = 0;
    try {
      usedScans = await ref.read(scanQuotaStorageProvider).readUsedScans();
    } on Exception {
      usedScans = 0;
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      usedScans: usedScans.clamp(0, state.limit),
      isLoading: false,
    );
  }
}

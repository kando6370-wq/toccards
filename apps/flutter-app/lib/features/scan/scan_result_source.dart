import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ScanResolutionKind { matched, failed, noMatch }

class ScanResolution {
  const ScanResolution.matched({
    required this.matchName,
    required this.candidates,
  }) : kind = ScanResolutionKind.matched;

  const ScanResolution.failed()
    : kind = ScanResolutionKind.failed,
      matchName = null,
      candidates = const [];

  const ScanResolution.noMatch()
    : kind = ScanResolutionKind.noMatch,
      matchName = null,
      candidates = const [];

  final ScanResolutionKind kind;
  final String? matchName;
  final List<String> candidates;
}

abstract interface class ScanResultSource {
  Future<ScanResolution> photo();
  Future<ScanResolution> library();
  Future<ScanResolution> retry();
}

final scanResultSourceProvider = Provider<ScanResultSource>(
  (ref) => _DemoScanResultSource(),
);

class _DemoScanResultSource implements ScanResultSource {
  var _photoScanCount = 0;

  @override
  Future<ScanResolution> photo() {
    _photoScanCount += 1;
    if (_photoScanCount == 2) {
      return Future.value(const ScanResolution.failed());
    }

    return Future.value(
      _photoScanCount >= 3
          ? const ScanResolution.matched(
              matchName: 'Charizard ex',
              candidates: ['Charizard ex', 'Charmander Promo', 'Charmeleon'],
            )
          : const ScanResolution.matched(
              matchName: 'Mega Lucario ex',
              candidates: ['Mega Lucario ex', 'Lucario ex', 'Riolu Promo'],
            ),
    );
  }

  @override
  Future<ScanResolution> library() {
    return Future.value(const ScanResolution.noMatch());
  }

  @override
  Future<ScanResolution> retry() {
    return Future.value(
      const ScanResolution.matched(
        matchName: 'Mega Lucario ex',
        candidates: ['Mega Lucario ex', 'Lucario ex', 'Riolu Promo'],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';

void main() {
  test(
    'photo uses recognition API because scan matches must come from card data',
    () async {
      final api = _FakeScanApi(_matchedRecognition);
      final picker = _FakeScanImagePicker();
      final imageHasher = _FakeScanImageHasher();
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        imageHasher: imageHasher,
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final result = await source.photo();

      expect(result.kind, ScanResolutionKind.matched);
      expect(result.scanId, 'scan-1');
      expect(result.cardRef, '1');
      expect(result.matchName, 'Bushi Tenderfoot');
      expect(result.candidates, ['Bushi Tenderfoot', 'Devoted Retainer']);
      expect(result.candidateCardRefs, ['1', '2']);
      expect(result.imageBytes, Uint8List.fromList([1, 2, 3]));
      expect(imageHasher.lastBytes, Uint8List.fromList([1, 2, 3]));
      expect(api.lastHashes?.cardImageBytes, Uint8List.fromList([4, 5, 6]));
      expect(api.lastPlatform, 'iOS');
      expect(picker.sources, [ScanImageSource.camera]);
    },
  );

  test(
    'library returns noMatch because unmatched scans cannot enter review',
    () async {
      final source = ApiScanResultSource(
        api: _FakeScanApi(
          const ScanRecognitionDto(
            scanId: 'scan-2',
            recognitionStatus: 'no_match',
            results: [],
          ),
        ),
        session: () => _session,
        imagePicker: _FakeScanImagePicker(),
        imageHasher: _FakeScanImageHasher(),
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final results = await source.library();
      expect((await results.single).kind, ScanResolutionKind.noMatch);
    },
  );

  test(
    'retry reuses the failed image because retry must not reopen capture',
    () async {
      final picker = _FakeScanImagePicker();
      final api = _FakeScanApi(_matchedRecognition);
      final imageHasher = _FakeScanImageHasher();
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        imageHasher: imageHasher,
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final first = await source.photo();
      await source.retry(
        imageBytes: first.imageBytes,
        fileName: first.imageFileName,
      );

      expect(picker.sources, [ScanImageSource.camera]);
      expect(api.callCount, 2);
      expect(imageHasher.lastBytes, Uint8List.fromList([1, 2, 3]));
    },
  );

  test(
    'picker cancellation does not call recognition because cancelling capture is not a failed scan',
    () async {
      final api = _FakeScanApi(_matchedRecognition);
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: _FakeScanImagePicker(cancelled: true),
        imageHasher: _FakeScanImageHasher(),
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      expect(await source.library(), isEmpty);
      expect(api.callCount, 0);
    },
  );

  test(
    'recognition failure keeps the selected image because Retry must resend the same card',
    () async {
      final source = ApiScanResultSource(
        api: _FakeScanApi(_matchedRecognition, failure: StateError('offline')),
        session: () => _session,
        imagePicker: _FakeScanImagePicker(),
        imageHasher: _FakeScanImageHasher(),
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final result = await source.photo();

      expect(result.kind, ScanResolutionKind.failed);
      expect(result.imageBytes, Uint8List.fromList([1, 2, 3]));
      expect(result.imageFileName, 'scan.jpg');
    },
  );

  test(
    'library recognizes up to ten selected images independently because each imported card needs its own scan record',
    () async {
      final picker = _FakeScanImagePicker(batchCount: 12);
      final api = _FakeScanApi(_matchedRecognition);
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        imageHasher: _FakeScanImageHasher(),
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final pendingResults = await source.library();
      final results = await Future.wait(pendingResults);

      expect(picker.batchLimits, [10]);
      expect(results, hasLength(10));
      expect(
        results.every((result) => result.kind == ScanResolutionKind.matched),
        isTrue,
      );
      expect(api.callCount, 10);
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

const _hash = 'vgM8KW2_mtY4LMLQZJvFpzl823zE3mx0mWhpCcRYaGw';

const _matchedRecognition = ScanRecognitionDto(
  scanId: 'scan-1',
  recognitionStatus: 'success',
  results: [
    ScanResultDto(
      index: 1,
      matched: true,
      candidates: [
        ScanCandidateDto(
          cardRef: '1',
          name: 'Bushi Tenderfoot',
          setCode: 'CHK',
          cardNumber: '1',
          confidence: 90,
        ),
        ScanCandidateDto(
          cardRef: '2',
          name: 'Devoted Retainer',
          setCode: 'CHK',
          cardNumber: '2',
          confidence: 80,
        ),
      ],
    ),
  ],
);

class _FakeScanImagePicker implements ScanImagePicker {
  _FakeScanImagePicker({this.cancelled = false, this.batchCount = 1});

  final bool cancelled;
  final int batchCount;
  final sources = <ScanImageSource>[];
  final batchLimits = <int>[];

  @override
  Future<ScanImage?> pick(ScanImageSource source) async {
    sources.add(source);
    if (cancelled) return null;
    return ScanImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'scan.jpg',
    );
  }

  @override
  Future<List<ScanImage>> pickMany(
    ScanImageSource source, {
    required int limit,
  }) async {
    sources.add(source);
    batchLimits.add(limit);
    if (cancelled) return const [];
    return [
      for (var index = 0; index < batchCount; index += 1)
        ScanImage(
          bytes: Uint8List.fromList([index + 1]),
          fileName: 'scan-$index.jpg',
        ),
    ];
  }
}

class _FakeScanApi implements ScanApi {
  _FakeScanApi(this.result, {this.failure});

  final ScanRecognitionDto result;
  final Object? failure;
  ScanImageHashes? lastHashes;
  String? lastPlatform;
  var callCount = 0;

  @override
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required ScanCollectionItemInput item,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required ScanImageHashes hashes,
    required String fileName,
    required String platform,
    required String appVersion,
    String? deviceModel,
    String? osVersion,
  }) async {
    callCount += 1;
    lastHashes = hashes;
    lastPlatform = platform;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result;
  }
}

class _FakeScanImageHasher implements ScanImageHasher {
  Uint8List? lastBytes;

  @override
  Future<ScanImageHashes> hash(Uint8List imageBytes) async {
    lastBytes = imageBytes;
    return ScanImageHashes(
      r: _hash,
      g: _hash,
      b: _hash,
      cardImageBytes: Uint8List.fromList([4, 5, 6]),
    );
  }
}

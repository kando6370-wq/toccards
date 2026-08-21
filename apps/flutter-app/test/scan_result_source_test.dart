import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_card_number_reader.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';

void main() {
  test(
    'photo uses recognition API because scan matches must come from card data',
    () async {
      final api = _FakeScanApi(_matchedRecognition);
      final picker = _FakeScanImagePicker();
      final imageHasher = _FakeScanImageHasher();
      final cardNumberReader = _FakeCardNumberReader('018/066');
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        imageHasher: imageHasher,
        cardNumberReader: cardNumberReader,
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
      expect(result.displayImageBytes, Uint8List.fromList([1, 2, 3]));
      expect(imageHasher.lastBytes, Uint8List.fromList([1, 2, 3]));
      expect(imageHasher.lastCrop, isNull);
      expect(api.lastHashes?.cardImageBytes, Uint8List.fromList([4, 5, 6]));
      expect(api.lastPlatform, 'iOS');
      expect(api.lastCardNumber, '018/066');
      expect(cardNumberReader.lastBytes, Uint8List.fromList([4, 5, 6]));
      expect(picker.sources, [ScanImageSource.camera]);
    },
  );

  test(
    'recognize forwards the camera viewfinder crop because in-app photos must match the visible targeting area',
    () async {
      final imageHasher = _FakeScanImageHasher();
      final source = ApiScanResultSource(
        api: _FakeScanApi(_matchedRecognition),
        session: () => _session,
        imagePicker: _FakeScanImagePicker(),
        imageHasher: imageHasher,
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );
      const crop = ScanImageCrop(
        left: 0.1,
        top: 0.2,
        width: 0.8,
        height: 0.6,
        viewportAspectRatio: 390 / 844,
      );

      Uint8List? displayedBytes;
      final result = await source.recognize(
        ScanImage(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'camera.jpg',
          recognitionCrop: crop,
        ),
        onDisplayImageReady: (bytes) => displayedBytes = bytes,
      );

      expect(imageHasher.lastCrop, same(crop));
      expect(
        result.imageBytes,
        Uint8List.fromList([1, 2, 3]),
        reason: 'Retry must retain the original camera file.',
      );
      expect(
        result.displayImageBytes,
        Uint8List.fromList([4, 5, 6]),
        reason: 'Camera previews must use the processed viewfinder crop.',
      );
      expect(displayedBytes, Uint8List.fromList([4, 5, 6]));
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
            quota: _freeQuota,
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
    'retry reuses an uncertain request id because a late success must not spend Free quota twice',
    () async {
      final api = _FakeScanApi(
        _matchedRecognition,
        failures: const [
          ScanApiException(
            scanRequestTimeoutMessage,
            code: scanRequestTimeoutCode,
          ),
        ],
      );
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: _FakeScanImagePicker(),
        imageHasher: _FakeScanImageHasher(),
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final failed = await source.photo();
      await source.retry(
        imageBytes: failed.imageBytes,
        fileName: failed.imageFileName,
      );

      expect(api.requestIds, hasLength(2));
      expect(api.requestIds[1], api.requestIds[0]);
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
  quota: _freeQuota,
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

const _freeQuota = ScanQuotaDto(
  access: ScanQuotaAccess.free,
  limit: 10,
  reserved: 0,
  consumed: 1,
  remaining: 9,
  unlimited: false,
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
  _FakeScanApi(this.result, {this.failure, this.failures = const []});

  final ScanRecognitionDto result;
  final Object? failure;
  final List<Object> failures;
  ScanImageHashes? lastHashes;
  String? lastPlatform;
  String? lastCardNumber;
  final requestIds = <String>[];
  var callCount = 0;

  @override
  Future<ScanQuotaDto> getQuota(
    AuthSession session, {
    bool localPremiumVerified = false,
  }) async => _freeQuota;

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
    required String requestId,
    bool localPremiumVerified = false,
    String? cardNumber,
    String? deviceModel,
    String? osVersion,
  }) async {
    callCount += 1;
    requestIds.add(requestId);
    lastHashes = hashes;
    lastPlatform = platform;
    lastCardNumber = cardNumber;
    if (callCount <= failures.length) throw failures[callCount - 1];
    final failure = this.failure;
    if (failure != null) throw failure;
    return result;
  }
}

class _FakeCardNumberReader implements ScanCardNumberReader {
  _FakeCardNumberReader(this.result);

  final String? result;
  Uint8List? lastBytes;

  @override
  Future<String?> read(Uint8List cardImageBytes) async {
    lastBytes = cardImageBytes;
    return result;
  }
}

class _FakeScanImageHasher implements ScanImageHasher {
  Uint8List? lastBytes;
  ScanImageCrop? lastCrop;

  @override
  Future<ScanImageHashes> hash(
    Uint8List imageBytes, {
    ScanImageCrop? crop,
  }) async {
    lastBytes = imageBytes;
    lastCrop = crop;
    return ScanImageHashes(
      r: _hash,
      g: _hash,
      b: _hash,
      cardImageBytes: Uint8List.fromList([4, 5, 6]),
    );
  }
}

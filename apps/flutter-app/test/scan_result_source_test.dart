import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/scan/scan_result_source.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

void main() {
  test(
    'photo uses recognition API because scan matches must come from card data',
    () async {
      final api = _FakeScanApi(_matchedRecognition);
      final picker = _FakeScanImagePicker();
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      final result = await source.photo();

      expect(result.kind, ScanResolutionKind.matched);
      expect(result.scanId, 'scan-1');
      expect(result.cardRef, '1');
      expect(result.matchName, 'Bushi Tenderfoot');
      expect(result.candidates, ['Bushi Tenderfoot', 'Devoted Retainer']);
      expect(api.lastBytes, Uint8List.fromList([1, 2, 3]));
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
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      expect((await source.library()).kind, ScanResolutionKind.noMatch);
    },
  );

  test(
    'retry reuses the failed image because retry must not reopen capture',
    () async {
      final picker = _FakeScanImagePicker();
      final api = _FakeScanApi(_matchedRecognition);
      final source = ApiScanResultSource(
        api: api,
        session: () => _session,
        imagePicker: picker,
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      await source.photo();
      await source.retry();

      expect(picker.sources, [ScanImageSource.camera]);
      expect(api.callCount, 2);
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
        appInfo: () async =>
            const ScanAppInfo(platform: 'iOS', appVersion: '1.0.0'),
      );

      expect((await source.library()).kind, ScanResolutionKind.cancelled);
      expect(api.callCount, 0);
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

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
  _FakeScanImagePicker({this.cancelled = false});

  final bool cancelled;
  final sources = <ScanImageSource>[];

  @override
  Future<ScanImage?> pick(ScanImageSource source) async {
    sources.add(source);
    if (cancelled) return null;
    return ScanImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'scan.jpg',
    );
  }
}

class _FakeScanApi implements ScanApi {
  _FakeScanApi(this.result);

  final ScanRecognitionDto result;
  Uint8List? lastBytes;
  String? lastPlatform;
  var callCount = 0;

  @override
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required String folderId,
    required String cardRef,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required Uint8List imageBytes,
    required String fileName,
    required String platform,
    required String appVersion,
    String? deviceModel,
    String? osVersion,
  }) async {
    callCount += 1;
    lastBytes = imageBytes;
    lastPlatform = platform;
    return result;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_card_number_reader.dart';
import '../../shared/scan/scan_image_hasher.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../subscription/scan_quota_controller.dart';
import '../subscription/subscription_controller.dart';

enum ScanResolutionKind {
  matched,
  failed,
  noMatch,
  cancelled,
  quotaExhausted,
  entitlementSyncRequired,
}

class ScanResolution {
  const ScanResolution.matched({
    required this.scanId,
    required this.cardRef,
    required this.matchName,
    required this.candidates,
    this.candidateCardRefs = const [],
    this.imageBytes,
    this.displayImageBytes,
    this.imageFileName,
    this.quota,
  }) : kind = ScanResolutionKind.matched;

  const ScanResolution.failed({
    this.imageBytes,
    this.displayImageBytes,
    this.imageFileName,
    this.quota,
  }) : kind = ScanResolutionKind.failed,
       scanId = null,
       cardRef = null,
       matchName = null,
       candidates = const [],
       candidateCardRefs = const [];

  const ScanResolution.noMatch({
    this.imageBytes,
    this.displayImageBytes,
    this.imageFileName,
    this.quota,
  }) : kind = ScanResolutionKind.noMatch,
       scanId = null,
       cardRef = null,
       matchName = null,
       candidates = const [],
       candidateCardRefs = const [];

  const ScanResolution.cancelled()
    : kind = ScanResolutionKind.cancelled,
      scanId = null,
      cardRef = null,
      matchName = null,
      candidates = const [],
      candidateCardRefs = const [],
      imageBytes = null,
      displayImageBytes = null,
      imageFileName = null,
      quota = null;

  const ScanResolution.quotaExhausted({
    required this.imageBytes,
    required this.displayImageBytes,
    required this.imageFileName,
    required this.quota,
  }) : kind = ScanResolutionKind.quotaExhausted,
       scanId = null,
       cardRef = null,
       matchName = null,
       candidates = const [],
       candidateCardRefs = const [];

  const ScanResolution.entitlementSyncRequired({
    required this.imageBytes,
    required this.displayImageBytes,
    required this.imageFileName,
  }) : kind = ScanResolutionKind.entitlementSyncRequired,
       scanId = null,
       cardRef = null,
       matchName = null,
       candidates = const [],
       candidateCardRefs = const [],
       quota = null;

  final ScanResolutionKind kind;
  final String? scanId;
  final String? cardRef;
  final String? matchName;
  final List<String> candidates;
  final List<String> candidateCardRefs;
  final Uint8List? imageBytes;
  final Uint8List? displayImageBytes;
  final String? imageFileName;
  final ScanQuotaDto? quota;
}

abstract interface class ScanResultSource {
  Future<ScanResolution> photo();
  Future<List<Future<ScanResolution>>> library({
    int maxItems = 10,
    void Function(ScanImage image, Future<ScanResolution> resolution)?
    onSelected,
  });
  Future<ScanResolution> recognize(
    ScanImage image, {
    ValueChanged<Uint8List>? onDisplayImageReady,
  });
  Future<ScanResolution> retry({Uint8List? imageBytes, String? fileName});
}

final scanResultSourceProvider = Provider<ScanResultSource>(
  (ref) => ApiScanResultSource(
    api: ref.watch(scanApiClientProvider),
    session: () => ref.read(authControllerProvider).session,
    imagePicker: ImagePickerScanImagePicker(),
    imageHasher: createScanImageHasher(),
    cardNumberReader: createScanCardNumberReader(),
    appInfo: _readScanAppInfo,
    localPremiumVerified: () =>
        ref.read(subscriptionControllerProvider).isPro ||
        ref.read(scanQuotaControllerProvider).unlimited,
    onQuotaChanged: (quota) {
      if (ref.mounted) {
        ref.read(scanQuotaControllerProvider.notifier).applyServerQuota(quota);
      }
    },
  ),
);

enum ScanImageSource { camera, gallery }

class ScanImage {
  const ScanImage({
    required this.bytes,
    required this.fileName,
    this.recognitionCrop,
  });

  final Uint8List bytes;
  final String fileName;
  final ScanImageCrop? recognitionCrop;
}

abstract interface class ScanImagePicker {
  Future<ScanImage?> pick(ScanImageSource source);
  Future<List<ScanImage>> pickMany(
    ScanImageSource source, {
    required int limit,
  });
}

class ImagePickerScanImagePicker implements ScanImagePicker {
  ImagePickerScanImagePicker({picker.ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? picker.ImagePicker();

  final picker.ImagePicker _imagePicker;

  @override
  Future<ScanImage?> pick(ScanImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source == ScanImageSource.camera
          ? picker.ImageSource.camera
          : picker.ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    return ScanImage(bytes: await image.readAsBytes(), fileName: image.name);
  }

  @override
  Future<List<ScanImage>> pickMany(
    ScanImageSource source, {
    required int limit,
  }) async {
    if (source != ScanImageSource.gallery) {
      throw ArgumentError.value(
        source,
        'source',
        'Only gallery supports batches.',
      );
    }
    final images = await _imagePicker.pickMultiImage(
      requestFullMetadata: false,
      limit: limit,
    );
    return Future.wait([
      for (final image in images)
        image.readAsBytes().then(
          (bytes) => ScanImage(bytes: bytes, fileName: image.name),
        ),
    ]);
  }
}

class ScanAppInfo {
  const ScanAppInfo({required this.platform, required this.appVersion});

  final String platform;
  final String appVersion;
}

class ApiScanResultSource implements ScanResultSource {
  ApiScanResultSource({
    required ScanApi api,
    required AuthSession? Function() session,
    required ScanImagePicker imagePicker,
    required ScanImageHasher imageHasher,
    required Future<ScanAppInfo> Function() appInfo,
    ScanCardNumberReader? cardNumberReader,
    bool Function()? localPremiumVerified,
    ValueChanged<ScanQuotaDto>? onQuotaChanged,
  }) : _api = api,
       _session = session,
       _imagePicker = imagePicker,
       _imageHasher = imageHasher,
       _appInfo = appInfo,
       _localPremiumVerified = localPremiumVerified ?? _false,
       _onQuotaChanged = onQuotaChanged,
       _cardNumberReader = cardNumberReader ?? const _NoopCardNumberReader();

  final ScanApi _api;
  final AuthSession? Function() _session;
  final ScanImagePicker _imagePicker;
  final ScanImageHasher _imageHasher;
  final Future<ScanAppInfo> Function() _appInfo;
  final ScanCardNumberReader _cardNumberReader;
  final bool Function() _localPremiumVerified;
  final ValueChanged<ScanQuotaDto>? _onQuotaChanged;
  Future<void> _reservationTail = Future<void>.value();
  final Expando<String> _retryRequestIds = Expando<String>(
    'scanRetryRequestId',
  );
  @override
  Future<ScanResolution> photo() => _pickAndRecognize(ScanImageSource.camera);

  @override
  Future<List<Future<ScanResolution>>> library({
    int maxItems = 10,
    void Function(ScanImage image, Future<ScanResolution> resolution)?
    onSelected,
  }) async {
    if (maxItems <= 0) return const [];
    final images = await _imagePicker.pickMany(
      ScanImageSource.gallery,
      limit: maxItems,
    );
    final selectedImages = images.take(maxItems).toList();
    if (selectedImages.isEmpty) return const [];
    return [
      for (final image in selectedImages)
        () {
          final resolution = recognize(image);
          onSelected?.call(image, resolution);
          return resolution;
        }(),
    ];
  }

  @override
  Future<ScanResolution> retry({Uint8List? imageBytes, String? fileName}) {
    if (imageBytes == null || fileName == null) {
      return Future.value(const ScanResolution.failed());
    }
    return recognize(ScanImage(bytes: imageBytes, fileName: fileName));
  }

  Future<ScanResolution> _pickAndRecognize(ScanImageSource source) async {
    final image = await _imagePicker.pick(source);
    if (image == null) return const ScanResolution.cancelled();
    return recognize(image);
  }

  @override
  Future<ScanResolution> recognize(
    ScanImage image, {
    ValueChanged<Uint8List>? onDisplayImageReady,
  }) async {
    final previousReservation = _reservationTail;
    final reservationFinished = Completer<void>();
    _reservationTail = reservationFinished.future;
    var reservationTurnReleased = false;
    void releaseReservationTurn() {
      if (reservationTurnReleased) return;
      reservationTurnReleased = true;
      reservationFinished.complete();
    }

    Uint8List? displayImageBytes = image.recognitionCrop == null
        ? image.bytes
        : null;
    final requestId = _retryRequestIds[image.bytes] ?? const Uuid().v4();
    final ScanRecognitionDto recognition;
    try {
      final session = _session();
      if (session == null) {
        return ScanResolution.failed(
          imageBytes: image.bytes,
          displayImageBytes: displayImageBytes,
          imageFileName: image.fileName,
        );
      }
      final info = await _appInfo();
      final hashes = await _imageHasher.hash(
        image.bytes,
        crop: image.recognitionCrop,
      );
      if (hashes.cardImageBytes == null) {
        throw const ScanImageProcessingException(
          'The corrected card image is unavailable.',
        );
      }
      displayImageBytes = image.recognitionCrop == null
          ? image.bytes
          : hashes.cardImageBytes!;
      onDisplayImageReady?.call(displayImageBytes);
      final cardNumber = await _cardNumberReader.read(hashes.cardImageBytes!);
      await previousReservation;
      try {
        final reservationApi = _api is ScanQuotaReservationApi
            ? _api as ScanQuotaReservationApi
            : null;
        if (reservationApi != null) {
          final quota = await reservationApi.reserveQuota(
            session,
            requestId: requestId,
            localPremiumVerified: _localPremiumVerified(),
          );
          _onQuotaChanged?.call(quota);
        }
      } finally {
        releaseReservationTurn();
      }
      recognition = await _api.recognizeImage(
        session,
        hashes: hashes,
        fileName: image.fileName,
        platform: info.platform,
        appVersion: info.appVersion,
        requestId: requestId,
        localPremiumVerified: _localPremiumVerified(),
        cardNumber: cardNumber,
      );
    } on ScanApiException catch (error) {
      if (error.code == 'SCAN_QUOTA_EXHAUSTED' && error.quota != null) {
        _retryRequestIds[image.bytes] = null;
        return ScanResolution.quotaExhausted(
          imageBytes: image.bytes,
          displayImageBytes: displayImageBytes,
          imageFileName: image.fileName,
          quota: error.quota!,
        );
      }
      if (error.statusCode == 409 &&
          error.code == 'ENTITLEMENT_SYNC_REQUIRED') {
        _retryRequestIds[image.bytes] = null;
        return ScanResolution.entitlementSyncRequired(
          imageBytes: image.bytes,
          displayImageBytes: displayImageBytes,
          imageFileName: image.fileName,
        );
      }
      _retryRequestIds[image.bytes] =
          error.code == scanRequestTimeoutCode ||
              error.code == 'SCAN_REQUEST_CONFLICT'
          ? requestId
          : null;
      return ScanResolution.failed(
        imageBytes: image.bytes,
        displayImageBytes: displayImageBytes,
        imageFileName: image.fileName,
        quota: error.quota,
      );
    } on Object {
      _retryRequestIds[image.bytes] = requestId;
      return ScanResolution.failed(
        imageBytes: image.bytes,
        displayImageBytes: displayImageBytes,
        imageFileName: image.fileName,
      );
    } finally {
      if (!reservationTurnReleased) {
        await previousReservation;
        releaseReservationTurn();
      }
    }
    _retryRequestIds[image.bytes] = null;
    final matchedResults = recognition.results.where(
      (result) => result.matched && result.candidates.isNotEmpty,
    );
    if (matchedResults.isEmpty) {
      return ScanResolution.noMatch(
        imageBytes: image.bytes,
        displayImageBytes: displayImageBytes,
        imageFileName: image.fileName,
        quota: recognition.quota,
      );
    }
    final candidates = matchedResults.first.candidates;
    return ScanResolution.matched(
      scanId: recognition.scanId,
      cardRef: candidates.first.cardRef,
      matchName: candidates.first.name,
      candidates: candidates.map((candidate) => candidate.name).toList(),
      candidateCardRefs: candidates
          .map((candidate) => candidate.cardRef)
          .toList(),
      imageBytes: image.bytes,
      displayImageBytes: displayImageBytes,
      imageFileName: image.fileName,
      quota: recognition.quota,
    );
  }
}

bool _false() => false;

class _NoopCardNumberReader implements ScanCardNumberReader {
  const _NoopCardNumberReader();

  @override
  Future<String?> read(Uint8List cardImageBytes) async => null;
}

Future<ScanAppInfo> _readScanAppInfo() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final platform = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS => 'iOS',
          TargetPlatform.android => 'Android',
          TargetPlatform.macOS => 'macOS',
          TargetPlatform.windows => 'Windows',
          TargetPlatform.linux => 'Linux',
          TargetPlatform.fuchsia => 'Fuchsia',
        };
  return ScanAppInfo(platform: platform, appVersion: packageInfo.version);
}

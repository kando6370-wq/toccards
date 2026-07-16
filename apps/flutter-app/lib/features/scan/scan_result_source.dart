import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:package_info_plus/package_info_plus.dart';

import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

enum ScanResolutionKind { matched, failed, noMatch, cancelled }

class ScanResolution {
  const ScanResolution.matched({
    required this.scanId,
    required this.cardRef,
    required this.matchName,
    required this.candidates,
    this.candidateCardRefs = const [],
    this.imageBytes,
    this.imageFileName,
  }) : kind = ScanResolutionKind.matched;

  const ScanResolution.failed({this.imageBytes, this.imageFileName})
    : kind = ScanResolutionKind.failed,
      scanId = null,
      cardRef = null,
      matchName = null,
      candidates = const [],
      candidateCardRefs = const [];

  const ScanResolution.noMatch({this.imageBytes, this.imageFileName})
    : kind = ScanResolutionKind.noMatch,
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
      imageFileName = null;

  final ScanResolutionKind kind;
  final String? scanId;
  final String? cardRef;
  final String? matchName;
  final List<String> candidates;
  final List<String> candidateCardRefs;
  final Uint8List? imageBytes;
  final String? imageFileName;
}

abstract interface class ScanResultSource {
  Future<ScanResolution> photo();
  Future<List<Future<ScanResolution>>> library();
  Future<ScanResolution> recognize(ScanImage image);
  Future<ScanResolution> retry({Uint8List? imageBytes, String? fileName});
}

final scanResultSourceProvider = Provider<ScanResultSource>(
  (ref) => ApiScanResultSource(
    api: ref.watch(scanApiClientProvider),
    session: () => ref.read(authControllerProvider).session,
    imagePicker: ImagePickerScanImagePicker(),
    appInfo: _readScanAppInfo,
  ),
);

enum ScanImageSource { camera, gallery }

class ScanImage {
  const ScanImage({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
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
    required Future<ScanAppInfo> Function() appInfo,
  }) : _api = api,
       _session = session,
       _imagePicker = imagePicker,
       _appInfo = appInfo;

  final ScanApi _api;
  final AuthSession? Function() _session;
  final ScanImagePicker _imagePicker;
  final Future<ScanAppInfo> Function() _appInfo;
  @override
  Future<ScanResolution> photo() => _pickAndRecognize(ScanImageSource.camera);

  @override
  Future<List<Future<ScanResolution>>> library() async {
    final images = await _imagePicker.pickMany(
      ScanImageSource.gallery,
      limit: 10,
    );
    final selectedImages = images.take(10).toList();
    if (selectedImages.isEmpty) return const [];
    return [for (final image in selectedImages) recognize(image)];
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
  Future<ScanResolution> recognize(ScanImage image) async {
    final ScanRecognitionDto recognition;
    try {
      final session = _session();
      if (session == null) {
        return ScanResolution.failed(
          imageBytes: image.bytes,
          imageFileName: image.fileName,
        );
      }
      final info = await _appInfo();
      recognition = await _api.recognizeImage(
        session,
        imageBytes: image.bytes,
        fileName: image.fileName,
        platform: info.platform,
        appVersion: info.appVersion,
      );
    } catch (_) {
      return ScanResolution.failed(
        imageBytes: image.bytes,
        imageFileName: image.fileName,
      );
    }
    final matchedResults = recognition.results.where(
      (result) => result.matched && result.candidates.isNotEmpty,
    );
    if (matchedResults.isEmpty) {
      return ScanResolution.noMatch(
        imageBytes: image.bytes,
        imageFileName: image.fileName,
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
      imageFileName: image.fileName,
    );
  }
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

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' as picker;
import 'package:package_info_plus/package_info_plus.dart';

import '../../shared/scan/scan_api_client.dart';
import '../../shared/scan/scan_providers.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

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
  ScanImage? _lastImage;

  @override
  Future<ScanResolution> photo() => _pickAndRecognize(ScanImageSource.camera);

  @override
  Future<ScanResolution> library() =>
      _pickAndRecognize(ScanImageSource.gallery);

  @override
  Future<ScanResolution> retry() async {
    final image = _lastImage;
    if (image == null) return const ScanResolution.failed();
    return _recognize(image);
  }

  Future<ScanResolution> _pickAndRecognize(ScanImageSource source) async {
    final image = await _imagePicker.pick(source);
    if (image == null) return const ScanResolution.failed();
    _lastImage = image;
    return _recognize(image);
  }

  Future<ScanResolution> _recognize(ScanImage image) async {
    final session = _session();
    if (session == null) return const ScanResolution.failed();
    final info = await _appInfo();
    final recognition = await _api.recognizeImage(
      session,
      imageBytes: image.bytes,
      fileName: image.fileName,
      platform: info.platform,
      appVersion: info.appVersion,
    );
    final matchedResults = recognition.results.where(
      (result) => result.matched && result.candidates.isNotEmpty,
    );
    if (matchedResults.isEmpty) return const ScanResolution.noMatch();
    final candidates = matchedResults.first.candidates;
    return ScanResolution.matched(
      matchName: candidates.first.name,
      candidates: candidates.map((candidate) => candidate.name).toList(),
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

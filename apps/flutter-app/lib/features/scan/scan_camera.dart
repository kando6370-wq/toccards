import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../shared/scan/scan_native_image_processor.dart';
import 'scan_result_source.dart';

abstract interface class ScanCameraSession {
  Widget buildPreview();
  bool get flashEnabled;
  Future<ScanImage> takePhoto({
    required Rect viewfinder,
    required Size viewport,
  });
  Future<bool> toggleFlash();
  Future<void> pausePreview();
  Future<void> resumePreview();
  Future<void> dispose();
}

abstract interface class ScanCameraFactory {
  Future<ScanCameraSession?> open();
}

final scanCameraFactoryProvider = Provider<ScanCameraFactory>(
  (ref) => const PluginScanCameraFactory(),
);

class PluginScanCameraFactory implements ScanCameraFactory {
  const PluginScanCameraFactory();

  Future<IosDeviceInfo?> _iosDeviceInfo() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      return await DeviceInfoPlugin().iosInfo;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<ScanCameraSession?> open() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;
      final description = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      controller = CameraController(
        description ?? cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      final info = await _iosDeviceInfo();
      // 停用 Duo 模拟器专用的 landscapeLeft，模拟器和真机共用原生旋转协调。
      final isDuo = info?.utsname.machine == 'iPhone19,4';
      try {
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'scan camera',
            context: ErrorDescription('while locking scan capture orientation'),
          ),
        );
      }
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException catch (error) {
        // AVFoundation already defaults to off on cameras without flash.
        if (defaultTargetPlatform != TargetPlatform.iOS ||
            error.code != 'setFlashModeFailed' ||
            error.description != 'Device does not have flash capabilities') {
          rethrow;
        }
      }
      final rotation = isDuo
          ? await _DuoScanRotation.enable(controller.cameraId)
          : null;
      return _PluginScanCameraSession(controller, rotation: rotation);
    } catch (_) {
      await controller?.dispose();
      return null;
    }
  }
}

class _DuoScanRotation {
  _DuoScanRotation(this.cameraId)
    : events = MethodChannel('${_channel.name}/$cameraId');

  static const _channel = MethodChannel('com.cardai.tcg/duo-scan-rotation');
  final int cameraId;
  final MethodChannel events;
  final previewTurns = ValueNotifier<int?>(null);

  static bool _validTurns(int? turns) =>
      turns != null && turns >= 0 && turns < 4;

  static Future<_DuoScanRotation?> enable(int cameraId) async {
    final rotation = _DuoScanRotation(cameraId);
    rotation.events.setMethodCallHandler((call) async {
      final turns = call.arguments;
      if (call.method == 'previewTurns' && turns is int && _validTurns(turns)) {
        rotation.previewTurns.value = turns;
      }
    });
    var enabled = false;
    try {
      final turns = await _channel.invokeMethod<int>('enable', {
        'cameraId': cameraId,
      });
      if (_validTurns(turns)) {
        rotation.previewTurns.value ??= turns;
        enabled = true;
        return rotation;
      }
    } on MissingPluginException {
      // iOS 测试环境可能未注册原生插件。
    } finally {
      if (!enabled) rotation.dispose();
    }
    return null;
  }

  Future<(XFile, int)> takePicture(int turns) async {
    final photo = await _channel.invokeMapMethod<String, Object?>(
      'takePicture',
      {'cameraId': cameraId, 'previewTurns': turns},
    );
    final path = photo?['path'];
    final cropTurns = photo?['cropTurns'];
    if (path is! String ||
        path.isEmpty ||
        cropTurns is! int ||
        !_validTurns(cropTurns)) {
      throw StateError('The camera returned an invalid photo.');
    }
    return (XFile(path), cropTurns);
  }

  void dispose() {
    events.setMethodCallHandler(null);
    previewTurns.dispose();
  }
}

class _PluginScanCameraSession implements ScanCameraSession {
  _PluginScanCameraSession(this._controller, {_DuoScanRotation? rotation})
    : _rotation = rotation;

  final CameraController _controller;
  final _DuoScanRotation? _rotation;
  int? _builtPreviewTurns;
  var _flashEnabled = false;

  @override
  bool get flashEnabled => _flashEnabled;

  Size? _orientedPreviewSize(int? turns) {
    final size = _controller.value.previewSize;
    if (size == null) return null;
    if (turns != null) return turns.isOdd ? size.flipped : size;
    return size.flipped;
  }

  @override
  Widget buildPreview() {
    final rotation = _rotation;
    if (rotation == null) return _buildPreview(null);
    return ValueListenableBuilder<int?>(
      valueListenable: rotation.previewTurns,
      builder: (context, turns, child) {
        _builtPreviewTurns = turns;
        return _buildPreview(turns);
      },
    );
  }

  Widget _buildPreview(int? turns) {
    final previewSize = _orientedPreviewSize(turns);
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize?.width ?? 1,
            height: previewSize?.height ?? 1,
            child: turns == null
                ? CameraPreview(_controller)
                : _controller.buildPreview(),
          ),
        ),
      ),
    );
  }

  @override
  Future<ScanImage> takePhoto({
    required Rect viewfinder,
    required Size viewport,
  }) async {
    final rotation = _rotation;
    final turns = rotation?.previewTurns.value;
    // 原生角度变化到 Flutter 重绘之间，暂缓拍照以免按新尺寸裁剪旧取景。
    if (rotation != null && (turns == null || turns != _builtPreviewTurns)) {
      throw StateError('Camera orientation changed. Try again.');
    }
    final previewSize = _orientedPreviewSize(turns);
    if (previewSize == null) {
      throw StateError('Camera preview dimensions are unavailable.');
    }
    final (image, cropTurns) = rotation != null && turns != null
        ? await rotation.takePicture(turns)
        : (await _controller.takePicture(), 0);
    final bytes = await const ScanNativeImageProcessor().cropViewfinder(
      await image.readAsBytes(),
      viewfinder: viewfinder,
      viewport: viewport,
      previewSize: previewSize,
      clockwiseQuarterTurns: cropTurns,
    );
    return ScanImage(
      bytes: bytes,
      fileName: image.name,
      viewfinderCropped: true,
    );
  }

  @override
  Future<bool> toggleFlash() async {
    _flashEnabled = !_flashEnabled;
    try {
      await _controller.setFlashMode(
        _flashEnabled ? FlashMode.torch : FlashMode.off,
      );
      return _flashEnabled;
    } on CameraException {
      _flashEnabled = false;
      await _controller.setFlashMode(FlashMode.off).catchError((_) {});
      return false;
    }
  }

  @override
  Future<void> pausePreview() => _controller.pausePreview();

  @override
  Future<void> resumePreview() => _controller.resumePreview();

  @override
  Future<void> dispose() async {
    _rotation?.dispose();
    try {
      await _controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // The camera may already be unavailable while the app is backgrounding.
    }
    await _controller.dispose();
  }
}

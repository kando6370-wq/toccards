import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/scan/scan_image_hasher.dart';
import 'scan_result_source.dart';

abstract interface class ScanCameraSession {
  Widget buildPreview();
  bool get flashEnabled;
  Future<ScanImage> takePhoto();
  Future<void> startImageStream(void Function(ScanCameraFrame frame) onFrame);
  Future<void> stopImageStream();
  Future<bool> toggleFlash();
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
      await controller.setFlashMode(FlashMode.off);
      return PluginScanCameraSession(controller);
    } catch (_) {
      await controller?.dispose();
      return null;
    }
  }
}

class PluginScanCameraSession implements ScanCameraSession {
  PluginScanCameraSession(this._controller);

  final CameraController _controller;
  var _flashEnabled = false;

  @override
  bool get flashEnabled => _flashEnabled;

  @override
  Widget buildPreview() {
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller.value.previewSize?.height ?? 1,
            height: _controller.value.previewSize?.width ?? 1,
            child: CameraPreview(_controller),
          ),
        ),
      ),
    );
  }

  @override
  Future<ScanImage> takePhoto() async {
    final image = await _controller.takePicture();
    return ScanImage(bytes: await image.readAsBytes(), fileName: image.name);
  }

  @override
  Future<void> startImageStream(
    void Function(ScanCameraFrame frame) onFrame,
  ) async {
    if (_controller.value.isStreamingImages) return;
    await _controller.startImageStream((image) {
      final format = switch (image.format.group) {
        ImageFormatGroup.bgra8888 => ScanFrameFormat.bgra8888,
        ImageFormatGroup.yuv420 => ScanFrameFormat.yuv420,
        ImageFormatGroup.jpeg => ScanFrameFormat.jpeg,
        _ => null,
      };
      if (format == null) return;
      onFrame(
        ScanCameraFrame(
          width: image.width,
          height: image.height,
          format: format,
          planes: [
            for (final plane in image.planes)
              ScanFramePlane(
                bytes: Uint8List.fromList(plane.bytes),
                bytesPerRow: plane.bytesPerRow,
                bytesPerPixel:
                    plane.bytesPerPixel ??
                    (format == ScanFrameFormat.bgra8888 ? 4 : 1),
              ),
          ],
        ),
      );
    });
  }

  @override
  Future<void> stopImageStream() async {
    if (_controller.value.isStreamingImages) {
      await _controller.stopImageStream();
    }
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
  Future<void> dispose() async {
    await stopImageStream();
    try {
      await _controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // The camera may already be unavailable while the app is backgrounding.
    }
    await _controller.dispose();
  }
}

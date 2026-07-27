import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

enum ScanPermissionResult { granted, denied, permanentlyDenied }

abstract interface class ScanPermissionGateway {
  Future<ScanPermissionResult> requestCamera();
  Future<ScanPermissionResult> requestGallery();
  Future<bool> openSettings();
}

final scanPermissionGatewayProvider = Provider<ScanPermissionGateway>(
  (ref) => const PluginScanPermissionGateway(),
);

class PluginScanPermissionGateway implements ScanPermissionGateway {
  const PluginScanPermissionGateway();

  @override
  Future<ScanPermissionResult> requestCamera() => _request(Permission.camera);

  @override
  Future<ScanPermissionResult> requestGallery() async {
    if (kIsWeb) return ScanPermissionResult.granted;
    final photos = await _request(Permission.photos);
    if (photos != ScanPermissionResult.denied ||
        defaultTargetPlatform != TargetPlatform.android) {
      return photos;
    }
    return _request(Permission.storage);
  }

  Future<ScanPermissionResult> _request(Permission permission) async {
    if (kIsWeb) return ScanPermissionResult.granted;
    var status = await permission.status;
    if (status.isGranted || status.isLimited) {
      return ScanPermissionResult.granted;
    }
    if (!status.isPermanentlyDenied && !status.isRestricted) {
      status = await permission.request();
    }
    if (status.isGranted || status.isLimited) {
      return ScanPermissionResult.granted;
    }
    return status.isPermanentlyDenied || status.isRestricted
        ? ScanPermissionResult.permanentlyDenied
        : ScanPermissionResult.denied;
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}

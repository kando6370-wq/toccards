import 'dart:math';

import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_storage.dart';

class InMemoryAuthStorage implements AuthStorage {
  AuthSession? _session;
  AuthSession? _previousAnonymousSession;
  String? _deviceId;

  @override
  Future<AuthSession?> readSession() async => _session;

  @override
  Future<AuthSession?> readPreviousAnonymousSession() async {
    return _previousAnonymousSession;
  }

  @override
  Future<void> writeSession(AuthSession session) async {
    if (session.isUser && (_session?.isAnonymous ?? false)) {
      _previousAnonymousSession = _session;
    }
    _session = session;
  }

  @override
  Future<void> clearUserSession() async {
    if (_session?.isUser ?? false) {
      _session = null;
    }
  }

  @override
  Future<void> clearAnonymousSession() async {
    _previousAnonymousSession = null;
    if (_session?.isAnonymous ?? false) {
      _session = null;
    }
  }

  @override
  Future<String> readOrCreateDeviceId() async {
    return _deviceId ??= _createUuidV4();
  }
}

String _createUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

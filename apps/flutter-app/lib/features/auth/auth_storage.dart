import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_models.dart';

abstract interface class AuthStorage {
  Future<AuthSession?> readSession();
  Future<AuthSession?> readPreviousAnonymousSession();
  Future<void> writeSession(AuthSession session);
  Future<void> clearUserSession();
  Future<void> clearAnonymousSession();
  Future<String> readOrCreateDeviceId();
}

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

class SecureAuthStorage implements AuthStorage {
  const SecureAuthStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _sessionKey = 'auth.session';
  static const _previousAnonymousSessionKey = 'auth.previous_anonymous_session';
  static const _deviceIdKey = 'auth.device_id';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> readSession() => _readSession(_sessionKey);

  @override
  Future<AuthSession?> readPreviousAnonymousSession() {
    return _readSession(_previousAnonymousSessionKey);
  }

  @override
  Future<void> writeSession(AuthSession session) async {
    final currentSession = await readSession();
    if (session.isUser && currentSession?.isAnonymous == true) {
      await _writeSession(_previousAnonymousSessionKey, currentSession!);
    }
    await _writeSession(_sessionKey, session);
  }

  @override
  Future<void> clearUserSession() async {
    if ((await readSession())?.isUser == true) {
      await _storage.delete(key: _sessionKey);
    }
  }

  @override
  Future<void> clearAnonymousSession() async {
    await _storage.delete(key: _previousAnonymousSessionKey);
    if ((await readSession())?.isAnonymous == true) {
      await _storage.delete(key: _sessionKey);
    }
  }

  @override
  Future<String> readOrCreateDeviceId() async {
    final stored = await _storage.read(key: _deviceIdKey);
    if (stored != null && _uuidV4Pattern.hasMatch(stored)) {
      return stored;
    }
    final deviceId = _createUuidV4();
    await _storage.write(key: _deviceIdKey, value: deviceId);
    return deviceId;
  }

  Future<AuthSession?> _readSession(String key) async {
    final encoded = await _storage.read(key: key);
    if (encoded == null) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) return null;
      return _sessionFromJson(Map<String, Object?>.from(value));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeSession(String key, AuthSession session) {
    return _storage.write(key: key, value: jsonEncode(_sessionToJson(session)));
  }
}

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

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

Map<String, Object?> _sessionToJson(AuthSession session) {
  return {
    'owner_type': session.ownerType.name,
    'access_token': session.accessToken,
    'refresh_token': session.refreshToken,
    'anonymous_id': session.anonymousId,
    'user_id': session.userId,
    'email': session.email,
    'login_method': session.loginMethod?.name,
  };
}

AuthSession? _sessionFromJson(Map<String, Object?> value) {
  final ownerType = switch (value['owner_type']) {
    'anonymous' => OwnerType.anonymous,
    'user' => OwnerType.user,
    _ => null,
  };
  final accessToken = _nonEmptyString(value['access_token']);
  final refreshToken = _nonEmptyString(value['refresh_token']);
  final anonymousId = _nonEmptyString(value['anonymous_id']);
  final userId = _nonEmptyString(value['user_id']);
  if (ownerType == null ||
      accessToken == null ||
      refreshToken == null ||
      (ownerType == OwnerType.anonymous && anonymousId == null) ||
      (ownerType == OwnerType.user && userId == null)) {
    return null;
  }
  final loginMethod = switch (value['login_method']) {
    'email' => LoginMethod.email,
    'google' => LoginMethod.google,
    'apple' => LoginMethod.apple,
    _ => null,
  };
  return AuthSession(
    ownerType: ownerType,
    accessToken: accessToken,
    refreshToken: refreshToken,
    anonymousId: anonymousId,
    userId: userId,
    email: _nonEmptyString(value['email']),
    loginMethod: loginMethod,
  );
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

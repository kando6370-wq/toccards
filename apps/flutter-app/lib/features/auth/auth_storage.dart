import 'auth_models.dart';

class InMemoryAuthStorage {
  AuthSession? _session;

  Future<AuthSession?> readSession() async => _session;

  Future<void> writeSession(AuthSession session) async {
    _session = session;
  }

  Future<void> clearUserSession() async {
    if (_session?.isUser ?? false) {
      _session = null;
    }
  }

  Future<void> clearAnonymousSession() async {
    if (_session?.isAnonymous ?? false) {
      _session = null;
    }
  }
}

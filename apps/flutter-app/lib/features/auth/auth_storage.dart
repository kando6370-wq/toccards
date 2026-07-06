import 'auth_models.dart';

class InMemoryAuthStorage {
  AuthSession? _session;
  AuthSession? _previousAnonymousSession;

  Future<AuthSession?> readSession() async => _session;

  Future<AuthSession?> readPreviousAnonymousSession() async {
    return _previousAnonymousSession;
  }

  Future<void> writeSession(AuthSession session) async {
    if (session.isUser && (_session?.isAnonymous ?? false)) {
      _previousAnonymousSession = _session;
    }
    _session = session;
  }

  Future<void> clearUserSession() async {
    if (_session?.isUser ?? false) {
      _session = null;
    }
  }

  Future<void> clearAnonymousSession() async {
    _previousAnonymousSession = null;
    if (_session?.isAnonymous ?? false) {
      _session = null;
    }
  }
}

enum OwnerType { anonymous, user }

enum LoginMethod { email, google, apple }

extension LoginMethodDisplay on LoginMethod {
  String get displayName => name.toUpperCase();
}

class AuthSession {
  const AuthSession({
    required this.ownerType,
    required this.accessToken,
    required this.refreshToken,
    this.anonymousId,
    this.userId,
    this.email,
    this.loginMethod,
  });

  final OwnerType ownerType;
  final String accessToken;
  final String refreshToken;
  final String? anonymousId;
  final String? userId;
  final String? email;
  final LoginMethod? loginMethod;

  bool get isAnonymous => ownerType == OwnerType.anonymous;
  bool get isUser => ownerType == OwnerType.user;
}

class AuthState {
  const AuthState.loading()
    : session = null,
      isLoading = true,
      pendingMigrationAnonymousId = null;

  const AuthState.ready({
    required this.session,
    this.pendingMigrationAnonymousId,
  }) : isLoading = false;

  final AuthSession? session;
  final bool isLoading;
  final String? pendingMigrationAnonymousId;
}

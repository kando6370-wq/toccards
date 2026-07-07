enum OwnerType { anonymous, user }

class AuthSession {
  const AuthSession({
    required this.ownerType,
    required this.accessToken,
    required this.refreshToken,
    this.anonymousId,
    this.userId,
    this.email,
  });

  final OwnerType ownerType;
  final String accessToken;
  final String refreshToken;
  final String? anonymousId;
  final String? userId;
  final String? email;

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

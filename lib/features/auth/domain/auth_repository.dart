enum AuthStatus {
  guest,
  restoring,
  creatingQr,
  waitingWeb,
  authenticating,
  waitingScan,
  waitingConfirm,
  expired,
  signedIn,
  failed,
}

final class AuthState {
  const AuthState({
    this.status = AuthStatus.guest,
    this.userName,
    this.avatarUrl,
    this.mid,
    this.qrUri,
    this.message,
  });
  final AuthStatus status;
  final String? userName;
  final Uri? avatarUrl;
  final String? mid;
  final Uri? qrUri;
  final String? message;
  bool get isSignedIn => status == AuthStatus.signedIn;
  bool get isBusy => const {
    AuthStatus.restoring,
    AuthStatus.creatingQr,
    AuthStatus.waitingWeb,
    AuthStatus.authenticating,
  }.contains(status);
}

/// Identity of one user-initiated browser login, invalidated when cancelled.
final class WebLoginAttempt {
  WebLoginAttempt();
}

final class LoginCookie {
  const LoginCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    this.expires,
  });
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expires;
}

abstract interface class WebAuthRepository implements AuthRepository {
  WebLoginAttempt? beginWebLogin();
  Future<void> completeWebLogin(
    WebLoginAttempt attempt,
    List<LoginCookie> cookies,
  );
}

abstract interface class AuthRepository {
  AuthState get current;
  Stream<AuthState> get changes;
  Future<void> restore();
  Future<void> signIn();
  void cancelSignIn();
  Future<void> signOut();
}

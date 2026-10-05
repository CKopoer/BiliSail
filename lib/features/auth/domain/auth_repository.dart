enum AuthStatus {
  guest,
  restoring,
  creatingQr,
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
}

abstract interface class AuthRepository {
  AuthState get current;
  Stream<AuthState> get changes;
  Future<void> restore();
  Future<void> signIn();
  void cancelSignIn();
  Future<void> signOut();
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import '../domain/password_sms_auth_repository.dart';
import '../../../domain/app_failure.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('AuthRepository'),
);
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((value) => state = value);
    ref.onDispose(subscription.cancel);
    return repository.current;
  }

  void signIn() => unawaited(ref.read(authRepositoryProvider).signIn());
  void cancelSignIn() => ref.read(authRepositoryProvider).cancelSignIn();
  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();

  PasswordSmsAuthRepository get _passwordSms {
    final repository = ref.read(authRepositoryProvider);
    if (repository is PasswordSmsAuthRepository) return repository;
    throw const AppFailure(AppFailureKind.protocol, '当前环境不支持密码和短信登录');
  }

  bool get passwordSmsSupported =>
      ref.read(authRepositoryProvider) is PasswordSmsAuthRepository;
  PasswordSmsLoginAttempt? beginPasswordSmsLogin() =>
      _passwordSms.beginPasswordSmsLogin();
  Future<PasswordSmsLoginStep> loginWithPassword(
    PasswordSmsLoginAttempt attempt,
    String username,
    String password, {
    LoginCaptchaProof? proof,
  }) =>
      _passwordSms.loginWithPassword(attempt, username, password, proof: proof);
  Future<PasswordSmsLoginStep> sendLoginSms(
    PasswordSmsLoginAttempt attempt,
    String countryCode,
    String phone, {
    LoginCaptchaProof? proof,
  }) => _passwordSms.sendLoginSms(attempt, countryCode, phone, proof: proof);
  Future<PasswordSmsLoginStep> loginWithSms(
    PasswordSmsLoginAttempt attempt,
    String code, {
    LoginCaptchaProof? proof,
  }) => _passwordSms.loginWithSms(attempt, code, proof: proof);
  Future<PasswordSmsLoginStep> refreshLoginCaptcha(
    PasswordSmsLoginAttempt attempt,
  ) => _passwordSms.refreshLoginCaptcha(attempt);
  Future<PasswordSmsLoginStep> sendVerificationSms(
    PasswordSmsLoginAttempt attempt, {
    LoginCaptchaProof? proof,
  }) => _passwordSms.sendVerificationSms(attempt, proof: proof);
  Future<PasswordSmsLoginStep> verifyLoginPhone(
    PasswordSmsLoginAttempt attempt,
    String code,
  ) => _passwordSms.verifyLoginPhone(attempt, code);

  WebAuthRepository? get _webAuth {
    final repository = ref.read(authRepositoryProvider);
    return repository is WebAuthRepository ? repository : null;
  }

  WebLoginAttempt? beginWebLogin() => _webAuth?.beginWebLogin();
  Future<void> completeWebLogin(
    WebLoginAttempt attempt,
    List<LoginCookie> cookies,
  ) async {
    await _webAuth?.completeWebLogin(attempt, cookies);
  }
}

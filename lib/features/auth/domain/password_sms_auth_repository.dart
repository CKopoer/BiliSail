import 'auth_repository.dart';

final class PasswordSmsLoginAttempt {
  PasswordSmsLoginAttempt();
}

final class LoginCaptchaProof {
  const LoginCaptchaProof(this.challenge, this.validate, this.seccode);
  final String challenge, validate, seccode;
}

final class LoginCaptchaException implements Exception {
  const LoginCaptchaException({this.configurationUnavailable = false});
  final bool configurationUnavailable;
}

enum PasswordSmsLoginStage { ready, captcha, smsSent, verifyPhone, completed }

final class PasswordSmsLoginStep {
  const PasswordSmsLoginStep(
    this.stage, {
    this.gt,
    this.challenge,
    this.maskedPhone,
    this.canRefreshCaptcha = false,
  });
  final PasswordSmsLoginStage stage;
  final String? gt, challenge, maskedPhone;
  final bool canRefreshCaptcha;
}

abstract interface class PasswordSmsAuthRepository implements AuthRepository {
  PasswordSmsLoginAttempt? beginPasswordSmsLogin();
  Future<PasswordSmsLoginStep> loginWithPassword(
    PasswordSmsLoginAttempt attempt,
    String username,
    String password, {
    LoginCaptchaProof? proof,
  });
  Future<PasswordSmsLoginStep> sendLoginSms(
    PasswordSmsLoginAttempt attempt,
    String countryCode,
    String phone, {
    LoginCaptchaProof? proof,
  });
  Future<PasswordSmsLoginStep> loginWithSms(
    PasswordSmsLoginAttempt attempt,
    String code, {
    LoginCaptchaProof? proof,
  });
  Future<PasswordSmsLoginStep> refreshLoginCaptcha(
    PasswordSmsLoginAttempt attempt,
  );
  Future<PasswordSmsLoginStep> sendVerificationSms(
    PasswordSmsLoginAttempt attempt, {
    LoginCaptchaProof? proof,
  });
  Future<PasswordSmsLoginStep> verifyLoginPhone(
    PasswordSmsLoginAttempt attempt,
    String code,
  );
}

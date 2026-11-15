import 'dart:async';

import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/domain/password_sms_auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_dialog.dart';
import 'package:bilisail/features/auth/presentation/password_sms_login_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Auth repository;
  setUp(() => repository = _Auth());
  Future<void> open(
    WidgetTester tester, {
    double textScale = 1,
    LoginCaptchaPresenter? captcha,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          if (captcha != null)
            loginCaptchaPresenterProvider.overrideWithValue(captcha),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: AccountDialog()),
        ),
      ),
    );
    await tester.ensureVisible(find.text('密码 / 短信登录'));
    await tester.tap(find.text('密码 / 短信登录'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'password entry uses the App login controller and captcha continuation',
    (tester) async {
      var verifications = 0;
      repository.captcha = true;
      await open(
        tester,
        captcha: (_, gt, challenge) async {
          verifications++;
          expect(gt, 'fixture-gt');
          return const LoginCaptchaProof(
            'proof-challenge',
            'passed',
            'passed|jordan',
          );
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, '手机号 / 邮箱'),
        'fixture',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '密码'),
        'fixture-password',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '密码'))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(verifications, 1);
      expect(repository.passwordCalls, 2);
      expect(repository.password, 'fixture-password');
      expect(find.byType(PasswordSmsLoginDialog), findsNothing);
    },
  );

  testWidgets(
    'SMS waits for explicit send and permits reading messages in background',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('短信登录'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '手机号'),
        '13800000000',
      );
      expect(repository.smsSends, 0);
      await tester.tap(find.text('获取短信验证码'));
      await tester.pumpAndSettle();
      expect(repository.smsSends, 1);
      expect(repository.phone, '13800000000');
      expect(find.text('60s 后重发'), findsOneWidget);
      final cancelled = repository.cancels;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(repository.cancels, cancelled);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.enterText(find.widgetWithText(TextField, '短信验证码'), '123456');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(repository.code, '123456');
      expect(find.byType(PasswordSmsLoginDialog), findsNothing);
    },
  );

  testWidgets('password risk verification waits for a separate SMS captcha', (
    tester,
  ) async {
    repository.captcha = true;
    repository.phoneVerification = true;
    final registrations = <String>[];
    await open(
      tester,
      captcha: (_, gt, challenge) async {
        registrations.add(gt);
        return LoginCaptchaProof(challenge, 'passed', 'passed|jordan');
      },
    );
    await tester.enterText(
      find.widgetWithText(TextField, '手机号 / 邮箱'),
      'fixture',
    );
    await tester.enterText(find.widgetWithText(TextField, '密码'), 'fixture');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('验证绑定手机号'), findsOneWidget);
    expect(find.text('138****0000'), findsOneWidget);
    expect(registrations, ['fixture-gt']);
    expect(repository.verificationSends, 0);
    await tester.tap(find.text('获取短信验证码'));
    await tester.pumpAndSettle();
    expect(registrations, ['fixture-gt', 'verification-gt']);
    expect(repository.verificationSends, 2);
    expect(repository.verificationProof?.challenge, 'verification-challenge');
    expect(repository.captchaRefreshes, 0);
    expect(find.text('60s 后重发'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '短信验证码'), '123456');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(repository.code, '123456');
    expect(find.byType(PasswordSmsLoginDialog), findsNothing);
  });

  for (final unavailableAfterRefresh in [false, true]) {
    testWidgets(
      'SMS refreshes an unavailable captcha once: stillUnavailable=$unavailableAfterRefresh',
      (tester) async {
        repository.smsCaptcha = true;
        var captchas = 0;
        await open(
          tester,
          captcha: (_, gt, challenge) async {
            captchas++;
            if (captchas == 1 || unavailableAfterRefresh) {
              throw const LoginCaptchaException(configurationUnavailable: true);
            }
            expect(gt, 'refreshed-gt');
            return const LoginCaptchaProof(
              'refreshed-challenge',
              'passed',
              'passed|jordan',
            );
          },
        );
        await tester.tap(find.text('短信登录'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '手机号'),
          '13800000000',
        );
        await tester.tap(find.text('获取短信验证码'));
        await tester.pumpAndSettle();
        expect(repository.captchaRefreshes, 1);
        expect(captchas, 2);
        expect(repository.smsSends, unavailableAfterRefresh ? 1 : 2);
        if (unavailableAfterRefresh) {
          expect(find.text('验证码配置已失效，请重新发起登录或使用扫码登录'), findsOneWidget);
        } else {
          expect(find.text('60s 后重发'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'password captcha failure gives a verification error without refreshing',
    (tester) async {
      repository.captcha = true;
      await open(
        tester,
        captcha: (_, gt, challenge) async {
          throw const LoginCaptchaException(configurationUnavailable: true);
        },
      );
      await tester.enterText(
        find.widgetWithText(TextField, '手机号 / 邮箱'),
        'fixture',
      );
      await tester.enterText(find.widgetWithText(TextField, '密码'), 'fixture');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();
      expect(repository.passwordCalls, 1);
      expect(repository.captchaRefreshes, 0);
      expect(find.text('验证码配置已失效，请重新发起登录或使用扫码登录'), findsOneWidget);
    },
  );

  testWidgets('closing a pending login ignores a late successful response', (
    tester,
  ) async {
    repository.pending = Completer<PasswordSmsLoginStep>();
    await open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, '手机号 / 邮箱'),
      'fixture',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '密码'),
      'fixture-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump();
    await tester.tap(find.byTooltip('关闭密码短信登录'));
    await tester.pumpAndSettle();
    repository.pending!.complete(
      const PasswordSmsLoginStep(PasswordSmsLoginStage.completed),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccountDialog), findsOneWidget);
    expect(repository.cancels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'password and SMS forms fit narrow screens with keyboard and large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });
      await open(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('短信登录'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

class _Auth implements PasswordSmsAuthRepository {
  int passwordCalls = 0, smsSends = 0, cancels = 0;
  String? password, phone, code;
  bool captcha = false, smsCaptcha = false, phoneVerification = false;
  int verificationSends = 0;
  LoginCaptchaProof? verificationProof;
  int captchaRefreshes = 0;
  Completer<PasswordSmsLoginStep>? pending;
  @override
  AuthState get current =>
      const AuthState(status: AuthStatus.waitingPasswordSms);
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  PasswordSmsLoginAttempt? beginPasswordSmsLogin() => PasswordSmsLoginAttempt();
  @override
  Future<PasswordSmsLoginStep> loginWithPassword(
    PasswordSmsLoginAttempt attempt,
    String username,
    String password, {
    LoginCaptchaProof? proof,
  }) async {
    passwordCalls++;
    this.password = password;
    if (captcha && proof == null) {
      return const PasswordSmsLoginStep(
        PasswordSmsLoginStage.captcha,
        gt: 'fixture-gt',
        challenge: 'fixture-challenge',
      );
    }
    if (phoneVerification) {
      return const PasswordSmsLoginStep(
        PasswordSmsLoginStage.verifyPhone,
        maskedPhone: '138****0000',
      );
    }
    return await pending?.future ??
        const PasswordSmsLoginStep(PasswordSmsLoginStage.completed);
  }

  @override
  Future<PasswordSmsLoginStep> sendLoginSms(
    PasswordSmsLoginAttempt attempt,
    String countryCode,
    String phone, {
    LoginCaptchaProof? proof,
  }) async {
    smsSends++;
    this.phone = phone;
    if (smsCaptcha && proof == null) {
      return const PasswordSmsLoginStep(
        PasswordSmsLoginStage.captcha,
        gt: 'fixture-gt',
        challenge: 'fixture-challenge',
        canRefreshCaptcha: true,
      );
    }
    return const PasswordSmsLoginStep(PasswordSmsLoginStage.smsSent);
  }

  @override
  Future<PasswordSmsLoginStep> loginWithSms(
    PasswordSmsLoginAttempt attempt,
    String code, {
    LoginCaptchaProof? proof,
  }) async {
    this.code = code;
    return const PasswordSmsLoginStep(PasswordSmsLoginStage.completed);
  }

  @override
  Future<PasswordSmsLoginStep> refreshLoginCaptcha(
    PasswordSmsLoginAttempt attempt,
  ) async {
    captchaRefreshes++;
    return const PasswordSmsLoginStep(
      PasswordSmsLoginStage.captcha,
      gt: 'refreshed-gt',
      challenge: 'refreshed-challenge',
    );
  }

  @override
  Future<PasswordSmsLoginStep> sendVerificationSms(
    PasswordSmsLoginAttempt attempt, {
    LoginCaptchaProof? proof,
  }) async {
    verificationSends++;
    if (proof == null) {
      return const PasswordSmsLoginStep(
        PasswordSmsLoginStage.captcha,
        gt: 'verification-gt',
        challenge: 'verification-challenge',
        canRefreshCaptcha: true,
      );
    }
    verificationProof = proof;
    return const PasswordSmsLoginStep(PasswordSmsLoginStage.smsSent);
  }

  @override
  Future<PasswordSmsLoginStep> verifyLoginPhone(
    PasswordSmsLoginAttempt attempt,
    String code,
  ) => loginWithSms(attempt, code);
  @override
  void cancelSignIn() => cancels++;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
}

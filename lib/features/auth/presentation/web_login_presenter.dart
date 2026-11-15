import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/passport_web_login.dart';
import '../domain/auth_repository.dart';

typedef WebLoginPresenter = Future<List<LoginCookie>?> Function(BuildContext);

// 暂时隐藏官网登录入口，保留 WebView、会话交接及平台能力实现。
final webLoginSupportedProvider = Provider<bool>((ref) => false);

final webLoginPresenterProvider = Provider<WebLoginPresenter>(
  (ref) => (context) async {
    final cookies = await showPassportWebLogin(context);
    return cookies == null
        ? null
        : List<LoginCookie>.unmodifiable([
            for (final cookie in cookies)
              LoginCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                hostOnly: cookie.hostOnly,
                secure: cookie.secure,
                expires: cookie.expires,
              ),
          ]);
  },
);

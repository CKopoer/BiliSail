import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/passport_web_login.dart';
import '../domain/auth_repository.dart';

typedef WebLoginPresenter = Future<List<LoginCookie>?> Function(BuildContext);

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

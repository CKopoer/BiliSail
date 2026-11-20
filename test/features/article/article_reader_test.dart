import 'dart:async';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/article_address.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/article/application/article_provider.dart';
import 'package:bilisail/features/article/domain/article_document.dart';
import 'package:bilisail/features/article/domain/article_repository.dart';
import 'package:bilisail/features/article/presentation/article_screen.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/dynamic_fakes.dart';

const _column = ArticleAddress(ArticleKind.column, '789');
const _opus = ArticleAddress(ArticleKind.opus, '98765432101234567890');
const _settings = AppSettings.defaults(
  navigationMode: WorkspaceNavigationMode.singlePage,
);

void main() {
  test(
    'validates article destinations without interpreting dynamic IDs as cv IDs',
    () {
      for (final (value, expected) in [
        ('https://www.bilibili.com/read/cv789/?spm=x', _column),
        ('https://m.bilibili.com/mobile/opus/${_opus.id}', _opus),
        ('https://t.bilibili.com/789', null),
        ('https://evil.invalid/read/cv789', null),
        ('https://name@www.bilibili.com/read/cv789', null),
        ('https://www.bilibili.com:444/opus/789', null),
        ('https://www.bilibili.com/read/cv0789', null),
      ]) {
        expect(ArticleAddress.fromWebUri(Uri.parse(value)), expected);
      }
    },
  );

  testWidgets('opens cv and opus bodies in their own workspace and returns', (
    tester,
  ) async {
    final auth = DynamicAuthFake(signedIn: false);
    addTearDown(auth.stream.close);
    final repository = _Repository((address, _) async {
      if (address == _column) {
        return _document(address, '旧文章', '旧文章正文', linkLabel: '阅读新版图文');
      }
      expect(address, _opus);
      return _document(address, '图文作品', '整篇图文正文');
    });
    final router = createBiliRouter(
      initialLocation: _column.location,
      playerBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          articleRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(auth),
          settingsRepositoryProvider.overrideWithValue(const _Settings()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.text('旧文章正文'), findsOneWidget);
    await tester.tapAt(
      tester.getTopLeft(find.text('阅读新版图文')) + const Offset(12, 12),
    );
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, _opus.location);
    expect(find.text('整篇图文正文'), findsOneWidget);
    expect(find.text('旧文章正文'), findsNothing);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, _column.location);
    expect(find.text('旧文章正文'), findsOneWidget);
    expect(repository.reads, [_column, _opus]);
  });

  testWidgets(
    'account transitions cancel older reads and retry uses the current session',
    (tester) async {
      final auth = DynamicAuthFake();
      addTearDown(auth.stream.close);
      final old = Completer<ArticleDocument>();
      final current = Completer<ArticleDocument>();
      final attempts = <RequestCancellation>[];
      var epoch = 0;
      final repository = _Repository((address, cancellation) async {
        attempts.add(cancellation);
        return switch ((epoch, attempts.length)) {
          (0, _) => old.future,
          (1, 2) => current.future,
          _ => _document(address, '当前账号的正文', '完整正文'),
        };
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            articleRepositoryProvider.overrideWithValue(repository),
            authRepositoryProvider.overrideWithValue(auth),
            sessionEpochProvider.overrideWithValue(() => epoch),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ArticleScreen(
                address: _column,
                onOpenUser: (_) {},
                onOpenLink: (_) {},
                onOpenWeb: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在加载专栏…'), findsOneWidget);
      epoch++;
      auth.change(const AuthState(status: AuthStatus.guest));
      await tester.pump();
      expect(attempts.first.isCancelled, isTrue);
      old.complete(_document(_column, '旧账号的专栏', '旧账号内容'));
      current.completeError(
        const AppFailure(AppFailureKind.notFound, '专栏不存在或已被删除'),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧账号内容'), findsNothing);
      expect(find.text('专栏不存在或已被删除'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('完整正文'), findsOneWidget);
    },
  );
}

ArticleDocument _document(
  ArticleAddress address,
  String title,
  String text, {
  String? linkLabel,
}) => ArticleDocument(
  url: address.webUri,
  title: title,
  blocks: [
    ArticleBlock(
      ArticleBlockKind.paragraph,
      text: [
        (text: text, link: null, bold: false, italic: false, strike: false),
      ],
    ),
    if (linkLabel != null)
      ArticleBlock(
        ArticleBlockKind.paragraph,
        text: [
          (
            text: linkLabel,
            link: _opus.webUri,
            bold: false,
            italic: false,
            strike: false,
          ),
        ],
      ),
  ],
);

final class _Settings implements SettingsRepository {
  const _Settings();

  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

final class _Repository implements ArticleRepository {
  _Repository(this.load);
  final Future<ArticleDocument> Function(ArticleAddress, RequestCancellation)
  load;
  final reads = <ArticleAddress>[];

  @override
  Future<ArticleDocument> read(
    ArticleAddress address,
    RequestCancellation cancellation,
  ) {
    reads.add(address);
    return load(address, cancellation);
  }
}

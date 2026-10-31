import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/features/video/data/api_video_actions_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'video_actions_bar_test.dart' show testPart;
import 'video_danmaku_composer_test.dart'
    show FakeComposerSession, pumpComposer;

void main() {
  for (final (mode, modeLabel) in [(1, '滚动'), (4, '底部'), (5, '顶部')]) {
    for (final (color, colorLabel) in [
      (0xffffff, '白色'),
      (0xff6699, '粉色'),
      (0xffd700, '金色'),
      (0x00a1d6, '蓝色'),
      (0xfe0302, '红色'),
      (0x00cd00, '绿色'),
      (0x222222, '深灰色'),
    ]) {
      testWidgets('$modeLabel $colorLabel reaches API and acknowledged echo', (
        tester,
      ) async {
        final transport = _SendTransport();
        final session = FakeComposerSession();
        addTearDown(session.dispose);
        await pumpComposer(tester, _repository(transport), session: session);
        await _choose(tester, colorLabel);
        await _choose(tester, modeLabel);
        await tester.enterText(find.byType(TextField), '中文 &+=%/#');
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(transport.posts, hasLength(1));
        final fields = transport.posts.single;
        expect(fields['oid'], testPart.cid);
        expect(fields['msg'], '中文 &+=%/#');
        expect(fields['progress'], '12000');
        expect(fields['mode'], '$mode');
        expect(fields['color'], '$color');
        expect(fields['csrf'], 'fixture-csrf');
        expect(fields['rnd'], '${_now.microsecondsSinceEpoch}');
        expect(session.sent, [
          (id: '9007199254740993', text: '中文 &+=%/#', mode: mode, color: color),
        ]);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.text('弹幕已发送'), findsOneWidget);
      });
    }
  }

  testWidgets(
    'custom RGB preserves the draft and reaches the API without alpha',
    (tester) async {
      final transport = _SendTransport();
      final session = FakeComposerSession();
      addTearDown(session.dispose);
      await pumpComposer(tester, _repository(transport), session: session);
      await tester.enterText(find.byType(TextField), 'custom draft');
      await tester.tap(find.byTooltip('发送弹幕样式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自定义颜色'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('danmaku-send-hex')),
        '000001',
      );
      await tester.ensureVisible(find.text('完成'));
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(transport.posts, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'custom draft',
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(transport.posts.single['color'], '1');
      expect(session.sent.single.color, 1);
    },
  );

  for (final uncertain in [false, true]) {
    testWidgets(
      '${uncertain ? 'uncertain' : 'rejected'} API send keeps draft without echo',
      (tester) async {
        final transport = _SendTransport()
          ..status = uncertain ? 503 : 200
          ..code = uncertain ? 0 : -101;
        final session = FakeComposerSession();
        addTearDown(session.dispose);
        await pumpComposer(tester, _repository(transport), session: session);
        await _choose(tester, '蓝色');
        await tester.enterText(find.byType(TextField), 'keep blue draft');
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(transport.posts, hasLength(1));
        expect(transport.posts.single['color'], '${0x00a1d6}');
        expect(session.sent, isEmpty);
        expect(find.text('弹幕已发送'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'keep blue draft',
        );
        if (uncertain) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pumpAndSettle();
          expect(transport.posts, hasLength(1));
        }
      },
    );
  }
}

final _now = DateTime.utc(2026, 10, 31, 1, 2, 3, 123, 456);

ApiVideoActionsRepository _repository(_SendTransport transport) {
  final requests = ApiRequests();
  final api = BiliApiClient(
    transport: transport,
    sessionProvider: requests,
    cookieJar: ApiCookieJar()
      ..receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture-session; Path=/; Secure',
        'bili_jct=fixture-csrf; Path=/; Secure',
      ]),
  );
  return ApiVideoActionsRepository(
    VideoActionsClient(api, clock: () => _now),
    requests,
    accountScope: () => 'user:1',
  );
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('发送弹幕样式'));
  await tester.pumpAndSettle();
  final color = find.byTooltip(label);
  await tester.tap(
    color.evaluate().isNotEmpty
        ? color
        : find.widgetWithText(ChoiceChip, label),
  );
  await tester.tap(find.text('完成'));
  await tester.pumpAndSettle();
}

final class _SendTransport implements ApiTransport, ApiFormTransport {
  int status = 200, code = 0;
  final posts = <Map<String, String>>[];
  ApiHttpResponse _response(Object? data, {int status = 200, int code = 0}) =>
      ApiHttpResponse(
        status,
        Uint8List.fromList(
          utf8.encode(jsonEncode({'code': code, 'data': data})),
        ),
        {},
      );

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => _response(switch (uri.path) {
    '/x/web-interface/archive/has/like' => 0,
    '/x/web-interface/archive/coins' => {'multiply': 0},
    '/x/v2/fav/video/favoured' => {'favoured': false},
    _ => throw StateError('Unexpected read'),
  });

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    expect(uri, Uri.https('api.bilibili.com', '/x/v2/dm/post'));
    posts.add(Map.of(fields));
    return _response(
      {'dmid_str': '9007199254740993'},
      status: status,
      code: code,
    );
  }
}

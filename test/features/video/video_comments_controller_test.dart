import 'package:bilisail/domain/user.dart';

import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_comments_controller.dart';
import 'package:bilisail/features/video/domain/video_comments_repository.dart';
import 'package:bilisail/features/video/presentation/video_comments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const root = CommentEntry(
  id: '10',
  author: '甲',
  authorId: UserId('100'),
  message: '原评论',
  ipLocation: 'IP属地：广东',
  replyCount: 3,
);
const child = CommentEntry(
  id: '11',
  author: '乙',
  authorId: UserId('101'),
  message: '回复',
  ipLocation: 'IP属地：上海',
  rootId: '10',
  parentId: '10',
);
void main() {
  late _Auth auth;
  late _Repo repo;
  late ProviderContainer container;
  late VideoCommentsController controller;
  VideoCommentsState state() =>
      container.read(videoCommentsControllerProvider('42'));
  setUp(() async {
    auth = _Auth();
    repo = _Repo();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoCommentsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(videoCommentsControllerProvider('42'), (_, _) {});
    controller = container.read(videoCommentsControllerProvider('42').notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.changesController.close();
  });
  test('comment copies preserve author IDs', () {
    expect(root.withLike(true).authorId, const UserId('100'));
    expect(root.withReplies([child]).authorId, const UserId('100'));
    expect(
      root.withReplies([child]).replies.single.authorId,
      const UserId('101'),
    );
  });
  testWidgets('root and nested identity open matching user', (tester) async {
    final opened = <UserId>[];
    repo.items = [
      root.withReplies([child]),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          videoCommentsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VideoCommentsPanel(detail: _detail, onOpenUser: opened.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('甲').first);
    expect(opened, [const UserId('100')]);
    await tester.tap(find.text('乙：').first);
    expect(opened.last, const UserId('101'));
    expect(find.text('详情').evaluate(), isEmpty);
    await tester.tap(find.textContaining('共 3 条回复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙').first);
    expect(opened.last, const UserId('101'));
  });
  test('emote loading discards response from previous session epoch', () async {
    repo.emotePending = Completer();
    final loading = controller.loadEmotes();
    expect(state().emotesLoading, true);
    repo.epoch++;
    repo.emotePending!.complete(const [CommentEmotePackage('old', [])]);
    await loading;
    expect(state().emotePackages, isEmpty);
  });
  test('logout cancels in-flight emotes and rejects late package', () async {
    repo.emotePending = Completer();
    final loading = controller.loadEmotes();
    final cancellation = repo.emoteCancellation!;
    repo.epoch++;
    auth.emit(const AuthState(status: AuthStatus.guest));
    await Future<void>.delayed(Duration.zero);
    expect(state().signedIn, false);
    expect(cancellation.isCancelled, true);
    repo.emotePending!.complete(const [CommentEmotePackage('private', [])]);
    await loading;
    expect(state().emotePackages, isEmpty);
    expect(state().emotesLoading, false);
  });
  test('emote packages load only once and disposal cancels request', () async {
    await controller.loadEmotes();
    expect(state().emotePackages.single.items.single.text, '[笑]');
    final cancellation = repo.emoteCancellation;
    await controller.loadEmotes();
    expect(repo.emoteCancellation, same(cancellation));
    container.dispose();
    expect(cancellation!.isCancelled, true);
    container = ProviderContainer();
  });
  test(
    'pagination uses selected sort, deduplicates and stops empty pages',
    () async {
      expect(state().items.length, 1);
      await controller.load();
      expect(repo.pages, [1, 2]);
      expect(state().items.length, 1);
      await controller.load(sort: CommentSort.latest);
      expect(repo.sort, CommentSort.latest);
      expect(state().page, 1);
      repo.empty = true;
      await controller.load();
      expect(state().hasMore, false);
    },
  );
  test(
    'reply to nested comment sends original root and selected parent',
    () async {
      await controller.openReplies(root);
      expect(state().replyItems.single.id, '11');
      controller.target(child);
      expect(await controller.send(' hello '), true);
      expect(repo.sentRoot, '10');
      expect(repo.sentParent, '11');
      expect(repo.sentText, 'hello');
      expect(state().replyItems.length, 2);
      controller.closeReplies();
      expect(state().openRoot, isNull);
      expect(state().items.single.replyCount, 4);
      expect(state().page, 1);
    },
  );
  test('uncertain send blocks replay until explicit acknowledgement', () async {
    repo.failure = const CommentWriteUncertain();
    expect(await controller.send('x'), false);
    expect(await controller.send('x'), false);
    expect(repo.writes, 1);
    await controller.load(refresh: true);
    expect(state().uncertain, contains('send'));
    controller.acknowledgeSend();
    repo.failure = null;
    expect(await controller.send('x'), true);
  });
  test(
    'busy prevents duplicate likes; confirmed success updates count',
    () async {
      repo.writePending = Completer<void>();
      final pending = controller.toggleLike(root);
      expect(await controller.toggleLike(root), false);
      expect(repo.writes, 1);
      repo.writePending!.complete();
      expect(await pending, true);
      expect(state().items.single.liked, true);
      expect(state().items.single.likeCount, 1);
    },
  );
  test('same account epoch transition rejects late read', () async {
    repo.pending = Completer<CommentPage>();
    final pending = controller.load(refresh: true);
    repo.epoch++;
    auth.emit(
      const AuthState(status: AuthStatus.signedIn, mid: '7', userName: '新会话'),
    );
    repo.pending!.complete(const CommentPage(items: [child], hasMore: false));
    await pending;
    expect(state().items.where((c) => c.id == child.id), isEmpty);
  });
  test('close reply view rejects late nested read', () async {
    repo.replyPending = Completer<CommentPage>();
    final pending = controller.openReplies(root);
    controller.closeReplies();
    repo.replyPending!.complete(
      const CommentPage(items: [child], hasMore: false),
    );
    await pending;
    expect(state().openRoot, isNull);
    expect(state().replyItems, isEmpty);
  });
  test('in-flight read cannot race a mutation', () async {
    repo.pending = Completer<CommentPage>();
    final pending = controller.load(refresh: true);
    expect(await controller.toggleLike(root), false);
    expect(repo.writes, 0);
    repo.pending!.complete(const CommentPage(items: [root], hasMore: false));
    await pending;
    expect(await controller.toggleLike(root), true);
    expect(state().items.single.liked, true);
  });
  testWidgets('successful send preserves a newer edited draft', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一条评论');
    repo.writePending = Completer<void>();
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '下一条草稿');
    repo.writePending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('下一条草稿'), findsOneWidget);
    expect(repo.sentText, '第一条评论');
  });
  testWidgets('emote picker replaces draft selection without sending', (
    tester,
  ) async {
    repo.emotePackages = const [
      CommentEmotePackage('小黄脸', [CommentEmote('[哭]', null)]),
      CommentEmotePackage('颜文字', [CommentEmote('[笑]', null)]),
    ];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abcd');
    final text = tester.widget<TextField>(find.byType(TextField)).controller!;
    text.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    final inputRect = tester.getRect(find.byType(TextField));
    await tester.tap(find.byTooltip('选择表情'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .getCenter(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .dx,
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
    );
    expect(tester.getRect(find.byType(TextField)), inputRect);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.text('[哭]'), findsOneWidget);
    expect(find.text('[笑]'), findsNothing);
    await tester.tap(find.text('颜文字'));
    await tester.pumpAndSettle();
    expect(find.text('[哭]'), findsNothing);
    expect(find.text('[笑]'), findsOneWidget);
    await tester.tap(find.text('[笑]'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(text.text, 'a[笑]d');
    expect(text.selection.baseOffset, 4);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('选择表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(text.text, 'a[笑]d');
  });
  testWidgets('nonzero count with empty result explains session limitation', (
    tester,
  ) async {
    repo.empty = true;
    await controller.load(sort: CommentSort.latest);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前会话未返回可展示的评论'), findsOneWidget);
    expect(find.text('还没有评论，来聊聊吧'), findsNothing);
  });
  testWidgets('nested sidebar reply retains draft on uncertain write', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IP属地：广东'), findsOneWidget);
    expect(find.text('共 3 条回复 ›'), findsOneWidget);
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('IP属地：广东'), findsOneWidget);
    expect(find.text('IP属地：上海'), findsOneWidget);
    await tester.tap(find.byTooltip('回复评论').last);
    await tester.pumpAndSettle();
    expect(find.text('回复 @乙'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留这条回复');
    repo.failure = const CommentWriteUncertain();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.text('保留这条回复'), findsOneWidget);
    expect(find.text('我已核对结果，允许再次发送'), findsOneWidget);
    await tester.tap(find.byTooltip('返回评论'));
    await tester.pumpAndSettle();
    expect(find.text('最热'), findsOneWidget);
    expect(find.text('详情'), findsNothing);
  });
  testWidgets('320 pixel panel supports double text scale without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: VideoCommentsPanel(detail: _detail),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('sidebar details return restores top comment scroll position', (
    tester,
  ) async {
    repo.items = List.generate(
      30,
      (i) => CommentEntry(
        id: '$i',
        author: '用户 $i',
        message: '评论内容 $i',
        replyCount: 3,
      ),
    );
    await controller.load(refresh: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0));
    await controller.openReplies(state().items[3]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回评论'));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, closeTo(before, 1));
  });
}

const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: '视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration.zero,
  ),
  description: '',
  parts: [],
  aid: '42',
);

class _Repo implements VideoCommentsRepository, CommentEmotesRepository {
  Completer<List<CommentEmotePackage>>? emotePending;
  RequestCancellation? emoteCancellation;
  List<CommentEmotePackage> emotePackages = const [
    CommentEmotePackage('test', [CommentEmote('[笑]', null)]),
  ];
  @override
  Future<List<CommentEmotePackage>> emotes(RequestCancellation cancellation) {
    emoteCancellation = cancellation;
    return emotePending?.future ?? Future.value(emotePackages);
  }

  List<CommentEntry> items = [root];
  int epoch = 0, writes = 0;
  bool empty = false;
  final pages = <int>[];
  CommentSort? sort;
  String? sentRoot, sentParent, sentText;
  Object? failure;
  Completer<CommentPage>? pending, replyPending;
  Completer<void>? writePending;
  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => epoch;
  @override
  Future<CommentPage> load(
    String aid,
    int page,
    CommentSort selected,
    RequestCancellation cancellation,
  ) async {
    pages.add(page);
    sort = selected;
    if (pending != null) return pending!.future;
    return CommentPage(items: empty ? [] : items, hasMore: true, totalCount: 4);
  }

  @override
  Future<CommentPage> replies(
    String aid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async => replyPending == null
      ? const CommentPage(items: [child], hasMore: false)
      : replyPending!.future;
  Future<void> write() async {
    writes++;
    final error = failure;
    if (error != null) throw error;
    if (writePending != null) await writePending!.future;
  }

  @override
  Future<void> like(
    String aid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<CommentEntry> send(
    String aid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  }) async {
    await write();
    sentRoot = rootId;
    sentParent = parentId;
    sentText = message;
    return CommentEntry(
      id: '12',
      author: '我',
      message: message,
      rootId: rootId,
      parentId: parentId,
    );
  }
}

class _Auth implements AuthRepository {
  final changesController = StreamController<AuthState>.broadcast(sync: true);
  AuthState value = const AuthState(status: AuthStatus.signedIn, mid: '7');
  void emit(AuthState state) {
    value = state;
    changesController.add(state);
  }

  @override
  AuthState get current => value;
  @override
  Stream<AuthState> get changes => changesController.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}

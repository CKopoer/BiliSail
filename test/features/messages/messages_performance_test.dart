import 'dart:ui' as ui;

import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

const _baseline = bool.fromEnvironment('MESSAGE_REBUILD_BASELINE');

void main() {
  testWidgets('unrelated message updates preserve mounted lists and rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthFake();
    addTearDown(auth.stream.close);
    final controller = _MessagesProbeController();
    final unread = _UnreadProbeController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messagesControllerProvider.overrideWith(() => controller),
          unreadMessagesProvider.overrideWith(() => unread),
        ],
        child: const MaterialApp(home: Scaffold(body: MessagesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsNWidgets(2));
    expect(find.byType(SelectableText), findsWidgets);

    final lists = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .where((state) => state.position.axis == Axis.vertical)
        .toList();
    for (final list in lists) {
      list.position.jumpTo(180);
    }
    await tester.pumpAndSettle();
    final positions = [for (final list in lists) list.position.pixels];

    Future<void> measure(String label, void Function(int) update) async {
      final counts = <String, int>{'lists': 0, 'inboxRows': 0, 'bodyRows': 0};
      debugOnRebuildDirtyWidget = (element, _) {
        final widget = element.widget;
        if (widget is ListView) counts['lists'] = counts['lists']! + 1;
        if (widget is ListTile) counts['inboxRows'] = counts['inboxRows']! + 1;
        if (widget is SelectableText) {
          counts['bodyRows'] = counts['bodyRows']! + 1;
        }
      };
      try {
        for (var index = 0; index < 10; index++) {
          update(index);
          await tester.pump();
        }
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      // Run the unchanged probe with MESSAGE_REBUILD_BASELINE before editing
      // production code; these component counts are not frame-time evidence.
      debugPrint('messages rebuild probe $label: $counts');
      if (!_baseline) expect(counts.values, everyElement(0), reason: label);
      expect(
        [for (final list in lists) list.position.pixels],
        positions,
        reason: '$label must preserve both scroll positions',
      );
    }

    await measure('unread', unread.setCount);
    await measure('sending', (index) => controller.sending(index.isEven));
    await measure(
      'markingRead',
      (index) => controller.markingRead(index.isEven),
    );

    controller.replaceBody();
    await tester.pumpAndSettle();
    expect(find.text('新的正文'), findsOneWidget);
    controller.replaceInbox();
    await tester.pumpAndSettle();
    expect(find.text('更新后的会话'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination indicators update without rebuilding existing rows', (
    tester,
  ) async {
    final auth = AuthFake();
    addTearDown(auth.stream.close);
    final controller = _MessagesProbeController(itemCount: 2);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messagesControllerProvider.overrideWith(() => controller),
          unreadMessagesProvider.overrideWith(_UnreadProbeController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: MessagesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    var listBuilds = 0, rowBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is ListView) listBuilds++;
      if (element.widget is ListTile || element.widget is SelectableText) {
        rowBuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    controller.pagination(loading: true);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(find.byTooltip('标为已读'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '标为已读',
            ),
          )
          .onPressed,
      isNull,
    );
    controller.pagination(error: '分页失败');
    await tester.pumpAndSettle();
    expect(find.text('分页失败'), findsNWidgets(2));
    expect(find.text('重试'), findsNWidgets(2));
    expect(listBuilds, 0);
    expect(rowBuilds, 0);
  });

  for (final replaceHandlers in [true, false]) {
    testWidgets(
      'retained body uses current ${replaceHandlers ? 'replacement' : 'State method'} callbacks',
      (tester) async {
        final auth = AuthFake();
        addTearDown(auth.stream.close);
        final controller = _MessagesProbeController(itemCount: 2);
        final host = GlobalKey<_CallbackHostState>();
        final calls = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              messagesControllerProvider.overrideWith(() => controller),
              unreadMessagesProvider.overrideWith(_UnreadProbeController.new),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: _CallbackHost(
                  key: host,
                  replaceHandlers: replaceHandlers,
                  calls: calls,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        controller.replaceBody(withTarget: true);
        await tester.pumpAndSettle();
        final originalBody = tester.element(find.byType(SelectableText));
        await tester.tap(find.widgetWithText(TextButton, '会话 0'));
        await tester.tap(find.text('查看分享内容'));
        expect(calls, ['user:0:2', 'target:0:/share']);
        host.currentState!.nextVersion();
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(SelectableText)), same(originalBody));
        await tester.tap(find.widgetWithText(TextButton, '会话 0'));
        await tester.tap(find.text('查看分享内容'));
        expect(calls, [
          'user:0:2',
          'target:0:/share',
          'user:1:2',
          'target:1:/share',
        ]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('closing retained private body evicts its decoded picture', (
    tester,
  ) async {
    final auth = AuthFake();
    addTearDown(auth.stream.close);
    final controller = _MessagesProbeController(itemCount: 2);
    const provider = NetworkImage('https://example.test/private.png');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final pixels = picture.toImageSync(2, 2);
    picture.dispose();
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent(
      provider,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: pixels)),
      ),
    );
    addTearDown(() => cache.evict(provider));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messagesControllerProvider.overrideWith(() => controller),
          unreadMessagesProvider.overrideWith(_UnreadProbeController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: MessagesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    controller.replaceBody(withImage: true);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(cache.containsKey(provider), isTrue);
    controller.clearConversation();
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(cache.containsKey(provider), isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _UnreadProbeController extends UnreadMessagesController {
  @override
  Future<Map<InboxSection, int>> build() async => const {};

  void setCount(int value) {
    state = AsyncData({InboxSection.private: value + 1});
  }
}

class _MessagesProbeController extends MessagesController {
  _MessagesProbeController({this.itemCount = 200});

  final int itemCount;

  @override
  MessagesState build() {
    final entries = List.generate(
      itemCount,
      (index) => InboxEntry(
        id: '1:${index + 2}',
        title: '会话 $index',
        text: '摘要 $index',
        sessionType: 1,
        userId: UserId('${index + 2}'),
      ),
    );
    return MessagesState(
      selected: entries.first,
      inbox: MessageListState(items: entries, hasMore: false),
      thread: MessageListState(
        hasMore: false,
        items: List.generate(
          itemCount,
          (index) => PrivateMessage(
            id: '$index',
            sequence: '$index',
            senderId: const UserId('2'),
            text: '正文 $index',
            type: 1,
          ),
        ),
      ),
    );
  }

  void sending(bool value) => state = state.copy(sending: value);
  void markingRead(bool value) => state = state.copy(markingRead: value);

  void replaceBody({bool withTarget = false, bool withImage = false}) {
    state = state.copy(
      thread: MessageListState(
        hasMore: false,
        items: [
          PrivateMessage(
            id: 'new',
            sequence: '201',
            senderId: UserId('2'),
            text: '新的正文',
            type: 1,
            targetUrl: withTarget ? Uri.https('example.test', '/share') : null,
            imageUrl: withImage
                ? Uri.https('example.test', '/private.png')
                : null,
          ),
        ],
      ),
    );
  }

  void pagination({bool loading = false, String? error}) {
    state = state.copy(
      inbox: MessageListState(
        items: state.inbox.items,
        loading: loading,
        error: error,
      ),
      thread: MessageListState(
        items: state.thread.items,
        loading: loading,
        error: error,
      ),
    );
  }

  void clearConversation() => state = state.copy(
    clearSelection: true,
    thread: const MessageListState(),
  );

  void replaceInbox() {
    state = state.copy(
      inbox: const MessageListState(
        hasMore: false,
        items: [InboxEntry(id: 'new', title: '更新后的会话', text: '新摘要')],
      ),
    );
  }
}

class _CallbackHost extends StatefulWidget {
  const _CallbackHost({
    super.key,
    required this.replaceHandlers,
    required this.calls,
  });

  final bool replaceHandlers;
  final List<String> calls;

  @override
  State<_CallbackHost> createState() => _CallbackHostState();
}

class _CallbackHostState extends State<_CallbackHost> {
  var _version = 0;

  void nextVersion() => setState(() => _version++);
  void _openUser(UserId id) => widget.calls.add('user:$_version:${id.value}');
  void _openTarget(Uri target) =>
      widget.calls.add('target:$_version:${target.path}');

  @override
  Widget build(BuildContext context) {
    final version = _version;
    return MessagesScreen(
      onOpenUser: widget.replaceHandlers
          ? (id) => widget.calls.add('user:$version:${id.value}')
          : _openUser,
      onOpenTarget: widget.replaceHandlers
          ? (target) => widget.calls.add('target:$version:${target.path}')
          : _openTarget,
    );
  }
}

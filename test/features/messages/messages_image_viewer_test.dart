import 'dart:async';
import 'dart:ui' as ui;

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/features/image_viewer/domain/original_image.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';
import 'message_fakes.dart';

void main() {
  final source = Uri.https('i0.hdslb.com', '/bfs/im/private.png');
  late AuthFake auth;
  late MessageRepositoryFake messages;
  late _Originals originals;

  setUp(() {
    auth = AuthFake();
    messages = MessageRepositoryFake()
      ..messages = [
        PrivateMessage(
          id: '2',
          sequence: '2',
          senderId: const UserId('2'),
          text: '[图片]',
          type: 2,
          imageUrl: source,
        ),
      ];
    originals = _Originals();
  });
  tearDown(() async => auth.stream.close());

  Future<void> openConversation(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(messages),
          originalImageRepositoryProvider.overrideWithValue(originals),
        ],
        child: const InputTestApp(home: Scaffold(body: MessagesScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留私信草稿');
    await tester.pumpAndSettle();
    expect(originals.sources, isEmpty);
  }

  Future<void> openImage(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel(RegExp('查看私信图片')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ImageViewer), findsOneWidget);
    expect(originals.sources.last, source);
  }

  void expectConversation(WidgetTester tester) {
    expect(find.byType(ImageViewer), findsNothing);
    expect(find.text('[图片]'), findsOneWidget);
    expect(find.text('保留私信草稿'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
    expect(
      container.read(messagesControllerProvider).selected?.id,
      conversation.id,
    );
    expect(messages.sends, 0);
    expect(messages.marks, 1);
    expect(tester.takeException(), isNull);
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('private image opens shared original viewer at $width', (
      tester,
    ) async {
      final image = await tester.runAsync(_originalImage);
      if (image == null) throw StateError('Original image missing');
      await openConversation(tester, width);
      await openImage(tester);
      expect(find.text('正在加载原图…'), findsOneWidget);
      expect(originals.sources, [source]);
      final viewer = tester.widget<ImageViewer>(find.byType(ImageViewer));
      expect(viewer.request.images, [source]);
      originals.pending.single.complete(image);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      await tester.tap(find.byTooltip('放大'));
      await tester.pump();
      expect(find.text('125%'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      expectConversation(tester);
    });
  }

  testWidgets(
    'closing private image cancels pending original and ignores result',
    (tester) async {
      final image = await tester.runAsync(_originalImage);
      if (image == null) throw StateError('Original image missing');
      await openConversation(tester, 390);
      await openImage(tester);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      expect(originals.reads.single.isCancelled, isTrue);
      originals.pending.single.complete(image);
      await tester.pumpAndSettle();
      expectConversation(tester);
    },
  );

  testWidgets('private image original failure retries in shared viewer', (
    tester,
  ) async {
    await openConversation(tester, 390);
    await openImage(tester);
    originals.pending.single.completeError(
      const FormatException('invalid image'),
    );
    await tester.pumpAndSettle();
    expect(find.text('原图无法读取，请重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(originals.sources, [source, source]);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(originals.reads.last.isCancelled, isTrue);
    expectConversation(tester);
  });
}

Future<OriginalImage> _originalImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(24, 16);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('PNG encoding failed');
  return OriginalImage(bytes: data.buffer.asUint8List(), width: 24, height: 16);
}

class _Originals implements OriginalImageRepository {
  final sources = <Uri>[];
  final reads = <RequestCancellation>[];
  final pending = <Completer<OriginalImage>>[];

  @override
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation) {
    sources.add(source);
    reads.add(cancellation);
    final result = Completer<OriginalImage>();
    pending.add(result);
    return result.future;
  }
}

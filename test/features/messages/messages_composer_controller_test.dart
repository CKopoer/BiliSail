import 'dart:async';
import 'dart:typed_data';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_composer.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  late _ComposeFake repo;
  late AuthFake auth;
  late ProviderContainer container;
  late MessagesController controller;
  MessagesState state() => container.read(messagesControllerProvider);
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  MessageLocalImage image() => MessageLocalImage(
    bytes: Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/png',
  );
  setUp(() async {
    repo = _ComposeFake();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(messagesControllerProvider, (_, _) {});
    controller = container.read(messagesControllerProvider.notifier);
    await flush();
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  test('image value owns immutable bytes and rejects empty, oversize or mismatched formats', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final value = MessageLocalImage(bytes: bytes, mimeType: 'image/png');
    bytes[0] = 9;
    expect(value.bytes[0], 1);
    expect(() => value.bytes[0] = 8, throwsUnsupportedError);
    expect(
      () => MessageLocalImage(bytes: Uint8List(0), mimeType: 'image/png'),
      throwsArgumentError,
    );
    expect(
      () => MessageLocalImage(
        bytes: Uint8List(MessageLocalImage.maxBytes + 1),
        mimeType: 'image/png',
      ),
      throwsArgumentError,
    );
    expect(
      () => MessageLocalImage(bytes: bytes, mimeType: 'image/webp'),
      throwsArgumentError,
    );
  });

  test('panel fallback enriches visible tokens without overriding message-specific images or recalls', () async {
    repo.messages = [
      PrivateMessage(
        id: '1',
        sequence: '1',
        senderId: const UserId('2'),
        text: '你好[doge][笑]',
        type: 1,
        emotes: {'[doge]': Uri.https('i0.hdslb.com', '/specific.png')},
      ),
      const PrivateMessage(
        id: '2',
        sequence: '2',
        senderId: UserId('2'),
        text: '消息已撤回[笑]',
        type: 5,
        kind: MessageContentKind.withdrawn,
      ),
    ];
    repo.packages = [
      MessageEmotePackage('默认', [
        MessageEmote('[doge]', Uri.https('i0.hdslb.com', '/panel.png')),
        MessageEmote('[笑]', Uri.https('i0.hdslb.com', '/smile.png')),
      ]),
    ];
    controller.selectConversation(conversation);
    await flush();
    expect(controller.supportsRichComposition, isTrue);
    expect(state().emotePackages, hasLength(1));
    expect(state().thread.items.first.emotes['[doge]']?.path, '/specific.png');
    expect(state().thread.items.first.emotes['[笑]']?.path, '/smile.png');
    expect(state().thread.items.last.emotes, isEmpty);
    await controller.loadEmotes();
    expect(repo.emoteReads, 1);
  });

  test(
    'late emote response does not replay an attempted automatic read ACK',
    () async {
      repo.emotePending = Completer<List<MessageEmotePackage>>();
      controller.selectConversation(conversation);
      await flush();
      expect(await controller.markRead(automatic: true), isTrue);
      await flush();
      expect(repo.marks, 1);
      repo.emotePending!.complete([const MessageEmotePackage('默认', [])]);
      await flush();
      expect(await controller.markRead(automatic: true), isFalse);
      expect(repo.marks, 1);
    },
  );

  test('pending panel read cancels at logout and cannot repopulate the next account', () async {
    repo.emotePending = Completer<List<MessageEmotePackage>>();
    controller.selectConversation(conversation);
    await flush();
    final cancellation = repo.emoteCancellation;
    auth.emit(const AuthState());
    await flush();
    expect(cancellation?.isCancelled, isTrue);
    repo.emotePending!.complete([const MessageEmotePackage('旧账号', [])]);
    await flush();
    expect(state().emotePackages, isEmpty);
    expect(state().emotesLoading, isFalse);
  });

  test('same-account epoch changes discard a stale panel response', () async {
    repo.emotePending = Completer<List<MessageEmotePackage>>();
    final pending = controller.loadEmotes();
    repo.sessionEpoch++;
    repo.emotePending!.complete([const MessageEmotePackage('旧会话', [])]);
    await pending;
    expect(state().emotePackages, isEmpty);
    expect(state().emotesLoading, isFalse);
  });

  test('image sending blocks duplicate and text writes while retaining the selected recipient', () async {
    controller.selectConversation(conversation);
    await flush();
    repo.imagePending = Completer<void>();
    final sending = controller.sendImage(image());
    expect(state().sending, isTrue);
    expect(await controller.sendImage(image()), isFalse);
    expect(await controller.send('不应重复发送'), isFalse);
    controller.selectConversation(otherConversation);
    await flush();
    repo.imagePending!.complete();
    expect(await sending, isTrue);
    expect(repo.imageWrites, 1);
    expect(repo.imageRecipient?.id, conversation.id);
    expect(state().selected?.id, otherConversation.id);
    expect(state().writeMessage, isNull);
  });

  test(
    'unknown image-send failure remains explicit and never retries itself',
    () async {
      controller.selectConversation(conversation);
      await flush();
      repo.imageFailure = const AppFailure(AppFailureKind.network, '断开');
      expect(await controller.sendImage(image()), isFalse);
      expect(state().sending, isFalse);
      expect(state().writeMessage, contains('操作结果尚未确认'));
      await flush();
      expect(repo.imageWrites, 1);
    },
  );

  test('logout cancels an in-flight image and ignores late success', () async {
    controller.selectConversation(conversation);
    await flush();
    repo.imagePending = Completer<void>();
    final sending = controller.sendImage(image());
    final cancellation = repo.imageCancellation;
    auth.emit(const AuthState());
    await flush();
    expect(cancellation?.isCancelled, isTrue);
    repo.imagePending!.complete();
    expect(await sending, isFalse);
    expect(state().writeMessage, isNull);
    expect(state().sending, isFalse);
  });

  test(
    'system conversations reject image sends; emote token text stays intact',
    () async {
      controller.selectConversation(
        const InboxEntry(
          id: '1:3',
          title: '系统账号',
          text: '',
          userId: UserId('3'),
          sessionType: 1,
          system: true,
        ),
      );
      await flush();
      expect(await controller.sendImage(image()), isFalse);
      expect(repo.imageWrites, 0);
      controller.selectConversation(conversation);
      await flush();
      expect(await controller.send('[doge] 你好 &+%'), isTrue);
      expect(repo.lastText, '[doge] 你好 &+%');
    },
  );
}

class _ComposeFake extends MessageRepositoryFake
    implements MessageComposeRepository {
  List<MessageEmotePackage> packages = const [];
  Completer<List<MessageEmotePackage>>? emotePending;
  Completer<void>? imagePending;
  RequestCancellation? emoteCancellation, imageCancellation;
  InboxEntry? imageRecipient;
  Object? imageFailure;
  int emoteReads = 0, imageWrites = 0;
  @override
  Future<List<MessageEmotePackage>> emotes({
    required RequestCancellation cancellation,
  }) async {
    emoteReads++;
    emoteCancellation = cancellation;
    return emotePending == null ? packages : emotePending!.future;
  }

  @override
  Future<void> sendImage(
    InboxEntry entry,
    MessageLocalImage image, {
    required RequestCancellation cancellation,
  }) async {
    imageWrites++;
    imageRecipient = entry;
    imageCancellation = cancellation;
    if (imageFailure case final error?) throw error;
    await imagePending?.future;
  }
}

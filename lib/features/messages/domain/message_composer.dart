import 'dart:typed_data';

import '../../../domain/request_cancellation.dart';
import 'message_repository.dart';

final class MessageLocalImage {
  factory MessageLocalImage({
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('图片大小须在 1 字节到 10 MiB 之间');
    }
    if (!{'image/jpeg', 'image/png', 'image/gif'}.contains(mimeType)) {
      throw ArgumentError('图片格式暂不支持');
    }
    return MessageLocalImage._(
      Uint8List.fromList(bytes).asUnmodifiableView(),
      mimeType,
    );
  }

  const MessageLocalImage._(this.bytes, this.mimeType);

  static const maxBytes = 10 * 1024 * 1024;
  final Uint8List bytes;
  final String mimeType;
}

final class MessageEmotePackage {
  const MessageEmotePackage(this.name, this.items);
  final String name;
  final List<MessageEmote> items;
}

final class MessageEmote {
  const MessageEmote(this.text, this.imageUrl);
  final String text;
  final Uri? imageUrl;
}

abstract interface class MessageComposeRepository {
  Future<List<MessageEmotePackage>> emotes({
    required RequestCancellation cancellation,
  });
  Future<void> sendImage(
    InboxEntry entry,
    MessageLocalImage image, {
    required RequestCancellation cancellation,
  });
}

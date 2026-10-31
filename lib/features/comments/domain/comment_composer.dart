import 'dart:typed_data';

import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';

final class CommentLocalImage {
  CommentLocalImage(Uint8List bytes, this.mimeType)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  static const maxBytes = 10 * 1024 * 1024;
  static const maxCount = 9;
  final Uint8List bytes;
  final String mimeType;
}

final class CommentPicture {
  const CommentPicture(this.url, this.width, this.height, this.sizeKiB);
  final Uri url;
  final int width, height;
  final double sizeKiB;
}

final class CommentMention {
  const CommentMention(this.id, this.name, {this.avatarUrl});
  final UserId id;
  final String name;
  final Uri? avatarUrl;
}

abstract interface class CommentComposerRepository {
  Future<List<CommentMention>> searchMentions(
    String keyword,
    RequestCancellation cancellation,
  );
  Future<CommentPicture> uploadPicture(
    CommentLocalImage image,
    RequestCancellation cancellation,
  );
}

import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/comment_target.dart';
import '../../../domain/dynamic_post.dart' show DynamicPost;
import 'dynamic_composer_repository.dart';
import 'dynamic_draft.dart';

final class DynamicInteractionSettings {
  const DynamicInteractionSettings({
    required this.canSelect,
    required this.selected,
    required this.canComment,
    required this.comments,
  });
  final bool canSelect, selected, canComment, comments;
}

final class DynamicEditDraft {
  const DynamicEditDraft({
    required this.id,
    required this.authorId,
    required this.text,
    required this.title,
    required this.spans,
    required this.pictures,
    this.topic,
    this.options = const DynamicPublishOptions(),
    this.repostId,
    this.reserveId,
  });
  final String id, authorId, title, text;
  final List<DynamicTextSpan> spans;
  final List<DynamicPicture> pictures;
  final DynamicComposeTopic? topic;
  final DynamicPublishOptions options;
  final String? repostId, reserveId;
}

abstract interface class DynamicManagementRepository {
  Future<void> remove(String id, RequestCancellation cancellation);
  Future<void> pin(String id, bool pinned, RequestCancellation cancellation);
  Future<void> visibility(
    String id,
    bool onlySelf,
    RequestCancellation cancellation,
  );
  Future<void> report(
    String id,
    UserId author,
    int reason,
    String description,
    RequestCancellation cancellation,
  );
  Future<bool> publicVisible(String id, RequestCancellation cancellation);
  Future<DynamicInteractionSettings> interaction(
    CommentTarget target,
    RequestCancellation cancellation,
  );
  Future<void> setInteraction(
    CommentTarget target,
    int action,
    RequestCancellation cancellation,
  );
  Future<DynamicEditDraft> editDraft(
    String id,
    RequestCancellation cancellation,
  );
  Future<void> shareMessage(
    DynamicPost post,
    UserId receiver,
    RequestCancellation cancellation,
  );
}

abstract interface class DynamicEditRepository {
  Future<void> edit({
    required String mid,
    required String id,
    required String title,
    required String text,
    required List<DynamicTextSpan> spans,
    required List<DynamicPicture> pictures,
    DynamicComposeTopic? topic,
    required DynamicPublishOptions options,
    String? repostId,
    String? reserveId,
    required RequestCancellation cancellation,
  });
}

import 'dynamic_composer_models.dart';

final class ApiDynamicInteraction {
  const ApiDynamicInteraction({
    required this.canSelect,
    required this.selected,
    required this.canComment,
    required this.comments,
  });
  final bool canSelect, selected, canComment, comments;
}

final class ApiDynamicEditDraft {
  const ApiDynamicEditDraft({
    required this.id,
    required this.authorId,
    required this.title,
    required this.contents,
    required this.pictures,
    this.topic,
    this.repostId,
    this.reserveId,
    this.onlySelf = false,
    this.replyPolicy = 0,
  });
  final String id, authorId, title;
  final List<ApiDynamicContent> contents;
  final List<ApiDynamicPicture> pictures;
  final ApiDynamicComposeTopic? topic;
  final String? repostId, reserveId;
  final bool onlySelf;
  final int replyPolicy;
}

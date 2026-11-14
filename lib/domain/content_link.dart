/// A comment address, distinct from the notification's own identifier.
final class CommentLocation {
  const CommentLocation(this.rootId, {this.replyId});
  final String rootId;
  final String? replyId;
  String get focusId => replyId ?? rootId;
  @override
  bool operator ==(Object other) =>
      other is CommentLocation &&
      rootId == other.rootId &&
      replyId == other.replyId;
  @override
  int get hashCode => Object.hash(rootId, replyId);
}

/// Validated navigation intent passed to retained content and playback views.
final class ContentLink {
  const ContentLink({this.comment, this.position, this.page, this.requestId});
  final CommentLocation? comment;
  final Duration? position;
  final int? page;
  final String? requestId;

  factory ContentLink.fromUri(Uri uri) {
    final query = uri.queryParameters;
    String? id(String? value) =>
        value != null && RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(value)
        ? value
        : null;
    final root = id(query['comment_root_id']);
    final secondary = id(query['comment_secondary_id']);
    final milliseconds = int.tryParse(query['start_progress'] ?? '');
    final part = int.tryParse(query['p'] ?? '');
    return ContentLink(
      requestId: id(query['message_request']),
      comment: root == null ? null : CommentLocation(root, replyId: secondary),
      position:
          milliseconds != null &&
              milliseconds >= 0 &&
              milliseconds <= const Duration(days: 7).inMilliseconds
          ? Duration(milliseconds: milliseconds)
          : null,
      page: part != null && part > 0 && part <= 10000 ? part : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContentLink &&
      comment == other.comment &&
      position == other.position &&
      page == other.page &&
      requestId == other.requestId;
  @override
  int get hashCode => Object.hash(comment, position, page, requestId);
}

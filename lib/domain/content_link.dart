/// A comment address, distinct from the notification's own identifier.
final class CommentLocation {
  const CommentLocation(this.rootId, {this.replyId});
  final String rootId;
  final String? replyId;
  String get focusId => replyId ?? rootId;

  static CommentLocation? fromWebUri(Uri uri) {
    final query = uri.queryParameters;
    final root =
        _id(query['comment_root_id']) ??
        _id(query['root']) ??
        _id(query['rpid']) ??
        _id(RegExp(r'^reply([1-9][0-9]*)$').firstMatch(uri.fragment)?[1]);
    return root == null
        ? null
        : CommentLocation(root, replyId: _id(query['comment_secondary_id']));
  }

  Map<String, String> get queryParameters => {
    'comment_root_id': rootId,
    'comment_secondary_id': ?replyId,
  };

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
    final root = _id(query['comment_root_id']);
    final secondary = _id(query['comment_secondary_id']);
    final milliseconds = int.tryParse(query['start_progress'] ?? '');
    final part = int.tryParse(query['p'] ?? '');
    return ContentLink(
      requestId: _id(query['message_request']),
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

String? _id(String? value) =>
    value != null && RegExp(r'^[1-9][0-9]{0,29}$').hasMatch(value)
    ? value
    : null;

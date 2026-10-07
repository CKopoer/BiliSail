enum CommentTargetType {
  video(1),
  album(11),
  article(12),
  music(14),
  dynamic(17),
  course(33);

  const CommentTargetType(this.value);
  final int value;
}

/// The server's comment identity differs from the dynamic's share/like ID.
final class CommentTarget {
  const CommentTarget(this.oid, this.type);
  final String oid;
  final CommentTargetType type;

  @override
  bool operator ==(Object other) =>
      other is CommentTarget && oid == other.oid && type == other.type;
  @override
  int get hashCode => Object.hash(oid, type);
}

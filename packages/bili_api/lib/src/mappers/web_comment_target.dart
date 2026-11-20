const supportedWebCommentTypes = {1, 11, 12, 14, 17, 33};

({String oid, int type})? parseWebCommentTarget(Map<String, Object?> basic) {
  final oid = switch (basic['comment_id_str']) {
    final String value => value,
    final int value => '$value',
    _ => '',
  };
  final type = switch (basic['comment_type']) {
    final int value => value,
    final String value => int.tryParse(value),
    _ => null,
  };
  return type != null &&
          supportedWebCommentTypes.contains(type) &&
          RegExp(r'^[1-9][0-9]{0,127}$').hasMatch(oid)
      ? (oid: oid, type: type)
      : null;
}

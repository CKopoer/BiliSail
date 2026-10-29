import '../models.dart';

/// UGC and PGC use the same three DASH audio locations.
List<Map<String, Object?>> dashAudioEntries(
  Map<String, Object?> dash,
  String endpoint,
) {
  List<Object?> list(Object? value) => value == null
      ? const []
      : value is List<Object?>
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  Map<String, Object?>? map(Object? value) => value == null
      ? null
      : value is Map<String, Object?>
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  final flac = map(dash['flac']);
  final dolby = map(dash['dolby']);
  return [
    for (final entry in list(dash['audio']).take(64)) ?map(entry),
    ?map(flac?['audio']),
    for (final entry in list(dolby?['audio']).take(64)) ?map(entry),
  ];
}

import '../../../domain/request_cancellation.dart';

typedef FavoriteFolderTarget = ({String id, String scope});

final class FavoriteFolderInfo {
  const FavoriteFolderInfo({
    required this.id,
    required this.title,
    required this.intro,
    required this.isPrivate,
  });
  final String id, title, intro;
  final bool isPrivate;
}

final class FavoriteFolderEdit {
  const FavoriteFolderEdit({
    required this.title,
    required this.intro,
    required this.isPrivate,
  });
  final String title, intro;
  final bool isPrivate;

  bool matches(FavoriteFolderInfo info) =>
      title == info.title && intro == info.intro && isPrivate == info.isPrivate;
}

/// A lost response does not prove failure. A subsequent read must reconcile it
/// before another explicit save may be submitted.
final class FavoriteFolderWriteUncertain implements Exception {
  const FavoriteFolderWriteUncertain();
}

abstract interface class FavoriteFolderRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<FavoriteFolderInfo> load(
    FavoriteFolderTarget target,
    RequestCancellation cancellation,
  );
  Future<void> update(
    FavoriteFolderTarget target,
    FavoriteFolderEdit edit,
    RequestCancellation cancellation,
  );
}

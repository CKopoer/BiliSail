import '../api_client.dart';
import '../models.dart';

final class ApiFavoriteFolderInfo {
  const ApiFavoriteFolderInfo({
    required this.id,
    required this.ownerMid,
    required this.title,
    required this.intro,
    required this.isPrivate,
  });
  final String id, ownerMid, title, intro;
  final bool isPrivate;
}

/// Folder metadata uses the existing Web resource read; mutations are single
/// Cookie/CSRF form submissions. Text stays raw until the transport encodes it.
final class FavoriteFolderClient {
  const FavoriteFolderClient(this.api);
  final BiliApiClient api;

  Future<ApiFavoriteFolderInfo> load(
    String id, {
    ApiRequestContext? context,
  }) async {
    _validateId(id);
    const endpoint = 'favorite_folder_info';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/v3/fav/resource/list', {
        'media_id': id,
        'pn': '1',
        'ps': '1',
        'platform': 'web',
      }),
      endpoint,
      context: context,
    );
    final info = data['info'];
    if (info is! Map<String, Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final upper = info['upper'];
    final title = info['title'];
    final intro = info['intro'];
    final attr = info['attr'];
    if (_id(info['id']) != id ||
        upper is! Map<String, Object?> ||
        _id(upper['mid']) == null ||
        title is! String ||
        title.trim().isEmpty ||
        intro is! String ||
        attr is! int ||
        attr < 0) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiFavoriteFolderInfo(
      id: id,
      ownerMid:
          _id(upper['mid']) ??
          (throw const ApiFailure(ApiFailureCategory.protocol, endpoint)),
      title: title,
      intro: intro,
      isPrivate: (attr & 2) != 0,
    );
  }

  Future<void> update(
    String id, {
    required String title,
    required String intro,
    required bool isPrivate,
    ApiRequestContext? context,
  }) async {
    _validateId(id);
    if (title.trim().isEmpty) throw ArgumentError.value(title, 'title');
    await api.submitForm('/x/v3/fav/folder/edit', 'favorite_folder_edit', {
      'media_id': id,
      'title': title,
      'intro': intro,
      'privacy': isPrivate ? '1' : '0',
    }, context: context);
  }

  static String? _id(Object? value) {
    final text = value is int
        ? '$value'
        : value is String
        ? value
        : null;
    return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  static void _validateId(String id) {
    if (_id(id) == null) throw ArgumentError.value(id, 'id');
  }
}

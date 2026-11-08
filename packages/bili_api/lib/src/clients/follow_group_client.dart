import '../api_client.dart';
import '../models.dart';

final class ApiFollowGroup {
  const ApiFollowGroup({required this.id, required this.name});

  final String id;
  final String name;
}

/// Web Cookie relation groups; IDs remain decimal strings across the API edge.
final class FollowGroupClient {
  const FollowGroupClient(this.api);

  final BiliApiClient api;

  Future<ApiFollowGroup> create(
    String name, {
    ApiRequestContext? context,
  }) async {
    const endpoint = 'follow_group_create';
    final normalized = _name(name);
    final data = await api.submitForm('/x/relation/tag/create', endpoint, {
      'tag': normalized,
    }, context: context);
    final id = data is Map<String, Object?> ? _id(data['tagid']) : null;
    if (id == null || !RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    return ApiFollowGroup(id: id, name: normalized);
  }

  Future<void> rename(
    String id,
    String name, {
    ApiRequestContext? context,
  }) async {
    _editable(id);
    await api.submitForm('/x/relation/tag/update', 'follow_group_rename', {
      'tagid': id,
      'name': _name(name),
    }, context: context);
  }

  Future<void> delete(String id, {ApiRequestContext? context}) async {
    _editable(id);
    await api.submitForm('/x/relation/tag/del', 'follow_group_delete', {
      'tagid': id,
    }, context: context);
  }

  Future<void> sort(List<String> ids, {ApiRequestContext? context}) async {
    if (ids.isEmpty || ids.length > 100 || ids.toSet().length != ids.length) {
      throw ArgumentError('Invalid follow groups');
    }
    for (final id in ids) {
      _editable(id);
    }
    await api.submitForm('/x/relation/tags/update_sort', 'follow_group_sort', {
      'tagids': ids.join(','),
    }, context: context);
  }

  static String _name(String name) {
    final value = name.trim();
    if (value.isEmpty || value.runes.length > 16) {
      throw ArgumentError('Invalid follow group name');
    }
    return value;
  }

  static void _editable(String id) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(id)) {
      throw ArgumentError('Reserved or invalid follow group');
    }
  }

  Future<List<ApiFollowGroup>> groups({
    bool includeReserved = false,
    ApiRequestContext? context,
  }) async {
    const endpoint = 'follow_groups';
    final value = await api.requestValue(
      Uri.https('api.bilibili.com', '/x/relation/tags'),
      endpoint,
      context: context,
    );
    if (value is! List<Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final groups = <ApiFollowGroup>[];
    final seen = <String>{};
    for (final entry in value.take(100)) {
      if (entry is! Map<String, Object?>) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      final id = _id(entry['tagid']);
      final name = entry['name'];
      if (id == null || name is! String || name.trim().isEmpty) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      // Reserved negative relation tags are not editable in this picker.
      if ((includeReserved || !id.startsWith('-')) && seen.add(id)) {
        groups.add(ApiFollowGroup(id: id, name: name));
      }
    }
    return List.unmodifiable(groups);
  }

  Future<Set<String>> membership(
    String mid, {
    ApiRequestContext? context,
  }) async {
    _validateMid(mid);
    const endpoint = 'follow_group_user';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/relation/tag/user', {'fid': mid}),
      endpoint,
      context: context,
    );
    final ids = <String>{};
    for (final id in data.keys) {
      if (_id(id) == null) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      ids.add(id);
    }
    return Set.unmodifiable(ids);
  }

  Future<void> save(
    String mid,
    Set<String> groupIds, {
    ApiRequestContext? context,
  }) async {
    _validateMid(mid);
    for (final id in groupIds) {
      if (_id(id) == null) throw ArgumentError('Invalid group ID');
    }
    await api.submitForm('/x/relation/tags/addUsers', 'follow_group_save', {
      'fids': mid,
      'tagids': groupIds.isEmpty ? '0' : groupIds.join(','),
    }, context: context);
  }

  static String? _id(Object? value) {
    final text = switch (value) {
      int number => '$number',
      String text => text,
      _ => null,
    };
    return text != null && RegExp(r'^-?(0|[1-9]\d*)$').hasMatch(text)
        ? text
        : null;
  }

  static void _validateMid(String mid) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(mid)) {
      throw ArgumentError('Invalid author ID');
    }
  }
}

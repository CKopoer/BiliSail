import '../api_client.dart';
import '../models.dart';
import '../models/dynamic_poll_models.dart';

final class DynamicPollClient {
  const DynamicPollClient(this.api);
  final BiliApiClient api;

  Future<List<ApiDynamicPollFollowee>> followees(
    String id, {
    ApiRequestContext? context,
  }) async {
    _requireId(id);
    const endpoint = 'dynamic_poll_followees';
    final data = await api.requestJson(
      Uri.https('api.vc.bilibili.com', '/vote_svr/v1/vote_svr/followee_votes', {
        'vote_id': id,
      }),
      endpoint,
      context: context,
    );
    final rows = data['votes'];
    if (rows == null) return const [];
    if (rows is! List<Object?>) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final result = <ApiDynamicPollFollowee>[];
    for (final row in rows.take(100)) {
      if (row is! Map<String, Object?> ||
          _id(row['uid']) == null ||
          row['name'] is! String) {
        continue;
      }
      final votes = row['votes'];
      if (votes is! List<Object?> ||
          votes.length > 20 ||
          votes.any((v) => _number(v) == null)) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      final name = row['name'] as String;
      result.add(
        ApiDynamicPollFollowee(
          _id(row['uid'])!,
          name.substring(0, name.length.clamp(0, 100)),
          List.unmodifiable(votes.map((v) => _number(v)!)),
          _image(row['face']),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<ApiDynamicPoll> detail(String id, {ApiRequestContext? context}) async {
    _requireId(id);
    const endpoint = 'dynamic_poll_detail';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/vote/vote_info', {'vote_id': id}),
      endpoint,
      context: context,
    );
    return _parse(data, id, endpoint, separatedVotes: true);
  }

  Future<ApiDynamicPoll> vote({
    required String id,
    required String voterId,
    required List<int> choices,
    required bool anonymous,
    String? dynamicId,
    ApiRequestContext? context,
  }) async {
    _requireId(id);
    _requireId(voterId);
    if (dynamicId != null) _requireId(dynamicId);
    if (choices.isEmpty ||
        choices.length > 20 ||
        choices.toSet().length != choices.length ||
        choices.any((index) => index < 0 || index > 0x7fffffff)) {
      throw ArgumentError('Invalid poll choices');
    }
    const endpoint = 'dynamic_poll_vote';
    final data = await api.submitDynamicJson('/x/vote/do_vote', endpoint, {
      'vote_id': _wireId(id),
      'voter_uid': _wireId(voterId),
      'votes': choices,
      'status': anonymous ? 1 : 0,
      'op_bit': 0,
      'dynamic_id': dynamicId == null ? 0 : _wireId(dynamicId),
    }, context: context);
    return _parse(
      data,
      id,
      endpoint,
      separatedVotes: false,
      submittedChoices: choices,
    );
  }
}

void _requireId(String id) {
  if (id.length > 128 || !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
    throw ArgumentError('Invalid poll identity');
  }
}

// JSON integer fields are encoded from Dart ints, never through floating point.
int _wireId(String id) {
  final number = int.tryParse(id);
  if (number == null || number <= 0) {
    throw ArgumentError('Invalid poll identity');
  }
  return number;
}

ApiDynamicPoll _parse(
  Object? data,
  String id,
  String endpoint, {
  required bool separatedVotes,
  List<int>? submittedChoices,
}) {
  Never invalid() => throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  if (data is! Map<String, Object?>) invalid();
  final info = data['vote_info'];
  if (info is! Map<String, Object?> || _id(info['vote_id']) != id) invalid();
  final rawOptions = info['options'];
  if (rawOptions is! List<Object?> ||
      rawOptions.length < 2 ||
      rawOptions.length > 20) {
    invalid();
  }
  final options = <ApiDynamicPollOptionResult>[];
  final indices = <int>{};
  for (final raw in rawOptions) {
    if (raw is! Map<String, Object?>) invalid();
    final index = _number(raw['opt_idx']);
    final count = _number(raw['cnt'] ?? 0);
    final text = raw['opt_desc'];
    if (index == null ||
        index > 0x7fffffff ||
        !indices.add(index) ||
        count == null ||
        text is! String ||
        text.isEmpty ||
        text.length > 4096) {
      invalid();
    }
    options.add(
      ApiDynamicPollOptionResult(
        index: index,
        text: text,
        count: count,
        imageUrl: _image(raw['img_url']),
      ),
    );
  }
  final title = info['title'];
  final description = info['desc'] ?? '';
  final maxChoices = _number(info['choice_cnt']);
  final endTime = _number(info['end_time']);
  final joinCount = _number(info['join_num'] ?? 0);
  final rawVotes = separatedVotes
      ? data['my_votes']
      : info['my_votes'] ?? submittedChoices;
  if (title is! String ||
      title.isEmpty ||
      title.length > 4096 ||
      description is! String ||
      description.length > 32768 ||
      maxChoices == null ||
      maxChoices < 1 ||
      maxChoices > options.length ||
      endTime == null ||
      endTime == 0 ||
      endTime > 8640000000000 ||
      joinCount == null ||
      (rawVotes != null && rawVotes is! List<Object?>)) {
    invalid();
  }
  final myVotes = <int>{};
  if (rawVotes is List<Object?>) {
    if (rawVotes.length > maxChoices) invalid();
    for (final value in rawVotes) {
      final index = _number(value);
      if (index == null || !indices.contains(index) || !myVotes.add(index)) {
        invalid();
      }
    }
  }
  if (submittedChoices != null && myVotes.isEmpty) invalid();
  return ApiDynamicPoll(
    id: id,
    title: title,
    description: description,
    maxChoices: maxChoices,
    endsAt: DateTime.fromMillisecondsSinceEpoch(endTime * 1000),
    joinCount: joinCount,
    options: options,
    myVotes: myVotes,
    authorId: _id(info['vote_publisher'] ?? info['uid']),
  );
}

String? _id(Object? value) {
  final id = value is int ? '$value' : value;
  return id is String &&
          id.length <= 128 &&
          RegExp(r'^[1-9][0-9]*$').hasMatch(id)
      ? id
      : null;
}

int? _number(Object? value) {
  final number = value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  return number != null && number >= 0 ? number : null;
}

Uri? _image(Object? value) {
  if (value is! String || value.isEmpty || value.length > 8192) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  return uri != null &&
          {'https', 'http'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? uri
      : null;
}

import 'dart:convert';
import '../models.dart';
import '../models/dynamic_models.dart';

/// Web dynamic responses are bounded before entering application state.
ApiDynamicPost parseDynamicPost(
  Map<String, Object?> item,
  String endpoint, {
  int depth = 0,
}) {
  final id = _id(item['id_str']);
  if (id == null) throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  if (item['modules'] is! Map<String, Object?> &&
      item['type'] != 'DYNAMIC_TYPE_NONE') {
    throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  final modules = _map(item['modules']);
  final author = _map(modules['module_author']);
  final content = _map(modules['module_dynamic']);
  final major = _map(content['major']);
  final opus = _map(major['opus']);
  final desc = _map(content['desc']);
  // Web desc can be a nonempty placeholder while opus carries the body.
  final summary = _hasReadableBody(desc) ? desc : _map(opus['summary']);
  final spans = <ApiDynamicTextSpan>[];
  var remaining = 32768;
  for (final raw in _list(summary['rich_text_nodes']).take(256)) {
    final node = _map(raw);
    final emoji = _map(node['emoji']);
    var text = _text(node['text'], fallback: _text(emoji['text']));
    if (text.length > remaining) text = text.substring(0, remaining);
    remaining -= text.length;
    final type = _text(node['type']);
    final image = _uri(emoji['icon_url']);
    if (text.isEmpty && image == null) continue;
    final kind = switch (type) {
      'RICH_TEXT_NODE_TYPE_EMOJI' when image != null =>
        ApiDynamicTextKind.emoji,
      'RICH_TEXT_NODE_TYPE_AT' => ApiDynamicTextKind.mention,
      'RICH_TEXT_NODE_TYPE_TOPIC' => ApiDynamicTextKind.topic,
      'RICH_TEXT_NODE_TYPE_WEB' => ApiDynamicTextKind.link,
      _ => ApiDynamicTextKind.plain,
    };
    spans.add(
      ApiDynamicTextSpan(
        kind: kind,
        text: text,
        imageUrl: kind == ApiDynamicTextKind.emoji ? image : null,
        linkUrl: _uri(node['jump_url']),
        userId: kind == ApiDynamicTextKind.mention ? _id(node['rid']) : null,
        emojiSize: emoji['size'] == 2 ? 2 : 1,
      ),
    );
    if (remaining <= 0) break;
  }
  final archive = _map(major['archive']);
  final bvid = _text(archive['bvid']);
  final stat = _map(archive['stat']);
  final video = RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)
      ? ApiVideoSummary(
          bvid: bvid,
          title: _text(archive['title']),
          coverUrl: _uri(archive['cover']),
          ownerName: _text(author['name']),
          ownerMid: _id(author['mid']),
          ownerAvatarUrl: _uri(author['face']),
          duration: _duration(archive['duration_text']),
          playCount: _number(stat['play']),
          danmakuCount: _number(stat['danmaku']),
          publishedAt: _date(author['pub_ts']),
        )
      : null;
  final images = <Uri>[];
  final imageAspectRatios = <Uri, double>{};
  for (final raw in _list(
    _map(major['draw'])['items'] ?? opus['pics'],
  ).take(9)) {
    final image = _map(raw);
    final uri = _uri(image['src'] ?? image['url']);
    if (uri != null) {
      images.add(uri);
      final width = _positiveDimension(image['width']);
      final height = _positiveDimension(image['height']);
      if (width != null && height != null) {
        final ratio = width / height;
        if (ratio.isFinite && ratio > 0) imageAspectRatios[uri] = ratio;
      }
    }
  }
  final type = _text(item['type']);
  // Web union members are commonly present with null values. Their presence
  // alone must not turn an archive, draw or opus into a deleted dynamic.
  final none = _map(major['none']);
  final unavailable =
      type == 'DYNAMIC_TYPE_NONE' ||
      major['type'] == 'MAJOR_TYPE_NONE' ||
      none.isNotEmpty;
  final article = _map(major['article']);
  final common = _map(major['common']);
  final live = _map(major['live']).isNotEmpty
      ? _map(major['live'])
      : _liveRecommendation(major['live_rcmd']);
  final link = article.isNotEmpty
      ? article
      : common.isNotEmpty
      ? common
      : live;
  final counts = _map(modules['module_stat']);
  final original = _map(item['orig']);
  final basic = _map(item['basic']);
  final (commentOid, commentType) = _commentTarget(id, type, basic, major);
  final like = _map(counts['like']);
  return ApiDynamicPost(
    id: id,
    title: _text(opus['title']),
    authorName: _text(author['name']),
    authorId: _id(author['mid']),
    authorAvatarUrl: _uri(author['face']),
    publishedAt: _date(author['pub_ts']),
    publishText: _text(author['pub_time']),
    actionText: _text(author['pub_action']),
    text: unavailable
        ? _text(_map(major['none'])['tips'], fallback: '该动态已删除或不可见')
        : spans.isNotEmpty
        ? spans.map((s) => s.text).join()
        : _text(
            summary['text'] ?? link['desc'],
            fallback:
                video == null &&
                    images.isEmpty &&
                    link.isEmpty &&
                    original.isEmpty
                ? '暂不支持该动态内容，请在官方页面查看'
                : '',
          ),
    spans: spans,
    imageUrls: images,
    imageAspectRatios: imageAspectRatios,
    video: video,
    original: original.isEmpty
        ? null
        : depth >= 2 || _id(original['id_str']) == null
        ? ApiDynamicPost(
            id: id,
            text: '原动态已删除或暂不支持，请在官方动态查看',
            unavailable: true,
            linkUrl: Uri.https('t.bilibili.com', '/$id'),
          )
        : parseDynamicPost(original, endpoint, depth: depth + 1),
    repostCount: _number(_map(counts['forward'])['count']),
    commentCount: _number(_map(counts['comment'])['count']),
    likeCount: _number(_map(counts['like'])['count']),
    typeLabel: switch (type) {
      'DYNAMIC_TYPE_ARTICLE' => '专栏',
      'DYNAMIC_TYPE_LIVE_RCMD' || 'DYNAMIC_TYPE_LIVE' => '直播',
      'DYNAMIC_TYPE_FORWARD' => '转发',
      _ => '',
    },
    linkTitle: _text(link['title']),
    linkDescription: _text(link['desc']),
    linkCoverUrl: _uri(link['cover'] ?? (_list(article['covers']).firstOrNull)),
    linkUrl:
        _officialUri(link['jump_url']) ?? Uri.https('t.bilibili.com', '/$id'),
    commentOid: unavailable ? null : commentOid,
    commentType: unavailable ? null : commentType,
    liked: like['status'] == true || like['status'] == 1,
    commentForbidden: _map(counts['comment'])['forbidden'] == true,
    repostForbidden: _map(counts['forward'])['forbidden'] == true,
    likeForbidden: like['forbidden'] == true,
    unavailable: unavailable,
  );
}

double? _positiveDimension(Object? value) {
  final dimension = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  return dimension != null && dimension.isFinite && dimension > 0
      ? dimension
      : null;
}

Map<String, Object?> _map(Object? v) =>
    v is Map<String, Object?> ? v : const {};
List<Object?> _list(Object? v) => v is List<Object?> ? v : const [];
String _text(Object? v, {String fallback = ''}) {
  if (v is! String || v.isEmpty) return fallback;
  return v.length > 32768 ? v.substring(0, 32768) : v;
}

String? _id(Object? v) {
  final s = v is int
      ? '$v'
      : v is String
      ? v
      : '';
  return s.length <= 128 && RegExp(r'^[1-9][0-9]*$').hasMatch(s) ? s : null;
}

Uri? _uri(Object? v) {
  if (v is! String || v.length > 8192) return null;
  final u = Uri.tryParse(v.startsWith('//') ? 'https:$v' : v);
  return u != null &&
          const ['http', 'https'].contains(u.scheme) &&
          u.host.isNotEmpty &&
          u.userInfo.isEmpty
      ? u.replace(scheme: 'https')
      : null;
}

int? _number(Object? v) {
  final n = v is int
      ? v
      : v is String
      ? int.tryParse(v)
      : null;
  if (n != null) return n >= 0 ? n : null;
  if (v is String && v.length < 32) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)(万|亿)$').firstMatch(v);
    if (m != null) {
      return ((double.tryParse(m[1] ?? '') ?? 0) *
              (m[2] == '万' ? 10000 : 100000000))
          .round();
    }
  }
  return null;
}

DateTime? _date(Object? v) {
  final n = _number(v);
  return n == null || n > 253402300799
      ? null
      : DateTime.fromMillisecondsSinceEpoch(n * 1000);
}

Duration _duration(Object? v) {
  final parts = _text(v).split(':');
  var seconds = 0;
  for (final p in parts.take(3)) {
    seconds = seconds * 60 + (int.tryParse(p) ?? 0);
  }
  return Duration(seconds: seconds.clamp(0, 604800));
}

Uri? _officialUri(Object? v) {
  final uri = _uri(v);
  return uri != null &&
          uri.port == 443 &&
          const [
            'www.bilibili.com',
            'live.bilibili.com',
            't.bilibili.com',
          ].contains(uri.host)
      ? uri
      : null;
}

Map<String, Object?> _liveRecommendation(Object? v) {
  final content = _map(v)['content'];
  if (content is! String || content.length > 65536) return const {};
  try {
    final root = _map(jsonDecode(content));
    final info = _map(root['live_play_info']);
    final roomId = _id(info['room_id']);
    return {
      ...info,
      'jump_url': roomId == null ? null : 'https://live.bilibili.com/$roomId',
    };
  } on FormatException {
    return const {};
  }
}

bool _hasReadableBody(Map<String, Object?> body) {
  if (_text(body['text']).trim().isNotEmpty) return true;
  return _list(body['rich_text_nodes']).take(256).any((raw) {
    final node = _map(raw);
    final emoji = _map(node['emoji']);
    return _text(node['text'], fallback: _text(emoji['text'])).isNotEmpty ||
        node['type'] == 'RICH_TEXT_NODE_TYPE_EMOJI' &&
            _uri(emoji['icon_url']) != null;
  });
}

(String?, int?) _commentTarget(
  String id,
  String type,
  Map<String, Object?> basic,
  Map<String, Object?> major,
) {
  if (basic.containsKey('comment_id_str') ||
      basic.containsKey('comment_type')) {
    final oid = _id(basic['comment_id_str']);
    final value = _number(basic['comment_type']);
    return oid != null && const {1, 11, 12, 14, 17, 33}.contains(value)
        ? (oid, value)
        : (null, null);
  }
  final rid = _id(basic['rid_str']);
  return switch (type) {
    'DYNAMIC_TYPE_WORD' ||
    'DYNAMIC_TYPE_FORWARD' ||
    'DYNAMIC_TYPE_LIVE' ||
    'DYNAMIC_TYPE_LIVE_RCMD' => (id, 17),
    'DYNAMIC_TYPE_AV' => (_id(_map(major['archive'])['aid']) ?? rid, 1),
    'DYNAMIC_TYPE_PGC' => (_id(_map(major['pgc'])['aid']) ?? rid, 1),
    'DYNAMIC_TYPE_DRAW' => (_id(_map(major['draw'])['id']) ?? rid, 11),
    'DYNAMIC_TYPE_ARTICLE' => (_id(_map(major['article'])['id']) ?? rid, 12),
    'DYNAMIC_TYPE_MUSIC' => (_id(_map(major['music'])['id']) ?? rid, 14),
    _ => (null, null),
  };
}

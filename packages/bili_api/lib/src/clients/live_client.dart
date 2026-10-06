import 'dart:async';

import '../api_client.dart';
import '../live/live_chat_session.dart';
import '../live/live_message_content.dart';
import '../models.dart';
import '../models/live_models.dart';

/// Web live room, media, chat reads and explicit Cookie/CSRF danmaku writes.
final class LiveClient {
  LiveClient(this.api);
  final BiliApiClient api;
  Future<String>? _deviceInFlight;

  Future<List<ApiLiveEmoticonPackage>> getEmoticons(
    String roomId, {
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    const endpoint = 'live_emoticons';
    final data = await api.requestJson(
      Uri.https(
        'api.live.bilibili.com',
        '/xlive/web-ucenter/v2/emoticon/GetEmoticons',
        {'platform': 'pc', 'room_id': roomId},
      ),
      endpoint,
      context: context,
    );
    final packages = <ApiLiveEmoticonPackage>[];
    var remaining = 500;
    for (final raw in _list(data['data'], endpoint).take(30)) {
      final entry = _map(raw, endpoint);
      final items = <ApiLiveEmoticon>[];
      for (final rawItem in _list(
        entry['emoticons'] ?? const [],
        endpoint,
      ).take(remaining)) {
        final item = _map(rawItem, endpoint);
        final unique = _text(item['emoticon_unique']) ?? '';
        final text = _text(item['emoji']) ?? _text(item['descript']) ?? '';
        final sticker = (_int(item['width']) ?? 0) > 0;
        if (text.isEmpty ||
            text.length > 100 ||
            unique.length > 200 ||
            (sticker && unique.isEmpty)) {
          continue;
        }
        items.add(
          ApiLiveEmoticon(
            unique: unique,
            text: text,
            imageUrl: _imageUri(item['url']),
            isSticker: sticker,
            allowed: _int(item['perm']) == 1,
            unlockHint: _text(item['unlock_show_text']) ?? '',
          ),
        );
      }
      remaining -= items.length;
      if (items.isNotEmpty) {
        packages.add(
          ApiLiveEmoticonPackage(_text(entry['pkg_name']) ?? '表情', items),
        );
      }
      if (remaining <= 0) break;
    }
    return List.unmodifiable(packages);
  }

  Future<void> sendDanmaku(
    String roomId,
    String message, {
    String? emoticonUnique,
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    if (message.trim().isEmpty ||
        message.runes.length > 100 ||
        (emoticonUnique != null &&
            (emoticonUnique.isEmpty || emoticonUnique.length > 200))) {
      throw ArgumentError('Invalid live danmaku');
    }
    try {
      await api.submitLiveForm('/msg/send', 'live_danmaku_send', {
        'roomid': roomId,
        'msg': emoticonUnique ?? message,
        'dm_type': emoticonUnique == null ? '0' : '1',
        'rnd': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
        'fontsize': '25',
        'color': '16777215',
        'mode': '1',
        'bubble': '0',
      }, context: context);
    } on ApiFailure catch (error) {
      if (error.businessCode == 10031) {
        throw ApiFailure(
          ApiFailureCategory.rateLimited,
          error.endpointId,
          businessCode: error.businessCode,
        );
      }
      if (const {
        1003212,
        1003,
        100301,
        100302,
        100303,
      }.contains(error.businessCode)) {
        throw ApiFailure(
          ApiFailureCategory.permission,
          error.endpointId,
          businessCode: error.businessCode,
        );
      }
      rethrow;
    }
  }

  Future<ApiLiveConnectionInfo> getConnectionInfo(
    String roomId, {
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    final origin = Uri.https('api.live.bilibili.com', '/');
    var cookie = _cookieValues(api.cookieJar.headerFor(origin));
    var device = cookie['buvid3'];
    if (device == null || device.isEmpty) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final pending = _deviceInFlight ??= _loadDevice(context);
        try {
          device = await pending;
          break;
        } on ApiFailure catch (error) {
          if (attempt != 0 ||
              error.category != ApiFailureCategory.cancelled ||
              context?.cancellation?.isCancelled == true) {
            rethrow;
          }
        } finally {
          if (identical(_deviceInFlight, pending)) _deviceInFlight = null;
        }
      }
    }
    if (context?.cancellation?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'live_danmaku_info');
    }
    final data = await api.requestLiveWbiJson(
      '/xlive/web-room/v1/index/getDanmuInfo',
      {'id': roomId, 'type': '0'},
      'live_danmaku_info',
      context: context,
    );
    final token = _requiredText(data['token'], 'live_danmaku_info');
    if (token.length > 4096) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_danmaku_info');
    }
    final hosts = <Uri>[];
    for (final raw in _list(data['host_list'], 'live_danmaku_info').take(10)) {
      final entry = _map(raw, 'live_danmaku_info');
      final host = _text(entry['host']);
      final port = _int(entry['wss_port']);
      if (host == null || !const {443, 2245}.contains(port)) continue;
      final uri = Uri(scheme: 'wss', host: host, port: port, path: '/sub');
      if (isTrustedLiveSocket(uri)) hosts.add(uri);
    }
    if (hosts.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'live_danmaku_info');
    }
    cookie = _cookieValues(api.cookieJar.headerFor(origin));
    return ApiLiveConnectionInfo(
      roomId: roomId,
      token: token,
      buvid: device ?? '',
      userId: _optionalId(cookie['DedeUserID']) ?? '0',
      hosts: hosts,
    );
  }

  Future<String> _loadDevice(ApiRequestContext? context) async {
    const endpoint = 'live_device';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/frontend/finger/spi'),
      endpoint,
      context: context,
    );
    final device = _requiredText(data['b_3'], endpoint);
    if (device.length > 200 || RegExp(r'[;\r\n]').hasMatch(device)) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    if (context?.cancellation?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
      'buvid3=$device; Domain=.bilibili.com; Path=/; Secure',
    ]);
    await api.onCookiesChanged?.call();
    return device;
  }

  static Map<String, String> _cookieValues(String? header) {
    final result = <String, String>{};
    for (final pair in header?.split('; ') ?? const <String>[]) {
      final separator = pair.indexOf('=');
      if (separator > 0) {
        result.putIfAbsent(
          pair.substring(0, separator),
          () => pair.substring(separator + 1),
        );
      }
    }
    return result;
  }

  Future<ApiLiveRoom> getRoom(
    String roomId, {
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    const endpoint = 'live_room';
    final room = await api.requestJson(
      Uri.https('api.live.bilibili.com', '/room/v1/Room/get_info', {
        'room_id': roomId,
      }),
      endpoint,
      context: context,
    );
    final uid = _id(room['uid'], endpoint);
    final master = await api.requestJson(
      Uri.https('api.live.bilibili.com', '/live_user/v1/Master/info', {
        'uid': uid,
      }),
      'live_anchor',
      context: context,
    );
    final info = _map(master['info'], 'live_anchor');
    return ApiLiveRoom(
      roomId: _id(room['room_id'], endpoint),
      title: _requiredText(room['title'], endpoint),
      anchorName: _requiredText(info['uname'], 'live_anchor'),
      anchorMid: uid,
      anchorAvatarUrl: _imageUri(info['face']),
      coverUrl: _imageUri(room['user_cover'] ?? room['keyframe']),
      description: _text(room['description']) ?? '',
      areaName: _text(room['area_name']) ?? '',
      liveStatus:
          _int(room['live_status']) ??
          (throw const ApiFailure(ApiFailureCategory.protocol, endpoint)),
      popularity: _int(room['online']),
    );
  }

  Future<ApiLivePlayInfo> getPlayInfo(
    String roomId, {
    int qn = 10000,
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    if (qn < 1 || qn > 30000) throw ArgumentError.value(qn, 'qn');
    const endpoint = 'live_playurl';
    final data = await api.requestJson(
      Uri.https(
        'api.live.bilibili.com',
        '/xlive/web-room/v2/index/getRoomPlayInfo',
        {
          'room_id': roomId,
          'qn': '$qn',
          'protocol': '0,1',
          'format': '0,2',
          'codec': '0,1',
          'platform': 'web',
        },
      ),
      endpoint,
      context: context,
    );
    final status =
        _int(data['live_status']) ??
        (throw const ApiFailure(ApiFailureCategory.protocol, endpoint));
    final canonicalId = _id(data['room_id'], endpoint);
    final playurl = _mapOrEmpty(_mapOrEmpty(data['playurl_info'])['playurl']);
    final labels = <int, String>{};
    final available = <int>{};
    for (final value in _list(
      playurl['g_qn_desc'] ?? const [],
      endpoint,
    ).take(30)) {
      final entry = _map(value, endpoint);
      final quality = _int(entry['qn']);
      if (quality != null) {
        labels[quality] = _text(entry['desc']) ?? '$quality';
      }
    }
    final streams = <ApiLiveStream>[];
    for (final protocolValue in _list(
      playurl['stream'] ?? const [],
      endpoint,
    ).take(10)) {
      final protocol = _map(protocolValue, endpoint);
      for (final formatValue in _list(
        protocol['format'] ?? const [],
        endpoint,
      ).take(10)) {
        final format = _map(formatValue, endpoint);
        final name = _text(format['format_name']) ?? '';
        for (final codecValue in _list(
          format['codec'] ?? const [],
          endpoint,
        ).take(10)) {
          final codec = _map(codecValue, endpoint);
          final quality = _int(codec['current_qn']);
          final base = _text(codec['base_url']);
          if (quality == null || base == null) continue;
          available.add(quality);
          for (final allowed in _list(
            codec['accept_qn'] ?? const [],
            endpoint,
          ).map(_int).whereType<int>()) {
            available.add(allowed);
          }
          final urls = <Uri>[];
          for (final urlValue in _list(
            codec['url_info'] ?? const [],
            endpoint,
          ).take(10)) {
            final urlInfo = _map(urlValue, endpoint);
            final host = _text(urlInfo['host']);
            if (host == null) continue;
            final extra = _text(urlInfo['extra']) ?? '';
            final url = _mediaUri('$host$base$extra');
            if (url != null) urls.add(url);
          }
          if (urls.isNotEmpty) {
            streams.add(
              ApiLiveStream(
                urls: List.unmodifiable(urls),
                quality: quality,
                qualityLabel: labels[quality] ?? '$quality',
                format: name,
                codec: _text(codec['codec_name']) ?? '',
              ),
            );
          }
        }
      }
    }
    if (status == 1 && streams.isEmpty) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    return ApiLivePlayInfo(
      roomId: canonicalId,
      liveStatus: status,
      streams: List.unmodifiable(streams),
      qualities: List.unmodifiable(
        available.toList()..sort((a, b) => b.compareTo(a)),
      ),
      qualityLabels: Map.unmodifiable(labels),
    );
  }

  Future<List<ApiLiveChatMessage>> getChatHistory(
    String roomId, {
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    const endpoint = 'live_chat_history';
    final data = await api.requestJson(
      Uri.https('api.live.bilibili.com', '/xlive/web-room/v1/dM/gethistory', {
        'roomid': roomId,
      }),
      endpoint,
      context: context,
    );
    final messages = <ApiLiveChatMessage>[];
    for (final value in _list(data['room'] ?? const [], endpoint).take(100)) {
      final entry = _map(value, endpoint);
      final rawText = _text(entry['text']);
      if (rawText == null) continue;
      final text = rawText.substring(0, rawText.length.clamp(0, 300));
      final name = _text(entry['nickname']) ?? '';
      final timeline = _text(entry['timeline']);
      messages.add(
        ApiLiveChatMessage(
          userName: name.substring(0, name.length.clamp(0, 100)),
          userId:
              _optionalId(_mapOrEmpty(entry['user'])['uid']) ??
              _optionalId(entry['uid']),
          text: text,
          timestamp: _historyTimestamp(timeline),
          id: _optionalId(entry['id_str'] ?? entry['id']),
          emotes: liveChatEmotes(entry['emots'], text),
          sticker: liveChatImage(entry['emoticon']),
        ),
      );
    }
    return List.unmodifiable(messages);
  }

  /// Public Web read. A null list is the observed empty-room response.
  Future<List<ApiLiveSuperChatMessage>> getSuperChats(
    String roomId, {
    ApiRequestContext? context,
  }) async {
    _validateId(roomId);
    const endpoint = 'live_super_chat';
    final data = await api.requestJson(
      Uri.https('api.live.bilibili.com', '/av/v1/SuperChat/getMessageList', {
        'room_id': roomId,
      }),
      endpoint,
      context: context,
    );
    final messages = <ApiLiveSuperChatMessage>[];
    for (final value in _list(data['list'] ?? const [], endpoint).take(100)) {
      final entry = _map(value, endpoint);
      final user = _map(entry['user_info'], endpoint);
      final price = _int(entry['price']);
      if (price == null || price <= 0) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      final text = _requiredText(entry['message'], endpoint);
      final name = _requiredText(user['uname'], endpoint);
      messages.add(
        ApiLiveSuperChatMessage(
          id: _id(entry['id'], endpoint),
          userName: name.substring(0, name.length.clamp(0, 100)),
          userId: _optionalId(entry['uid']),
          text: text.substring(0, text.length.clamp(0, 2000)),
          price: price,
          avatarUrl: _imageUri(user['face']),
          startedAt: _unixSeconds(entry['start_time']),
          expiresAt: _unixSeconds(entry['end_time']),
          backgroundColor: _argb(entry['background_color']),
          backgroundBottomColor: _argb(entry['background_bottom_color']),
          textColor: _argb(entry['font_color']),
        ),
      );
    }
    return List.unmodifiable(messages);
  }

  static void _validateId(String value) {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw ArgumentError('Invalid live room ID');
    }
  }

  static Map<String, Object?> _map(Object? value, String endpoint) =>
      value is Map<String, Object?>
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  static Map<String, Object?> _mapOrEmpty(Object? value) =>
      value is Map<String, Object?> ? value : const {};
  static List<Object?> _list(Object? value, String endpoint) => value is List
      ? value
      : throw ApiFailure(ApiFailureCategory.protocol, endpoint);
  static String _id(Object? value, String endpoint) =>
      _optionalId(value) ??
      (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static String? _optionalId(Object? value) {
    final text = value is int
        ? '$value'
        : value is String
        ? value
        : null;
    return text != null && RegExp(r'^[1-9][0-9]*$').hasMatch(text)
        ? text
        : null;
  }

  static int? _int(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static DateTime? _unixSeconds(Object? value) {
    final seconds = _int(value);
    if (seconds == null || seconds <= 0 || seconds > 253402300799) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static DateTime? _historyTimestamp(String? value) {
    if (value == null) return null;
    final iso = value.replaceFirst(' ', 'T');
    // Web history timeline is Beijing wall time, independent of device zone.
    return DateTime.tryParse(
      RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(iso)
          ? '$iso+08:00'
          : iso,
    );
  }

  static int? _argb(Object? value) {
    if (value is! String || !value.startsWith('#')) return null;
    final hex = value.substring(1);
    if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
      return null;
    }
    final color = int.parse(hex, radix: 16);
    return hex.length == 6 ? 0xff000000 | color : color;
  }

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static String _requiredText(Object? value, String endpoint) =>
      _text(value) ?? (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static Uri? _mediaUri(String value) {
    if (value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }

  static Uri? _imageUri(Object? value) {
    if (value is! String || value.isEmpty || value.length > 2048) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    if (uri.scheme == 'https') return uri;
    if (uri.scheme == 'http' &&
        (uri.host == 'hdslb.com' || uri.host.endsWith('.hdslb.com'))) {
      return uri.replace(scheme: 'https');
    }
    return null;
  }
}

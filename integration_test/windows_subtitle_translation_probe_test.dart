import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show PointerDeviceKind;

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/input_test_app.dart';

/// Explicit local read probe. Never logs credentials, signed URLs or cue text.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('inspect saved-session subtitles and translated media', (
    tester,
  ) async {
    final saved = await SystemCredentialStore().read();
    _report({'savedSessionAvailable': saved != null});
    if (saved == null) fail('Requires an existing saved Web session');
    final decoded = jsonDecode(saved);
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['cookies'] is! Map<String, Object?>) {
      fail('Unsupported secure session snapshot');
    }
    final transport = _ProbeTransport();
    final requests = ApiRequests();
    final api = BiliApiClient(transport: transport, sessionProvider: requests);
    addTearDown(() {
      requests.advanceSession();
      api.cookieJar.clear();
      api.close();
      transport.inner.close();
    });
    api.cookieJar.restoreFromSecureStorage(
      decoded['cookies'] as Map<String, Object?>,
    );
    await tester.runAsync(() async {
      final nav = await api.getNav();
      _report({'sessionValid': nav.isLogin});
      expect(nav.isLogin, isTrue);
      for (final bvid in const ['BV1fnYk6eENv', 'BV1jxtC6pEuU']) {
        final detail = await api.getVideoDetail(bvid);
        final part = detail.pages.first;
        _report({'video': bvid, 'aid': detail.aid, 'cid': part.cid});
        if (const bool.fromEnvironment('BILI_SUBTITLE_MODERN_ONLY')) {
          if (bvid == 'BV1fnYk6eENv') {
            for (final language in const ['', 'en', 'ja']) {
              await _modernSubtitleProbe(
                api,
                transport,
                detail.aid,
                part.cid,
                language,
              );
            }
          }
          continue;
        }
        final raw = await api.requestWbiJson('/x/player/wbi/v2', {
          'aid': detail.aid,
          'cid': part.cid,
        }, 'player_metadata');
        final subtitle = raw['subtitle'];
        _report({
          'video': bvid,
          'metadataKeys': raw.keys.toList(),
          'needLoginSubtitle': raw['need_login_subtitle'],
          if (subtitle is Map<String, Object?>)
            'subtitleKeys': subtitle.keys.toList(),
        });
        if (subtitle is Map<String, Object?> &&
            subtitle['subtitles'] is List<Object?>) {
          for (final row in (subtitle['subtitles'] as List<Object?>).take(12)) {
            if (row is! Map<String, Object?>) continue;
            _report({
              'video': bvid,
              'trackKeys': row.keys.toList(),
              for (final key in const [
                'lan',
                'lan_doc',
                'type',
                'ai_type',
                'ai_status',
                'role',
                'format',
              ])
                key: row[key],
              'urlHost': _url(row['subtitle_url'])?.host,
              'urlV2Host': _url(row['subtitle_url_v2'])?.host,
            });
          }
        }
        final metadata = await PlaybackMetadataClient(api)
            .load(detail.aid, part.cid);
        _report({
          'video': bvid,
          'parsedTracks': metadata.subtitles.length,
          'subtitleFailure': metadata.subtitleFailure?.category.name,
        });
        for (final track in metadata.subtitles.take(8)) {
          try {
            final cues = await api.getSubtitleCues(track.url);
            _report({
              'video': bvid,
              'label': track.label,
              'cueCount': cues.length,
              'firstMs': cues.firstOrNull?.start.inMilliseconds,
              'lastMs': cues.lastOrNull?.end.inMilliseconds,
            });
          } on ApiFailure catch (failure) {
            _report({
              'video': bvid,
              'label': track.label,
              'category': failure.category.name,
              'endpoint': failure.endpointId,
              'httpStatus': failure.httpStatus,
              'businessCode': failure.businessCode,
            });
          }
        }
        await api.getPlayInfo(bvid, part.cid);
      }
    });
    if (const bool.fromEnvironment('BILI_SUBTITLE_NATIVE')) {
      await _nativeProbe(tester, api, requests, transport);
    }
  }, skip: !const bool.fromEnvironment('BILI_SUBTITLE_SAVED_SESSION'));
}

Uri? _url(Object? value) => value is String
    ? Uri.tryParse(value.startsWith('//') ? 'https:$value' : value)
    : null;

void _report(Map<String, Object?> value) => debugPrint(jsonEncode(value));

final class _ProbeTransport implements ApiTransport {
  final inner = DioApiTransport();
  Map<String, Object?>? lastPlayurl;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final response = await inner.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancellation: cancellation,
    );
    if (uri.host != 'api.bilibili.com') {
      Object? body;
      try {
        body = jsonDecode(utf8.decode(response.body));
      } on FormatException {
        // Do not log a non-JSON response, which may contain a signed URL.
      }
      _report({
        'subtitleBodyHost': uri.host,
        'status': response.statusCode,
        'bytes': response.body.length,
        'contentType': response.header('content-type'),
        'jsonRootKeys': body is Map<String, Object?>
            ? body.keys.toList()
            : null,
        if (body is Map<String, Object?>) ..._cueStats(body['body']),
      });
    } else if (uri.path.endsWith('/playurl')) {
      final root = jsonDecode(utf8.decode(response.body));
      if (root is Map<String, Object?> &&
          root['data'] is Map<String, Object?>) {
        final data = root['data'] as Map<String, Object?>;
        lastPlayurl = data;
        _report({
          'playurlPath': uri.path,
          'playurlKeys': data.keys.toList(),
          'language': _languageSummary(data['language']),
          'cur_language': data['cur_language'],
          'cur_production_type': data['cur_production_type'],
        });
      }
    }
    return response;
  }
}

Map<String, Object?> _cueStats(Object? value) {
  if (value is! List<Object?>) return {'bodyList': false};
  final invalid = <Map<String, Object?>>[];
  var empty = 0;
  for (var index = 0; index < value.length; index++) {
    final row = value[index];
    if (row is! Map<String, Object?>) continue;
    final from = row['from'], to = row['to'], text = row['content'];
    if (text == '') empty++;
    if (from is! num ||
        to is! num ||
        to < from ||
        text is! String ||
        text.isEmpty) {
      if (invalid.length < 8) {
        invalid.add({
          'index': index,
          'from': from is num ? from : null,
          'to': to is num ? to : null,
          'contentType': text.runtimeType.toString(),
          'contentLength': text is String ? text.length : null,
        });
      }
    }
  }
  return {
    'bodyRows': value.length,
    'emptyTextRows': empty,
    'invalidRows': invalid,
  };
}

Future<void> _nativeProbe(
  WidgetTester tester,
  BiliApiClient api,
  ApiRequests requests,
  _ProbeTransport transport,
) async {
  initializePlayerBackend();
  final detail = await ApiVideoRepository(api, requests).loadDetail(
    const VideoId('BV1fnYk6eENv'),
    cancellation: RequestCancellation(),
  );
  final engine = MediaKitEngine();
  final session = PlaybackSession(
    engine: engine,
    repository: ApiPlaybackRepository(api, requests),
    progress: _NoopProgress(),
    accountScope: () => 'subtitle-probe',
    sessionEpoch: () => requests.sessionEpoch,
  );
  final settings = AppSettings(
    autoPlay: false,
    defaultVolume: 0,
    preferredQuality: 32,
    danmakuEnabled: false,
    resumePlayback: false,
    playerControlsMode: PlayerControlsMode.dynamic,
  );
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  var hover = 0.0;
  Future<void> choose(String tooltip, String label) async {
    final bounds = tester.getRect(
      find.byKey(const ValueKey('player-surface-tap-target')),
    );
    hover += 2;
    await mouse.moveTo(bounds.topLeft + Offset(30 + hover, 30));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump(const Duration(milliseconds: 300));
    await mouse.moveTo(const Offset(-10, -10));
    await tester.pump(const Duration(seconds: 2));
    final item = find
        .ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is PopupMenuEntry,
          ),
        )
        .last;
    await tester.ensureVisible(item);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(item);
    await tester.pump(const Duration(milliseconds: 300));
  }

  try {
    await mouse.addPointer(location: const Offset(-10, -10));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: InputTestApp(
          home: Scaffold(
            body: SizedBox(
              width: 1100,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: PlaybackPanel(
                  detail: detail,
                  part: detail.parts.first,
                  settings: settings,
                  onToggleComments: () {},
                  window: WindowService(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () => session.media != null && session.subtitleTracks.isNotEmpty,
    );
    await choose('字幕', '中文 · AI');
    await _until(tester, () => session.subtitleCues.isNotEmpty);
    await session.seek(const Duration(seconds: 10));
    await _until(tester, () => engine.currentSnapshot.position.inSeconds >= 9);
    await tester.pump(const Duration(milliseconds: 400));
    final cue = session.subtitleCues
        .where(
          (cue) =>
              engine.currentSnapshot.position >= cue.start &&
              engine.currentSnapshot.position < cue.end,
        )
        .firstOrNull;
    expect(cue, isNotNull);
    expect(find.text(cue!.text), findsOneWidget);
    _report({
      'nativeSubtitleVisible': true,
      'selectedTrack': session.selectedSubtitle,
      'positionMs': engine.currentSnapshot.position.inMilliseconds,
      'cueCount': session.subtitleCues.length,
      'decodedVideo': engine.inspectDiagnostics().hasDecodedVideo,
      'decodedAudio': engine.inspectDiagnostics().hasDecodedAudio,
    });
    await choose('播放速度', '1.5x');
    await _until(tester, () => engine.currentSnapshot.rate == 1.5);
    _report({'nativeMenuRate': engine.currentSnapshot.rate});
    final current = session.media;
    final quality = current?.qualities
        .where((value) => value != current.quality)
        .firstOrNull;
    expect(quality, isNotNull);
    final qualityLabel =
        current?.qualityLabels[quality] ??
        switch (quality) {
          120 => '4K',
          116 => '1080P60',
          112 => '1080P+',
          80 => '1080P',
          74 => '720P60',
          64 => '720P',
          32 => '480P',
          16 => '360P',
          _ => '$quality',
        };
    await choose('清晰度', qualityLabel);
    await _until(
      tester,
      () => session.media?.quality == quality && !session.isResolving,
    );
    _report({'nativeMenuQuality': session.media?.quality});
    await _until(
      tester,
      () => session.subtitleTracks.isNotEmpty && !session.subtitleLoading,
    );
    final original = session.media;
    for (final language in const ['en', 'ja', '']) {
      final generation = session.sourceGeneration;
      final label = switch (language) {
        'en' => 'English · AI 翻译',
        'ja' => '日本語 · AI 翻译',
        _ => '原声',
      };
      await choose('语音翻译', label);
      await _until(
        tester,
        () =>
            session.sourceGeneration > generation &&
            !session.isResolving &&
            engine.inspectDiagnostics().hasDecodedVideo &&
            engine.inspectDiagnostics().hasDecodedAudio,
      );
      expect(session.error, isNull);
      expect(session.selectedVoice.languageCode, language);
      expect(
        engine.currentSnapshot.position.inMilliseconds,
        closeTo(10000, 100),
      );
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
      await _until(
        tester,
        () => session.subtitleTracks.isNotEmpty && !session.subtitleLoading,
      );
      if (language.isNotEmpty) {
        expect(
          session.subtitleTracks[session.selectedSubtitle].languageCode,
          'ai-$language',
        );
        expect(session.subtitleCues, isNotEmpty);
        expect(session.subtitleMessage, isNull);
      }
      final media = session.media;
      final decoded = engine.inspectDiagnostics();
      _report({
        'nativeTranslation': language.isEmpty ? 'original' : language,
        'responseLanguage': transport.lastPlayurl?['cur_language'],
        'responseProductionType': transport.lastPlayurl?['cur_production_type'],
        'changedVideoResource':
            original?.video.urls.first.path != media?.video.urls.first.path,
        'changedAudioResource':
            original?.audio?.urls.first.path != media?.audio?.urls.first.path,
        'decodedVideo': decoded.hasDecodedVideo,
        'decodedAudio': decoded.hasDecodedAudio,
        'audioChannels': decoded.audioChannels,
        'audioSampleRate': decoded.audioSampleRate,
        'positionMs': engine.currentSnapshot.position.inMilliseconds,
        'desiredPlaying': engine.currentSnapshot.desiredPlaying,
        'rate': engine.currentSnapshot.rate,
        'subtitleCueCount': session.subtitleCues.length,
      });
    }
    expect(tester.takeException(), isNull);
  } finally {
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await session.close();
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 50));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Native probe timed out');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _NoopProgress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;

  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}

/// The field numbers were inspected in Bilibili's player core.ba67b466.js,
/// bilibili.subtitle.SubtitleViewReply. This probe copies no player source.
Future<void> _modernSubtitleProbe(
  BiliApiClient api,
  _ProbeTransport transport,
  String aid,
  String cid,
  String language,
) async {
  final uri = Uri.https('api.bilibili.com', '/x/v2/subtitle/web/view', {
    'oid': cid,
    'pid': aid,
    'type': '1',
    'context_ext': jsonEncode({'video_type': 1}),
    'cur_language': language,
    'cur_production_type': language.isEmpty ? '0' : '2',
    'playlist_switch': '0',
  });
  final cookie = api.cookieJar.headerFor(uri);
  final response = await transport.inner.get(
    uri,
    headers: {
      'User-Agent': 'Mozilla/5.0',
      'Referer': 'https://www.bilibili.com/',
      'Cookie': ?cookie,
    },
    timeout: const Duration(seconds: 15),
  );
  _report({
    'modernSubtitleLanguage': language,
    'httpStatus': response.statusCode,
    'bytes': response.body.length,
    'contentType': response.header('content-type'),
  });
  if (response.statusCode != 200 || response.body.length > 256 * 1024) {
    fail('Modern subtitle metadata unavailable');
  }
  final root = _wireFields(response.body);
  final subtitleBody = root[1]?.firstOrNull;
  if (subtitleBody is! Uint8List) fail('Missing Protobuf subtitle object');
  final subtitle = _wireFields(subtitleBody);
  final tracks = subtitle[3] ?? const <Object>[];
  _report({'modernSubtitleTrackCount': tracks.length});
  for (final value in tracks.take(12)) {
    if (value is! Uint8List) fail('Invalid Protobuf subtitle track');
    final track = _wireFields(value);
    String? text(int field) {
      final value = track[field]?.firstOrNull;
      return value is Uint8List ? utf8.decode(value) : null;
    }

    int number(int field) => switch (track[field]?.firstOrNull) {
      final int value => value,
      _ => 0,
    };
    _report({
      'requestedLanguage': language,
      'lan': text(3),
      'lan_doc': text(4),
      'urlHost': _url(text(5))?.host,
      'type': number(7),
      'lan_doc_brief': text(8),
      'ai_type': number(9),
      'ai_status': number(10),
      'role': number(11),
      'format': number(13),
      'fieldNumbers': track.keys.toList(),
    });
  }
}

Map<int, List<Object>> _wireFields(Uint8List bytes) {
  var offset = 0, fields = 0;
  final result = <int, List<Object>>{};
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 64 && offset < bytes.length; shift += 7) {
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte & 128 == 0) return value;
    }
    throw const FormatException('Invalid Protobuf varint');
  }

  while (offset < bytes.length) {
    if (++fields > 2048) {
      throw const FormatException('Too many metadata fields');
    }
    final tag = varint();
    final field = tag >> 3;
    if (field == 0) throw const FormatException('Invalid Protobuf field');
    switch (tag & 7) {
      case 0:
        (result[field] ??= []).add(varint());
      case 1:
        offset += 8;
      case 2:
        final length = varint();
        if (length < 0 || length > bytes.length - offset) {
          throw const FormatException('Invalid Protobuf length');
        }
        (result[field] ??= []).add(
          Uint8List.sublistView(bytes, offset, offset + length),
        );
        offset += length;
      case 5:
        offset += 4;
      default:
        throw const FormatException('Unsupported Protobuf wire type');
    }
    if (offset > bytes.length) {
      throw const FormatException('Truncated Protobuf');
    }
  }
  return result;
}

Map<String, Object?>? _languageSummary(Object? value) {
  if (value is! Map<String, Object?>) return null;
  final items = value['items'];
  return {
    'support': value['support'] == true,
    'list_title': value['list_title'],
    'default_title': value['default_title'],
    'items': items is List<Object?>
        ? [
            for (final item in items.take(20))
              if (item is Map<String, Object?>)
                {
                  for (final key in const [
                    'lang',
                    'title',
                    'subtitle_lang',
                    'production_type',
                    'video_detext',
                    'video_mouth_shape_change',
                  ])
                    key: item[key],
                },
          ]
        : null,
  };
}

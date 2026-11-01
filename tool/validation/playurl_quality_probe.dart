import 'dart:convert';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:flutter/material.dart';

/// Explicit local read probe; never prints cookies, media URLs or response text.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('播放接口只读诊断'))));
  const useSession = bool.fromEnvironment('BILI_PLAYURL_USE_SESSION');
  final saved = useSession ? await SystemCredentialStore().read() : null;
  final snapshot = saved == null ? null : jsonDecode(saved);
  final transport = _ProbeTransport();
  final requests = ApiRequests();
  final api = BiliApiClient(transport: transport, sessionProvider: requests);
  if (snapshot case {'cookies': final Map<String, Object?> cookies}) {
    api.cookieJar.restoreFromSecureStorage(cookies);
  }
  try {
    final nav = await api.getNav();
    debugPrint('QUALITY_PROBE signedIn=${nav.isLogin}');
    const bvid = String.fromEnvironment(
      'BILI_PLAYURL_BVID',
      defaultValue: 'BV1VNxr63EZp',
    );
    final detail = await api.getVideoDetail(bvid);
    for (final qn in [80, 116, 129]) {
      try {
        final info = await api.getPlayInfo(
          bvid,
          detail.pages.first.cid,
          qn: qn,
        );
        debugPrint(
          'QUALITY_PROBE qn=$qn videos=${info.dashVideo.map((v) => '${v.id}:${v.codecs}').join(',')} audio=${info.dashAudio.length}',
        );
      } on ApiFailure catch (failure) {
        debugPrint(
          'QUALITY_PROBE qn=$qn category=${failure.category.name} endpoint=${failure.endpointId} code=${failure.businessCode}',
        );
      }
    }
    final media = await ApiPlaybackRepository(api, requests).resolve(
      const VideoId(bvid),
      detail.pages.first.cid,
      quality: 116,
      cancellation: RequestCancellation(),
    );
    debugPrint(
      'QUALITY_PROBE repositoryQuality=${media.quality} qualities=${media.qualities} audio=${media.audio != null}',
    );
  } finally {
    api.cookieJar.clear();
    api.close();
    transport._inner.close();
  }
}

class _ProbeTransport implements ApiTransport {
  final _inner = DioApiTransport();

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final response = await _inner.get(
      uri,
      headers: headers,
      timeout: timeout,
      cancellation: cancellation,
    );
    if (uri.path == '/x/web-interface/nav') {
      final root = jsonDecode(utf8.decode(response.body));
      if (root case {'data': final Map<String, Object?> data}) {
        debugPrint('QUALITY_PROBE vip=${data['vipStatus']}');
      }
    }
    if (uri.path == '/x/player/wbi/playurl') {
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is Map<String, Object?>) {
        final data = decoded['data'];
        debugPrint(
          'QUALITY_PROBE responseCode=${decoded['code']} quality=${data is Map<String, Object?> ? data['quality'] : null}',
        );
      }
    }
    return response;
  }
}

import 'dart:async';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/cdn_speed_test_repository.dart';

final class ApiCdnSpeedTestRepository implements CdnSpeedTestRepository {
  ApiCdnSpeedTestRepository(
    this.api,
    this.requests, {
    this.probeTimeout = timeout,
  });
  final BiliApiClient api;
  final ApiRequests requests;
  final Duration probeTimeout;
  static const maxBytes = 1024 * 1024;
  static const timeout = Duration(seconds: 5);

  @override
  Future<CdnSpeedSample> loadSample({
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final info = await api.getVideoPreviewInfo(
      'BV1fK4y1t7hj',
      '196018899',
      context: context,
    );
    final track = info.dashVideo.firstOrNull;
    if (track == null) {
      throw const AppFailure(AppFailureKind.playback, '无法获取测速视频，请重试');
    }
    return CdnSpeedSample([
      track.url,
      ...track.backupUrls,
    ], sessionEpoch: requests.sessionEpoch);
  }, cancellation: cancellation);

  @override
  Future<CdnSpeedMeasurement> measure(
    Uri url, {
    required int sessionEpoch,
    required RequestCancellation cancellation,
  }) async {
    if (sessionEpoch != requests.sessionEpoch) {
      throw const AppFailure(AppFailureKind.cancelled, '测速已取消');
    }
    return requests.run((context) async {
      final client = HttpClient()
        ..connectionTimeout = probeTimeout
        ..autoUncompress = false;
      final watch = Stopwatch()..start();
      var bytes = 0;
      var measuredHost = url.host;
      var finished = false;
      // Include DNS, headers and a stalled response body in the same deadline.
      final cancelled = context.cancellation?.whenCancelled
          .then<CdnSpeedMeasurement>((_) {
            if (!finished) client.close(force: true);
            throw const AppFailure(AppFailureKind.cancelled, '测速已取消');
          });
      try {
        final download = () async {
          var target = url;
          for (var redirects = 0; redirects <= 3; redirects++) {
            if (!_isHttpUrl(target) ||
                url.scheme == 'https' && target.scheme != 'https') {
              throw const AppFailure(AppFailureKind.protocol, '不支持此测速地址');
            }
            final request = await client.getUrl(target);
            request.followRedirects = false;
            request.headers
              ..set(HttpHeaders.rangeHeader, 'bytes=0-${maxBytes - 1}')
              ..set(HttpHeaders.refererHeader, 'https://www.bilibili.com/')
              ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0')
              ..set(HttpHeaders.acceptEncodingHeader, 'identity');
            final response = await request.close();
            if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
              final location = response.headers.value(
                HttpHeaders.locationHeader,
              );
              if (location == null || redirects == 3) break;
              target = target.resolve(location);
              // A redirect body is not part of the media sample.
              await response.listen((_) {}).cancel();
              continue;
            }
            if (response.statusCode != 200 && response.statusCode != 206) {
              throw AppFailure(
                AppFailureKind.network,
                '不可用（HTTP ${response.statusCode}）',
              );
            }
            final contentType = response.headers.contentType?.mimeType ?? '';
            if (contentType.startsWith('text/') ||
                contentType.contains('json') ||
                contentType.contains('xml')) {
              throw const AppFailure(AppFailureKind.protocol, '此线路未返回视频数据');
            }
            if (response.statusCode == 206 &&
                !(response.headers.value(HttpHeaders.contentRangeHeader) ?? '')
                    .startsWith('bytes 0-')) {
              throw const AppFailure(AppFailureKind.protocol, '测速分段响应无效');
            }
            measuredHost = target.host;
            await for (final chunk in response) {
              bytes = (bytes + chunk.length).clamp(0, maxBytes);
              if (bytes >= maxBytes) break;
            }
            if (bytes == 0) {
              throw const AppFailure(AppFailureKind.network, '未收到视频数据');
            }
            return CdnSpeedMeasurement(
              bytes: bytes,
              elapsed: watch.elapsed,
              host: target.host,
            );
          }
          throw const AppFailure(AppFailureKind.network, '测速重定向失败');
        }();
        return await Future.any([download, ?cancelled]).timeout(probeTimeout);
      } on TimeoutException {
        if (bytes > 0) {
          return CdnSpeedMeasurement(
            bytes: bytes,
            elapsed: watch.elapsed,
            host: measuredHost,
          );
        }
        throw const AppFailure(AppFailureKind.timeout, '连接超时');
      } on AppFailure {
        rethrow;
      } on IOException {
        throw const AppFailure(AppFailureKind.network, '连接失败');
      } finally {
        finished = true;
        client.close(force: true);
        watch.stop();
      }
    }, cancellation: cancellation);
  }

  bool _isHttpUrl(Uri url) =>
      (url.scheme == 'http' || url.scheme == 'https') &&
      url.host.isNotEmpty &&
      url.userInfo.isEmpty;
}

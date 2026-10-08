import 'dart:async';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/comment_video_link.dart';

typedef ShortLinkExpander = Future<Uri?> Function(
  Uri uri,
  RequestCancellation cancellation,
  Duration timeout,
);

/// Short links use a separate credential-free transport. Only b23.tv is fetched;
/// a redirect to another host is inspected locally and never followed by it.
final class PublicCommentVideoLinkRepository
    implements CommentVideoLinkRepository {
  PublicCommentVideoLinkRepository(
    this.api,
    this.requests, {
    this.expand = readBilibiliShortLinkLocation,
    this.timeout = const Duration(seconds: 8),
  });
  final BiliApiClient api;
  final ApiRequests requests;
  final ShortLinkExpander expand;
  final Duration timeout;

  @override
  Future<VideoId?> resolve(
    Uri uri, {
    required RequestCancellation cancellation,
  }) async {
    final untrack = requests.trackLifetime(cancellation);
    try {
      return await _resolve(uri, cancellation).timeout(timeout);
    } on TimeoutException {
      cancellation.cancel();
      throw const AppFailure(AppFailureKind.timeout, '视频链接解析超时，请稍后重试');
    } on IOException {
      _check(cancellation);
      throw const AppFailure(AppFailureKind.network, '视频链接解析失败，请检查网络后重试');
    } on FormatException {
      throw const AppFailure(AppFailureKind.protocol, '视频链接格式异常');
    } finally {
      untrack();
    }
  }

  Future<VideoId?> _resolve(Uri uri, RequestCancellation cancellation) async {
    var target = uri;
    final seen = <Uri>{};
    for (var redirects = 0; redirects <= 3; redirects++) {
      _check(cancellation);
      final link = parseCommentVideoLink(target);
      if (link?.video case final video?) return video;
      if (link?.aid case final aid?) {
        final bvid = await requests.run(
          (context) => api.getVideoBvidByAid(aid, context: context),
          cancellation: cancellation,
        );
        _check(cancellation);
        return VideoId(bvid);
      }
      if (!isBilibiliShortLink(target)) return null;
      if (redirects == 3 || !seen.add(target)) {
        throw const AppFailure(AppFailureKind.protocol, '视频短链接重定向异常');
      }
      final location = await expand(target, cancellation, timeout);
      _check(cancellation);
      if (location == null) return null;
      target = location;
    }
    return null;
  }

  static void _check(RequestCancellation cancellation) {
    if (cancellation.isCancelled) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }
}

Future<Uri?> readBilibiliShortLinkLocation(
  Uri uri,
  RequestCancellation cancellation,
  Duration timeout, {
  HttpClient Function()? clientFactory,
}) async {
  if (!isBilibiliShortLink(uri)) return null;
  PublicCommentVideoLinkRepository._check(cancellation);
  final client = (clientFactory ?? HttpClient.new)()
    ..connectionTimeout = timeout;
  cancellation.onCancel(() => client.close(force: true));
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      try {
        PublicCommentVideoLinkRepository._check(cancellation);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const AppFailure(AppFailureKind.protocol, '视频短链接缺少目标地址');
          }
          return uri.resolve(location);
        }
        if (response.statusCode == HttpStatus.ok) return null;
        throw const AppFailure(AppFailureKind.network, '视频短链接暂时无法访问');
      } finally {
        // No HTML body is needed, including on unsupported/error responses.
        await response.listen((_) {}).cancel();
      }
    })().timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

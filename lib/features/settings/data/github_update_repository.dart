import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/app_update.dart';

typedef ReleaseFetcher = Future<String> Function(
  RequestCancellation cancellation,
);

final class GitHubUpdateRepository implements AppUpdateRepository {
  GitHubUpdateRepository({
    required this.versionLoader,
    this.fetcher,
    this.timeout = const Duration(seconds: 12),
  });

  final Future<AppVersion> Function() versionLoader;
  final ReleaseFetcher? fetcher;
  final Duration timeout;
  final Set<HttpClient> _clients = {};
  bool _closed = false;
  static const maxResponseBytes = 2 * 1024 * 1024;

  @override
  Future<AppVersion> installedVersion() => versionLoader();

  @override
  Future<AppRelease?> latestRelease(RequestCancellation cancellation) async {
    _checkCancellation(cancellation);
    final body = await (fetcher?.call(cancellation) ?? _fetch(cancellation));
    _checkCancellation(cancellation);
    return parseReleases(body);
  }

  void _checkCancellation(RequestCancellation cancellation) {
    if (_closed || cancellation.isCancelled) {
      throw const AppFailure(AppFailureKind.cancelled, '更新检查已取消');
    }
  }

  Future<String> _fetch(RequestCancellation cancellation) async {
    // Dedicated public transport: no Bilibili Cookie, token, redirects or retry.
    final client = HttpClient()..connectionTimeout = timeout;
    _clients.add(client);
    cancellation.onCancel(() => client.close(force: true));
    try {
      return await (() async {
        final request = await client.getUrl(
          Uri.https('api.github.com', '/repos/CKopoer/BiliSail/releases', {
            'per_page': '100',
          }),
        );
        _checkCancellation(cancellation);
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'BiliSail-update-check',
        );
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github+json',
        );
        request.headers.set('X-GitHub-Api-Version', '2026-03-10');
        final response = await request.close();
        if (response.statusCode == 403 || response.statusCode == 429) {
          throw const AppFailure(
            AppFailureKind.rateLimited,
            'GitHub 请求受限，请稍后重试',
          );
        }
        if (response.statusCode != 200) {
          throw const AppFailure(AppFailureKind.network, '无法获取 GitHub 更新信息');
        }
        if (response.contentLength > maxResponseBytes) {
          throw const AppFailure(AppFailureKind.protocol, '更新信息超过容量限制');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          _checkCancellation(cancellation);
          if (bytes.length + chunk.length > maxResponseBytes) {
            throw const AppFailure(AppFailureKind.protocol, '更新信息超过容量限制');
          }
          bytes.addAll(chunk);
        }
        return utf8.decode(bytes);
      })().timeout(timeout);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      _checkCancellation(cancellation);
      throw const AppFailure(AppFailureKind.timeout, '检查更新超时，请稍后重试');
    } on FormatException {
      throw const AppFailure(AppFailureKind.protocol, '更新信息格式异常');
    } on IOException {
      _checkCancellation(cancellation);
      throw const AppFailure(AppFailureKind.network, '检查更新失败，请检查网络连接');
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  static AppRelease? parseReleases(String body) {
    try {
      if (utf8.encode(body).length > maxResponseBytes) {
        throw const FormatException();
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! List<Object?> || decoded.length > 100) {
        throw const FormatException();
      }
      AppRelease? newest;
      for (final item in decoded) {
        if (item is! Map<String, Object?> ||
            item['draft'] is! bool ||
            item['prerelease'] is! bool ||
            item['tag_name'] is! String) {
          throw const FormatException();
        }
        if (item['draft'] == true) continue;
        final tag = item['tag_name'];
        if (tag is! String) throw const FormatException();
        final version = AppVersion.tryParse(tag);
        // Unrelated/non-version tags are not update candidates.
        if (version == null) continue;
        final urlText = item['html_url'];
        final url = urlText is String ? Uri.tryParse(urlText) : null;
        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'github.com' ||
            url.port != 443 ||
            url.userInfo.isNotEmpty ||
            url.hasQuery ||
            url.hasFragment ||
            url.pathSegments.length != 5 ||
            url.pathSegments.take(4).join('/') !=
                'CKopoer/BiliSail/releases/tag' ||
            url.pathSegments.last != tag) {
          throw const FormatException();
        }
        final notes = item['body'];
        if (notes != null && notes is! String) throw const FormatException();
        final text = notes is String ? notes : '';
        final release = AppRelease(
          version: version,
          url: url,
          notes: text.length > 12000
              ? '${text.substring(0, 12000)}\n…完整说明请查看 Release 页面'
              : text,
          prerelease: item['prerelease'] == true,
        );
        if (newest == null || version.compareTo(newest.version) > 0) {
          newest = release;
        }
      }
      if (newest == null &&
          decoded.isNotEmpty &&
          decoded.any(
            (item) => item is Map<String, Object?> && item['draft'] == false,
          )) {
        throw const FormatException();
      }
      return newest;
    } on FormatException {
      throw const AppFailure(AppFailureKind.protocol, 'GitHub 更新信息格式异常');
    }
  }

  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

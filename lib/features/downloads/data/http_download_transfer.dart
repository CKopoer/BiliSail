import 'dart:async';
import 'dart:io';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/download_models.dart';

/// Transfers one DASH track. URLs and request headers exist only in memory.
final class HttpDownloadTransfer {
  const HttpDownloadTransfer();

  Future<DownloadTrackProgress> transfer({
    required DownloadTrackSource source,
    required DownloadTrackProgress previous,
    required File partFile,
    required Map<String, String> headers,
    required RequestCancellation cancellation,
    required void Function(DownloadTrackProgress) onProgress,
    DateTime? deadline,
  }) async {
    if (source.urls.isEmpty) {
      throw const AppFailure(AppFailureKind.protocol, '没有可用的媒体下载地址');
    }
    var progress = previous;
    final oldLength = await partFile.exists() ? await partFile.length() : 0;
    if (progress.identity != source.identity ||
        oldLength != progress.bytes ||
        progress.bytes > 0 && !_strongEtag(progress.etag)) {
      if (await partFile.exists()) await partFile.delete();
      progress = _fresh(source, previous.fileName);
      onProgress(progress);
    }
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      if (cancellation.isCancelled) throw _cancelled();
      if (deadline != null && DateTime.now().isAfter(deadline)) {
        throw const AppFailure(AppFailureKind.timeout, '下载超过时间限制');
      }
      if (progress.bytes > 0 && !_strongEtag(progress.etag)) {
        await _discard(partFile);
        progress = _fresh(source, previous.fileName);
        onProgress(progress);
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..idleTimeout = const Duration(seconds: 12)
        ..maxConnectionsPerHost = 2;
      client.autoUncompress = false;
      cancellation.onCancel(() => client.close(force: true));
      RandomAccessFile? handle;
      try {
        final url = source.urls[attempt % source.urls.length];
        final request = await client
            .getUrl(url)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = true;
        request.maxRedirects = 3;
        for (final entry in headers.entries) {
          final name = entry.key.toLowerCase();
          if (name == 'referer' || name == 'user-agent') {
            request.headers.set(entry.key, entry.value);
          }
        }
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (progress.bytes > 0) {
          request.headers.set(
            HttpHeaders.rangeHeader,
            'bytes=${progress.bytes}-',
          );
          if (progress.etag case final etag?) {
            request.headers.set(HttpHeaders.ifRangeHeader, etag);
          }
        }
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );
        if (cancellation.isCancelled) throw _cancelled();
        final status = response.statusCode;
        if (status == HttpStatus.forbidden || status == HttpStatus.gone) {
          throw AppFailure(AppFailureKind.permission, '媒体地址已失效（HTTP $status）');
        }
        if (status == HttpStatus.requestedRangeNotSatisfiable) {
          final total = _unsatisfiedTotal(
            response.headers.value(HttpHeaders.contentRangeHeader),
          );
          if (_strongEtag(progress.etag) &&
              response.headers.value(HttpHeaders.etagHeader) == progress.etag &&
              total != null &&
              total == progress.bytes &&
              total == progress.totalBytes) {
            return progress;
          }
          await _discard(partFile);
          progress = _fresh(source, previous.fileName);
          onProgress(progress);
          continue;
        }
        if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
          throw AppFailure(AppFailureKind.network, '媒体下载失败（HTTP $status）');
        }
        final responseEtag = response.headers.value(HttpHeaders.etagHeader);
        final etag = _strongEtag(responseEtag) ? responseEtag : null;
        int total;
        int expectedEnd;
        if (status == HttpStatus.partialContent) {
          final range = _parseRange(
            response.headers.value(HttpHeaders.contentRangeHeader),
          );
          final contentLength = response.contentLength;
          if (range == null ||
              range.start != progress.bytes ||
              (contentLength >= 0 &&
                  range.end - range.start + 1 != contentLength)) {
            throw const AppFailure(AppFailureKind.protocol, '媒体续传范围无效');
          }
          total = range.total;
          expectedEnd = range.end;
          if ((progress.totalBytes != null && progress.totalBytes != total) ||
              (progress.etag != null && progress.etag != etag)) {
            await _discard(partFile);
            progress = _fresh(source, previous.fileName);
            onProgress(progress);
            continue;
          }
        } else {
          if (response.contentLength <= 0) {
            throw const AppFailure(AppFailureKind.protocol, '媒体响应缺少有效长度');
          }
          total = response.contentLength;
          expectedEnd = total - 1;
          if (progress.bytes > 0) {
            await _discard(partFile);
            progress = _fresh(source, previous.fileName);
            onProgress(progress);
          }
        }
        handle = await partFile.open(
          mode: progress.bytes > 0 ? FileMode.append : FileMode.write,
        );
        var bytes = progress.bytes;
        await for (final chunk in response.timeout(
          const Duration(seconds: 20),
        )) {
          if (cancellation.isCancelled) throw _cancelled();
          if (deadline != null && DateTime.now().isAfter(deadline)) {
            throw const AppFailure(AppFailureKind.timeout, '下载超过时间限制');
          }
          bytes += chunk.length;
          if (bytes > expectedEnd + 1) {
            throw const AppFailure(AppFailureKind.protocol, '媒体响应超过声明长度');
          }
          await handle.writeFrom(chunk);
          progress = DownloadTrackProgress(
            kind: previous.kind,
            identity: source.identity,
            fileName: previous.fileName,
            codec: source.codec,
            bandwidth: source.bandwidth,
            bytes: bytes,
            totalBytes: total,
            etag: etag,
          );
          onProgress(progress);
        }
        await handle.flush();
        await handle.close();
        handle = null;
        if (bytes != expectedEnd + 1) {
          throw const AppFailure(AppFailureKind.network, '媒体响应提前结束');
        }
        if (bytes == total) return progress;
        if (etag == null) {
          throw const AppFailure(AppFailureKind.protocol, '媒体分段响应缺少续传校验标识');
        }
        continue;
      } on AppFailure catch (error) {
        if (error.kind == AppFailureKind.cancelled ||
            error.kind == AppFailureKind.permission ||
            error.kind == AppFailureKind.protocol ||
            error.kind == AppFailureKind.timeout &&
                deadline != null &&
                DateTime.now().isAfter(deadline)) {
          rethrow;
        }
        lastError = error;
      } on TimeoutException {
        lastError = const AppFailure(AppFailureKind.timeout, '媒体下载超时');
      } on SocketException {
        lastError = const AppFailure(AppFailureKind.network, '媒体连接中断');
      } on HttpException {
        lastError = const AppFailure(AppFailureKind.network, '媒体连接失败');
      } finally {
        try {
          try {
            await handle?.flush();
          } finally {
            await handle?.close();
          }
        } finally {
          client.close(force: true);
        }
      }
      // A short response or interrupted connection can resume from actual disk bytes.
      if (await partFile.exists()) {
        final length = await partFile.length();
        progress = DownloadTrackProgress(
          kind: progress.kind,
          identity: progress.identity,
          fileName: progress.fileName,
          codec: progress.codec,
          bandwidth: progress.bandwidth,
          bytes: length,
          totalBytes: progress.totalBytes,
          etag: progress.etag,
        );
        onProgress(progress);
      }
    }
    throw lastError ?? const AppFailure(AppFailureKind.network, '媒体下载失败');
  }

  static DownloadTrackProgress _fresh(
    DownloadTrackSource source,
    String name,
  ) => DownloadTrackProgress(
    kind: source.kind,
    identity: source.identity,
    fileName: name,
    codec: source.codec,
    bandwidth: source.bandwidth,
  );

  static Future<void> _discard(File file) async {
    if (await file.exists()) await file.delete();
  }

  static AppFailure _cancelled() =>
      const AppFailure(AppFailureKind.cancelled, '下载已取消');

  static bool _strongEtag(String? value) {
    if (value == null ||
        value.length < 2 ||
        value.codeUnitAt(0) != 0x22 ||
        value.codeUnitAt(value.length - 1) != 0x22) {
      return false;
    }
    for (var i = 1; i < value.length - 1; i++) {
      final code = value.codeUnitAt(i);
      if (code != 0x21 &&
          (code < 0x23 || code > 0x7e) &&
          (code < 0x80 || code > 0xff)) {
        return false;
      }
    }
    return true;
  }

  static _ByteRange? _parseRange(String? value) {
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value ?? '');
    if (match == null) return null;
    final start = int.tryParse(match[1] ?? '');
    final end = int.tryParse(match[2] ?? '');
    final total = int.tryParse(match[3] ?? '');
    if (start == null ||
        end == null ||
        total == null ||
        start > end ||
        end >= total) {
      return null;
    }
    return _ByteRange(start, end, total);
  }

  static int? _unsatisfiedTotal(String? value) {
    final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(value ?? '');
    return match == null ? null : int.tryParse(match[1] ?? '');
  }
}

final class _ByteRange {
  const _ByteRange(this.start, this.end, this.total);
  final int start, end, total;
}

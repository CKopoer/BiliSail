import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:crypto/crypto.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/request_cancellation.dart';
import '../../playback/domain/playback_repository.dart';
import '../domain/download_repository.dart';

/// Resolves only Web DASH media. Every persisted identity excludes signed URLs.
final class ApiDownloadSourceRepository implements DownloadSourceRepository {
  ApiDownloadSourceRepository(
    this.api,
    this.requests, {
    required String Function() accountScope,
    this.cdnPreference,
  }) : _accountScope = accountScope; // ignore: prefer_initializing_formals

  final BiliApiClient api;
  final ApiRequests requests;
  final String Function() _accountScope;
  final Future<MediaCdnPreference> Function()? cdnPreference;

  static const _headers = <String, String>{
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36',
  };

  @override
  String get accountScope => _accountScope();

  @override
  int get sessionEpoch => requests.sessionEpoch;

  void _check(RequestCancellation cancellation, String scope, int epoch) {
    if (cancellation.isCancelled ||
        requests.sessionEpoch != epoch ||
        _accountScope() != scope) {
      throw const AppFailure(AppFailureKind.cancelled, '下载请求已取消');
    }
  }

  Future<T> _read<T>(
    Future<T> Function(ApiRequestContext) operation,
    RequestCancellation cancellation,
    String scope,
    int epoch,
  ) async {
    _check(cancellation, scope, epoch);
    final result = await requests.run(operation, cancellation: cancellation);
    _check(cancellation, scope, epoch);
    return result;
  }

  Future<ApiPlayInfo> _playInfo(
    DownloadItem item,
    int quality,
    RequestCancellation cancellation,
    String scope,
    int epoch,
  ) async {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(item.part.cid) ||
        (item.episodeId == null && !item.video.id.isValid) ||
        (item.episodeId != null &&
            !RegExp(r'^[1-9][0-9]*$').hasMatch(item.episodeId!))) {
      throw const AppFailure(AppFailureKind.protocol, '下载内容标识无效');
    }
    final info = await _read(
      (context) => item.episodeId == null
          ? api.getPlayInfo(
              item.video.id.value,
              item.part.cid,
              qn: quality,
              context: context,
            )
          : PgcClient(api)
                .getPlayInfo(item.episodeId!, qn: quality, context: context),
      cancellation,
      scope,
      epoch,
    );
    if (item.episodeId != null && info.isPreview) {
      throw const AppFailure(
        AppFailureKind.permission,
        '当前账号仅能播放试看片段，无法下载完整剧集',
      );
    }
    return info;
  }

  @override
  Future<List<int>> qualities(
    DownloadItem item, {
    required RequestCancellation cancellation,
  }) async {
    final scope = _accountScope();
    final epoch = requests.sessionEpoch;
    final first = await _playInfo(item, 127, cancellation, scope, epoch);
    if (!first.dashAudio.any(
      (track) => track.codecs.toLowerCase().startsWith('mp4a'),
    )) {
      throw const AppFailure(AppFailureKind.playback, '当前没有可下载的 AAC 音频轨道');
    }
    // acceptQuality advertises possible tiers, including ones this account
    // cannot currently obtain. Only returned DASH tracks are selectable.
    final available =
        first.dashVideo
            .where(
              (track) =>
                  track.id > 0 &&
                  VideoCodecPreference.fromCodec(track.codecs) != null,
            )
            .map((track) => track.id)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    _check(cancellation, scope, epoch);
    return List.unmodifiable(available);
  }

  @override
  Future<DownloadResolvedSource> resolve(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) async {
    final scope = _accountScope();
    final epoch = requests.sessionEpoch;
    final info = await _playInfo(
      item,
      selection.quality,
      cancellation,
      scope,
      epoch,
    );
    final videos =
        info.dashVideo
            .where(
              (track) =>
                  track.id == selection.quality &&
                  VideoCodecPreference.fromCodec(track.codecs) ==
                      selection.codec,
            )
            .toList()
          ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    final audios =
        info.dashAudio
            .where((track) => track.codecs.toLowerCase().startsWith('mp4a'))
            .toList()
          ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    if (videos.isEmpty) {
      throw const AppFailure(AppFailureKind.playback, '所选画质或视频编码当前不可用');
    }
    if (audios.isEmpty) {
      throw const AppFailure(AppFailureKind.playback, '当前没有可下载的 AAC 音频轨道');
    }
    final preference =
        await cdnPreference?.call() ?? MediaCdnPreference.automatic;
    _check(cancellation, scope, epoch);
    DownloadTrackSource track(ApiMediaTrack media, DownloadTrackKind kind) {
      final urls = orderMediaCdnUrls(
        [
          media.url,
          ...media.backupUrls,
        ].where((url) => url.scheme == 'https' && url.host.isNotEmpty),
        preference,
      );
      if (urls.isEmpty) {
        throw const AppFailure(AppFailureKind.protocol, '播放源没有安全的下载地址');
      }
      // The final media filename survives CDN host and signature renewal.
      final file = media.url.pathSegments.lastOrNull ?? '';
      if (file.isEmpty) {
        throw const AppFailure(AppFailureKind.protocol, '播放源缺少媒体文件标识');
      }
      return DownloadTrackSource(
        identity: sha256
            .convert(
              utf8.encode(
                '${item.key}|${kind.name}|${media.id}|${media.codecs}|${media.bandwidth}|$file',
              ),
            )
            .toString(),
        kind: kind,
        urls: urls,
        codec: media.codecs,
        bandwidth: media.bandwidth,
      );
    }

    return DownloadResolvedSource(
      video: track(videos.first, DownloadTrackKind.video),
      audio: track(audios.first, DownloadTrackKind.audio),
      quality: selection.quality,
      duration: info.duration,
      headers: _headers,
    );
  }

  @override
  Future<DownloadExtras> extras(
    DownloadItem item,
    DownloadSelection selection, {
    required RequestCancellation cancellation,
  }) async {
    final scope = _accountScope();
    final epoch = requests.sessionEpoch;
    _check(cancellation, scope, epoch);
    final release = requests.trackLifetime(cancellation);
    final warnings = <String>[];
    final subtitles = <DownloadedSubtitle>[];
    final comments = <TimedComment>[];
    var encodedBudget = 30 * 1024 * 1024;
    Uint8List? cover;
    try {
      var coverUrl = Uri.tryParse(item.video.coverUrl);
      ApiVideoDetail? detail;
      if (coverUrl == null || !coverUrl.hasAuthority) {
        try {
          if (item.episodeId case final episodeId?) {
            final season = await _read(
              (context) =>
                  PgcClient(api)
                      .getSeason(episodeId: episodeId, context: context),
              cancellation,
              scope,
              epoch,
            );
            final episode = season.episodes
                .where((entry) => entry.episodeId == episodeId)
                .firstOrNull;
            coverUrl = episode?.coverUrl ?? season.coverUrl;
          } else {
            detail = await _read(
              (context) =>
                  api.getVideoDetail(item.video.id.value, context: context),
              cancellation,
              scope,
              epoch,
            );
            coverUrl = detail?.coverUrl;
          }
        } catch (error) {
          _check(cancellation, scope, epoch);
          warnings.add('封面信息获取失败：${_reason(error)}');
        }
      }
      if (coverUrl != null && coverUrl.hasAuthority) {
        try {
          cover = await _cover(coverUrl, cancellation, scope, epoch);
          encodedBudget -= cover.length;
        } catch (error) {
          _check(cancellation, scope, epoch);
          warnings.add('封面保存失败：${_reason(error)}');
        }
      }
      if (selection.includeSubtitles) {
        try {
          final aid =
              item.aid ??
              detail?.aid ??
              (await _read(
                (context) =>
                    api.getVideoDetail(item.video.id.value, context: context),
                cancellation,
                scope,
                epoch,
              )).aid;
          final tracks = await _read(
            (context) =>
                api.getSubtitleTracks(aid, item.part.cid, context: context),
            cancellation,
            scope,
            epoch,
          );
          if (tracks.length > 16) warnings.add('字幕轨道超过 16 条，仅保存前 16 条');
          var totalCues = 0;
          var totalTextBytes = 0;
          for (final track in tracks.take(16)) {
            _check(cancellation, scope, epoch);
            try {
              final cues = await _read(
                (context) => api.getSubtitleCues(track.url, context: context),
                cancellation,
                scope,
                epoch,
              );
              final cueBytes = cues.fold<int>(
                0,
                (sum, cue) => sum + utf8.encode(cue.text).length + 128,
              );
              if (cues.any((cue) => cue.text.length > 4096) ||
                  cues.length > 4000 ||
                  totalCues + cues.length > 20000 ||
                  totalTextBytes + cueBytes > 2 * 1024 * 1024 ||
                  cueBytes > encodedBudget) {
                warnings.add('字幕内容超过离线保存上限，已跳过「${track.label}」');
                continue;
              }
              subtitles.add(
                DownloadedSubtitle(
                  label: track.label,
                  cues: cues
                      .map((cue) => SubtitleCue(cue.start, cue.end, cue.text))
                      .toList(),
                ),
              );
              totalCues += cues.length;
              totalTextBytes += cueBytes;
              encodedBudget -= cueBytes;
            } catch (error) {
              _check(cancellation, scope, epoch);
              warnings.add('字幕「${track.label}」保存失败：${_reason(error)}');
            }
          }
        } catch (error) {
          _check(cancellation, scope, epoch);
          warnings.add('字幕列表获取失败：${_reason(error)}');
        }
      }
      if (selection.includeDanmaku) {
        final duration = item.part.duration > Duration.zero
            ? item.part.duration
            : item.video.duration;
        final segments = ((duration.inMilliseconds + 359999) ~/ 360000).clamp(
          1,
          120,
        );
        if (duration > const Duration(hours: 12)) {
          warnings.add('视频弹幕超过 120 段，仅保存前 120 段');
        }
        var capacityReached = false;
        for (var segment = 1; segment <= segments; segment++) {
          _check(cancellation, scope, epoch);
          try {
            final entries = await _read(
              (context) => api.getDanmakuSegment(
                item.part.cid,
                segment,
                context: context,
              ),
              cancellation,
              scope,
              epoch,
            );
            if (entries.length > 6000) {
              warnings.add('第 $segment 段弹幕超过 6000 条，仅保存前 6000 条');
            }
            var skippedLongComment = false;
            for (final entry in entries.take(6000)) {
              if (comments.length >= 60000) break;
              if (!const [1, 4, 5].contains(entry.mode)) continue;
              if (entry.content.length > 512) {
                skippedLongComment = true;
                continue;
              }
              final cost = utf8.encode(entry.content).length + 192;
              if (cost > encodedBudget) {
                capacityReached = true;
                break;
              }
              encodedBudget -= cost;
              comments.add(
                TimedComment(
                  id: entry.id,
                  position: entry.progress,
                  text: entry.content,
                  mode: entry.mode,
                  color: entry.color,
                  fontSize: entry.fontSize.toDouble(),
                  weight: entry.weight,
                ),
              );
            }
            if (skippedLongComment) {
              warnings.add('第 $segment 段存在过长弹幕，已跳过');
            }
            if (capacityReached || comments.length >= 60000) {
              warnings.add(
                capacityReached
                    ? '弹幕超过离线保存容量上限，后续弹幕未保存'
                    : '弹幕超过 60000 条，仅保存前 60000 条',
              );
              break;
            }
          } catch (error) {
            _check(cancellation, scope, epoch);
            warnings.add('第 $segment 段弹幕获取失败：${_reason(error)}');
          }
        }
      }
      _check(cancellation, scope, epoch);
      return DownloadExtras(
        cover: cover,
        subtitles: subtitles,
        comments: comments,
        warnings: warnings,
      );
    } finally {
      release();
    }
  }

  static String _reason(Object error) => switch (error) {
    AppFailure(:final message) => message,
    _ => '网络或内容格式异常',
  };

  Future<Uint8List> _cover(
    Uri url,
    RequestCancellation cancellation,
    String scope,
    int epoch,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    cancellation.onCancel(() => client.close(force: true));
    try {
      var current = url;
      for (var redirect = 0; redirect <= 3; redirect++) {
        _check(cancellation, scope, epoch);
        if (current.scheme != 'https' ||
            !(current.host == 'hdslb.com' ||
                current.host.endsWith('.hdslb.com') ||
                current.host == 'bilibili.com' ||
                current.host.endsWith('.bilibili.com'))) {
          throw const AppFailure(AppFailureKind.protocol, '封面地址无效');
        }
        final request = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 10));
        request.followRedirects = false;
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        _check(cancellation, scope, epoch);
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) break;
          current = current.resolve(location);
          await response.drain<void>().timeout(const Duration(seconds: 2));
          continue;
        }
        if (response.statusCode != 200 ||
            response.contentLength > 4 * 1024 * 1024) {
          throw const AppFailure(AppFailureKind.network, '封面响应无效或超过 4 MiB');
        }
        final bytes = BytesBuilder(copy: false);
        Future<void> collect() async {
          await for (final chunk in response) {
            _check(cancellation, scope, epoch);
            if (bytes.length + chunk.length > 4 * 1024 * 1024) {
              throw const AppFailure(AppFailureKind.protocol, '封面超过 4 MiB');
            }
            bytes.add(chunk);
          }
        }

        await collect().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            client.close(force: true);
            throw const AppFailure(AppFailureKind.timeout, '封面读取超时');
          },
        );
        _check(cancellation, scope, epoch);
        return bytes.takeBytes();
      }
      throw const AppFailure(AppFailureKind.network, '封面重定向次数过多');
    } finally {
      client.close(force: true);
    }
  }
}

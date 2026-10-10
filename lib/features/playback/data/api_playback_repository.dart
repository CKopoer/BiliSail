import 'dart:async';
import 'dart:io';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../core/storage/image_byte_cache.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/app_failure.dart';
import '../domain/playback_repository.dart';
import 'dash_media_selection.dart';

class ApiPlaybackRepository
    implements
        PlaybackRepository,
        PlaybackMetadataRepository,
        VoicePlaybackRepository {
  ApiPlaybackRepository(
    this.api,
    this.requests, {
    this.cdnPreference,
    this.imageDimensions,
  });
  final BiliApiClient api;
  final ApiRequests requests;
  final Future<MediaCdnPreference> Function()? cdnPreference;
  final Future<({int width, int height})> Function(Uri)? imageDimensions;

  @override
  Future<PlaybackMetadata> metadata(
    VideoDetail video,
    VideoPart part, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final aid =
        video.aid ??
        (await api.getVideoDetail(
          video.summary.id.value,
          context: context,
        )).aid;
    final data = await PlaybackMetadataClient(api)
        .load(aid, part.cid, context: context);
    return PlaybackMetadata(
      subtitles: List.unmodifiable(data.subtitles.map(_subtitle)),
      chapters: List.unmodifiable(
        data.chapters.map(
          (c) => VideoChapter(start: c.start, end: c.end, title: c.title),
        ),
      ),
      subtitleFailure: switch (data.subtitleFailure) {
        final failure? => mapApiFailure(failure),
        null => null,
      },
      chapterFailure: switch (data.chapterFailure) {
        final failure? => mapApiFailure(failure),
        null => null,
      },
    );
  }, cancellation: cancellation);

  @override
  Future<VideoStoryboard?> storyboard(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final data = await PlaybackMetadataClient(api)
        .storyboard(video.value, cid, context: context);
    if (data == null) return null;
    var width = data.tileWidth;
    var height = data.tileHeight;
    if (data.needsImageDimensions) {
      final size = await _storyboardImageDimensions(data.images.first, context);
      // Every page uses the declared grid. Do not guess a standard tile size:
      // older PGC sheets can differ from newer videos and from one another.
      if (size.width % data.columns != 0 || size.height % data.rows != 0) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'video_storyboard');
      }
      final measuredWidth = size.width ~/ data.columns;
      final measuredHeight = size.height ~/ data.rows;
      if (measuredWidth < 1 ||
          measuredHeight < 1 ||
          measuredWidth > 4096 ||
          measuredHeight > 4096 ||
          (width != 0 && width != measuredWidth) ||
          (height != 0 && height != measuredHeight)) {
        throw const ApiFailure(ApiFailureCategory.protocol, 'video_storyboard');
      }
      width = measuredWidth;
      height = measuredHeight;
    }
    return VideoStoryboard(
      columns: data.columns,
      rows: data.rows,
      tileWidth: width,
      tileHeight: height,
      images: data.images,
      times: data.times,
    );
  }, cancellation: cancellation);

  Future<({int width, int height})> _storyboardImageDimensions(
    Uri image,
    ApiRequestContext context,
  ) async {
    const endpoint = 'video_storyboard';
    final loader = imageDimensions;
    if (loader == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final signal = context.cancellation;
    if (signal?.isCancelled == true) {
      throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
    }
    final remaining =
        context.deadline?.difference(DateTime.now()) ??
        const Duration(seconds: 25);
    if (remaining <= Duration.zero) {
      throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
    }
    try {
      // Cancelling this consumer must not abort a shared image-cache request
      // used by another widget. The cache owns its bounded transport lifetime.
      return await Future.any([
        loader(image),
        if (signal != null)
          signal.whenCancelled.then<({int width, int height})>((_) {
            throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
          }),
      ]).timeout(remaining);
    } on ApiFailure {
      rethrow;
    } on ImageLoadCancelled {
      throw const ApiFailure(ApiFailureCategory.cancelled, endpoint);
    } on TimeoutException {
      throw const ApiFailure(ApiFailureCategory.timeout, endpoint);
    } on SocketException {
      throw const ApiFailure(ApiFailureCategory.network, endpoint);
    } on HttpException {
      throw const ApiFailure(ApiFailureCategory.network, endpoint);
    } on Exception {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
  }

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => _resolve(
    video,
    cid,
    quality: quality,
    preferredCodec: preferredCodec,
    cancellation: cancellation,
    voice: const PlaybackVoice.original(),
  );

  @override
  Future<PlaybackMedia> resolveVoice(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) => _resolve(
    video,
    cid,
    quality: quality,
    preferredCodec: preferredCodec,
    cancellation: cancellation,
    voice: voice,
  );

  Future<PlaybackMedia> _resolve(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final info = await api.getPlayInfo(
      video.value,
      cid,
      qn: quality,
      language: voice.languageCode,
      productionType: voice.productionType,
      context: context,
    );
    if (!voice.isOriginal &&
        (info.currentLanguage != voice.languageCode ||
            info.productionType != voice.productionType ||
            !info.voices.any(
              (option) =>
                  option.languageCode == voice.languageCode &&
                  option.productionType == voice.productionType,
            ))) {
      throw const AppFailure(AppFailureKind.playback, '所选语音暂不可用，请切回原声');
    }
    return selectDashMedia(
      info,
      quality: quality,
      preferredCodec: preferredCodec,
      cdnPreference:
          await cdnPreference?.call() ?? MediaCdnPreference.automatic,
      headers: {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36',
      },
    );
  }, cancellation: cancellation);

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final comments = await api.getDanmakuSegment(
      cid,
      segment,
      context: context,
    );
    return comments
        .where((item) => const [1, 4, 5].contains(item.mode))
        .map(
          (item) => TimedComment(
            id: item.id,
            position: item.progress,
            text: item.content,
            mode: item.mode,
            color: item.color,
            fontSize: item.fontSize.toDouble(),
            weight: item.weight,
          ),
        )
        .toList(growable: false);
  }, cancellation: cancellation);

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final detail = await api.getVideoDetail(video.value, context: context);
    final tracks = await api.getSubtitleTracks(
      detail.aid,
      cid,
      context: context,
    );
    return tracks.map(_subtitle).toList(growable: false);
  }, cancellation: cancellation);

  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final cues = await api.getSubtitleCues(track.uri, context: context);
    return cues
        .map((cue) => SubtitleCue(cue.start, cue.end, cue.text))
        .toList(growable: false);
  }, cancellation: cancellation);

  static SubtitleTrack _subtitle(ApiSubtitleTrack track) => SubtitleTrack(
    track.label,
    track.url,
    id: track.id,
    languageCode: track.languageCode,
    type: track.type,
    aiType: track.aiType,
    aiStatus: track.aiStatus,
  );
}

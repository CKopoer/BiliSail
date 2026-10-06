import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/media_cdn.dart';
import '../domain/playback_repository.dart';
import 'dash_media_selection.dart';

class ApiPlaybackRepository
    implements PlaybackRepository, PlaybackMetadataRepository {
  ApiPlaybackRepository(this.api, this.requests, {this.cdnPreference});
  final BiliApiClient api;
  final ApiRequests requests;
  final Future<MediaCdnPreference> Function()? cdnPreference;

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
      subtitles: List.unmodifiable(
        data.subtitles.map((s) => SubtitleTrack(s.label, s.url)),
      ),
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
    return VideoStoryboard(
      columns: data.columns,
      rows: data.rows,
      tileWidth: data.tileWidth,
      tileHeight: data.tileHeight,
      images: data.images,
      times: data.times,
    );
  }, cancellation: cancellation);

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final info = await api.getPlayInfo(
      video.value,
      cid,
      qn: quality,
      context: context,
    );
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
    return tracks
        .map((track) => SubtitleTrack(track.label, track.url))
        .toList(growable: false);
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
}

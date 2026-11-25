import 'package:bili_player/bili_player.dart';

import '../../../domain/app_failure.dart';
import '../domain/playback_repository.dart';

/// Selects the actual CDN line and media tracks for one resolved request.
({ResolvedMediaSource source, int liveLineIndex}) selectPlaybackSource(
  PlaybackMedia resolved, {
  required bool requestedAudioOnly,
  required bool isLive,
  required int requestedLiveLine,
}) {
  final policy = MediaRequestPolicy(headers: resolved.headers);
  final audio = resolved.audio;
  final audioUri = audio?.urls.firstOrNull;
  final audioTrack = audio != null && audioUri != null
      ? MediaTrack(
          uri: audioUri,
          requestPolicy: policy,
          codec: audio.codec,
          bandwidth: audio.bandwidth,
        )
      : null;
  if (requestedAudioOnly) {
    if (isLive ||
        resolved.kind != PlaybackMediaKind.dash ||
        audioTrack == null) {
      throw const AppFailure(AppFailureKind.playback, '当前内容没有独立音轨，请返回视频播放');
    }
    return (
      source: ProgressiveSource(audioTrack, isAudioOnly: true),
      liveLineIndex: 0,
    );
  }
  if (resolved.video.urls.isEmpty) {
    throw const AppFailure(AppFailureKind.playback, '未取得视频播放地址');
  }
  if (resolved.kind == PlaybackMediaKind.dash &&
      audioTrack == null &&
      !resolved.isIntentionallySilent) {
    throw const AppFailure(AppFailureKind.playback, '未取得点播音频轨道');
  }
  // Live lines follow url_info order, independently of VOD CDN preferences.
  final liveLineIndex =
      isLive &&
          requestedLiveLine >= 0 &&
          requestedLiveLine < resolved.video.urls.length
      ? requestedLiveLine
      : 0;
  final video = MediaTrack(
    uri: resolved.video.urls[liveLineIndex],
    requestPolicy: policy,
    codec: resolved.video.codec,
    embeddedAudioCodec: resolved.video.embeddedAudioCodec,
    bandwidth: resolved.video.bandwidth,
    isHdr: resolved.isHdr,
  );
  final source = switch (resolved.kind) {
    PlaybackMediaKind.dash => DashPairSource(
      video: video,
      audio: audioTrack,
      isIntentionallySilent: resolved.isIntentionallySilent,
      duration: resolved.duration,
    ),
    PlaybackMediaKind.liveHls => ManifestSource(video, isLive: true),
    PlaybackMediaKind.liveFlv ||
    PlaybackMediaKind.progressive => ProgressiveSource(video, isLive: isLive),
  };
  return (source: source, liveLineIndex: liveLineIndex);
}

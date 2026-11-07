import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'native_audio_gain.dart';
import 'player_contract.dart';

double fsPlayerGainAmplitude(double gainDb) =>
    math.pow(10, gainDb / 20).toDouble();

/// An ephemeral native input. Its contents include URLs and must not be logged.
final class FsPlayerInput {
  const FsPlayerInput(
    this.url,
    this.headers, {
    required this.video,
    required this.audio,
    required this.live,
    this.duration,
  });
  final String url;
  final Map<String, String> headers;
  final bool video, audio, live;
  final Duration? duration;
}

FsPlayerInput fsPlayerInput(ResolvedMediaSource source, OpenOptions options) {
  if (options.startPosition < Duration.zero ||
      options.openTimeout <= Duration.zero ||
      !options.rate.isFinite ||
      options.rate <= 0 ||
      !options.volume.isFinite ||
      options.volume < 0 ||
      options.volume > 100 ||
      !NativeAudioGain.valid(options.audioGainDb) ||
      options.maxBufferAhead <= Duration.zero ||
      options.maxBufferAhead > OpenOptions.maximumBufferAhead) {
    throw const PlayerFailure(PlayerFailureKind.invalidSource, '无效的播放参数', 0);
  }
  final (main, audio, video, live) = switch (source) {
    DashPairSource(:final video, :final audio) => (video, audio, true, false),
    DashVideoSource(:final video) => (video, null, true, false),
    ProgressiveSource(:final media, :final isAudioOnly, :final isLive) => (
      media,
      null,
      !isAudioOnly,
      isLive,
    ),
    ManifestSource(:final media, :final isLive) => (media, null, true, isLive),
  };
  if (RegExp(
    r'^(dvh1|dvhe)\.0?5\.',
    caseSensitive: false,
  ).hasMatch(main.codec ?? '')) {
    throw const PlayerFailure(
      PlayerFailureKind.unsupportedVideoColor,
      'fsplayer 开源版不支持杜比视界 Profile 5',
      0,
    );
  }
  if (source is DashPairSource &&
      audio == null &&
      !source.isIntentionallySilent) {
    throw const PlayerFailure(PlayerFailureKind.invalidSource, 'DASH 音轨缺失', 0);
  }
  if (source is DashVideoSource && options.volume != 0) {
    throw const PlayerFailure(PlayerFailureKind.invalidSource, '无音轨预览必须静音', 0);
  }
  Map<String, String> headers(MediaTrack track) {
    final result = <String, String>{};
    for (final entry in track.requestPolicy.headers.entries) {
      final key = entry.key.toLowerCase();
      if (!{'user-agent', 'referer', 'origin', 'accept'}.contains(key) ||
          entry.value.contains(RegExp(r'[\r\n]')) ||
          result.containsKey(key)) {
        throw const PlayerFailure(
          PlayerFailureKind.unsupportedHeaders,
          '不支持的媒体请求头',
          0,
        );
      }
      result[key] = entry.value;
    }
    return result;
  }

  String url(MediaTrack track) {
    final uri = track.uri;
    if (uri.scheme == 'fd' && Platform.isAndroid) {
      final fd = int.tryParse(uri.host);
      if (fd != null && fd >= 0) return '/proc/self/fd/$fd';
    }
    if (!{'http', 'https', 'file'}.contains(uri.scheme) ||
        (uri.scheme != 'file' &&
            (uri.host.isEmpty || uri.userInfo.isNotEmpty))) {
      throw const PlayerFailure(PlayerFailureKind.invalidSource, '不支持的媒体地址', 0);
    }
    return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
  }

  final first = headers(main);
  final mainUrl = url(main);
  if (audio == null) {
    return FsPlayerInput(
      mainUrl,
      first,
      video: video,
      audio: source is! DashVideoSource && source is! DashPairSource,
      live: live,
    );
  }
  final second = headers(audio);
  if (first.length != second.length ||
      first.entries.any((entry) => second[entry.key] != entry.value)) {
    throw const PlayerFailure(
      PlayerFailureKind.unsupportedHeaders,
      'fsplayer 暂不支持不同的分轨请求头',
      0,
    );
  }
  final duration = (source as DashPairSource).duration;
  if (duration == null || duration <= Duration.zero) {
    throw const PlayerFailure(
      PlayerFailureKind.invalidSource,
      'fsplayer DASH 分轨需要有效时长',
      0,
    );
  }
  String xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  String manifestUrl(MediaTrack track) => switch (track.uri.scheme) {
    'file' => track.uri.toString(),
    'fd' => 'file://${url(track)}',
    _ => url(track),
  };
  final manifest =
      '<?xml version="1.0"?>'
      '<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" '
      'mediaPresentationDuration="PT${duration.inMicroseconds / 1000000}S" '
      'minBufferTime="PT1S" profiles="urn:mpeg:dash:profile:isoff-on-demand:2011">'
      '<Period><AdaptationSet contentType="video" mimeType="video/mp4">'
      '<Representation id="v" bandwidth="${main.bandwidth ?? 1}">'
      '<BaseURL>${xml(manifestUrl(main))}</BaseURL>'
      '<SegmentList timescale="1000" duration="${duration.inMilliseconds}">'
      '<SegmentURL media="${xml(manifestUrl(main))}"/></SegmentList>'
      '</Representation></AdaptationSet>'
      '<AdaptationSet contentType="audio" mimeType="audio/mp4">'
      '<Representation id="a" bandwidth="${audio.bandwidth ?? 1}">'
      '<BaseURL>${xml(manifestUrl(audio))}</BaseURL>'
      '<SegmentList timescale="1000" duration="${duration.inMilliseconds}">'
      '<SegmentURL media="${xml(manifestUrl(audio))}"/></SegmentList>'
      '</Representation></AdaptationSet></Period></MPD>';
  return FsPlayerInput(
    'data:application/dash+xml;base64,${base64Encode(utf8.encode(manifest))}',
    first,
    video: true,
    audio: true,
    live: false,
    duration: duration,
  );
}

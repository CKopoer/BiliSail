import 'dart:io';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const systemMediaPart = VideoPart(
  cid: '1',
  page: 1,
  title: '分 P',
  duration: Duration(seconds: 20),
);

VideoDetail systemMediaVideo(String title, {String cover = ''}) => VideoDetail(
  summary: VideoSummary(
    id: const VideoId('BV1GJ411x7h7'),
    title: title,
    coverUrl: cover,
    author: 'fixture',
    duration: const Duration(seconds: 20),
  ),
  description: '',
  parts: const [systemMediaPart],
);

class SystemMediaFixtureRepository extends Fake implements PlaybackRepository {
  SystemMediaFixtureRepository({this.directory});
  final String? directory;

  PlaybackMedia get media => PlaybackMedia(
    video: PlaybackTrack(
      urls: [
        directory == null
            ? Uri.https('example.test', '/video')
            : Directory(directory!).uri.resolve('video.mp4'),
      ],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [
        directory == null
            ? Uri.https('example.test', '/audio')
            : Directory(directory!).uri.resolve('audio.m4a'),
      ],
      codec: 'mp4a',
      bandwidth: 100,
    ),
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 20),
    headers: const {},
  );

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    int quality = 80,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => media;

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => const [];
}

class SystemMediaFixtureContent extends Fake
    implements ContentPlaybackRepository {
  SystemMediaFixtureContent(this.repository);
  final SystemMediaFixtureRepository repository;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => repository.media;
}

class SystemMediaFixtureProgress extends Fake implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}

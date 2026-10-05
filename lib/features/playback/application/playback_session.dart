import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/playback_repository.dart';
import '../domain/content_playback.dart';
import '../domain/sponsor_repository.dart';
import '../../settings/domain/app_settings.dart';

final playbackSessionProvider = Provider<PlaybackSession>(
  (ref) => throw UnimplementedError('PlaybackSession'),
);

/// One process-owned native engine. Metadata and frequent position notifications
/// are separate so a position sample never rebuilds a whole route.
class PlaybackSession extends ChangeNotifier {
  PlaybackSession({
    required this.engine,
    required this.repository,
    required this.progress,
    required this.accountScope,
    this.sponsorRepository,
    this.contentRepository,
    this.metadataRepository,
  }) {
    _clock.start();
    danmaku = DanmakuController(monotonicNow: () => _clock.elapsed);
    _subscriptions.add(engine.snapshots.listen(_onSnapshot));
    _subscriptions.add(
      engine.failures.listen((failure) {
        if (failure.generation != engine.currentSnapshot.generation ||
            _resolving) {
          return;
        }
        error = failure.message;
        _notify();
      }),
    );
  }

  final SponsorRepository? sponsorRepository;
  AppSettings _settings = const AppSettings.defaults();
  RequestCancellation? _sponsorCancellation;
  List<SponsorSegment> sponsorSegments = const [];
  final Set<String> _skippedSponsors = {};
  bool sponsorLoading = false;
  String? sponsorMessage;
  bool _sponsorSeeking = false;
  SponsorSegment? get currentSponsor =>
      _settings.sponsorBlockMode == SponsorBlockMode.disabled
      ? null
      : sponsorSegments
            .where(
              (segment) =>
                  segment.matches(snapshots.value.duration) &&
                  snapshots.value.position >= segment.start &&
                  snapshots.value.position < segment.end,
            )
            .firstOrNull;
  final PlayerEngine engine;
  final PlaybackRepository repository;
  final PlaybackMetadataRepository? metadataRepository;
  final ContentPlaybackRepository? contentRepository;
  final PlaybackProgressStore progress;
  final String Function() accountScope;
  final _clock = Stopwatch();
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _owners = <Object>{};
  final _checkpoints = <Object, _PlaybackCheckpoint>{};
  Object? _activeOwner;
  bool _ownerVisible = true;
  Duration? _openingPosition;
  double _openingRate = 1;
  double _openingVolume = 100;
  int _quality = 80;
  String? _subtitlePreference;
  final snapshots = ValueNotifier(
    const PlaybackSnapshot(phase: PlaybackPhase.idle, generation: 0),
  );
  late final DanmakuController danmaku;
  final _segments = <int, List<TimedComment>>{};
  final _segmentRequests = <int, RequestCancellation>{};
  final _failedSegments = <int>{};
  final _prefetchFailedSegments = <int>{};
  RequestCancellation? _sourceCancellation;
  RequestCancellation? _subtitleCancellation;
  int _generation = 0;
  int _subtitleGeneration = 0;
  bool _disposed = false;
  bool _closing = false;
  bool _resolving = false;
  bool _desiredPlaying = true;
  Duration _lastSaved = const Duration(seconds: -10);
  int _lastCommentWindow = -1;
  String _scope = 'guest';
  VideoDetail? detail;
  VideoPart? part;
  ContentPlaybackTarget? contentTarget;
  String? contentTitle;
  bool get isLive => contentTarget is LivePlaybackTarget;
  String get title => contentTitle ?? detail?.summary.title ?? '播放器';
  PlaybackMedia? media;
  String? error;
  String? auxiliaryMessage;
  List<SubtitleTrack> subtitleTracks = const [];
  List<SubtitleCue> subtitleCues = const [];
  List<VideoChapter> chapters = const [];
  VideoStoryboard? storyboard;
  bool storyboardLoading = false;
  bool _storyboardRequested = false;
  String? storyboardMessage;
  String? chaptersMessage;
  RequestCancellation? _storyboardCancellation;
  int selectedSubtitle = -1;
  bool commentsEnabled = true;
  double commentFontScale = 1;
  bool get isResolving => _resolving;
  int get sourceGeneration => _generation;
  String get sourceAccountScope => _scope;
  String? get danmakuCid => switch (contentTarget) {
    LivePlaybackTarget() => null,
    PgcPlaybackTarget(:final cid) => cid ?? part?.cid,
    _ => part?.cid,
  };

  /// The current media owner remains the same when its workspace tab is hidden.
  bool ownsPlayback(Object owner) =>
      !_disposed && _owners.contains(owner) && identical(_activeOwner, owner);

  void attach(Object owner) => _owners.add(owner);
  void _captureOwner() {
    final owner = _activeOwner;
    final selected = part;
    final video = detail;
    if (owner == null ||
        (contentTarget == null && (selected == null || video == null))) {
      return;
    }
    final saved = _checkpoints[owner];
    final previous =
        saved?.videoId == video?.summary.id &&
            saved?.cid == selected?.cid &&
            saved?.target == contentTarget
        ? saved
        : null;
    final snapshot = snapshots.value;
    // A failed preparation has no confirmed source: native idle snapshots
    // must not replace the position/preferences we were trying to restore.
    final preparing = media == null;
    _checkpoints[owner] = _PlaybackCheckpoint(
      videoId: video?.summary.id,
      cid: selected?.cid,
      target: contentTarget,
      scope: _scope,
      position: preparing
          ? _openingPosition ?? previous?.position
          : snapshot.position,
      rate:
          _temporaryRateOriginal ?? (preparing ? _openingRate : snapshot.rate),
      volume: preparing ? _openingVolume : snapshot.volume,
      quality: _quality,
      desiredPlaying: _desiredPlaying,
      subtitleLabel: _subtitlePreference,
    );
  }

  Future<void> activate(
    Object owner,
    VideoDetail? video,
    VideoPart? selected, {
    ContentPlaybackTarget? target,
    String? title,
  }) async {
    if (_disposed || !_owners.contains(owner)) return;
    if (identical(_activeOwner, owner) &&
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target &&
        _scope == accountScope() &&
        (media != null || _resolving)) {
      _ownerVisible = true;
      return;
    }
    final sameOwner = identical(_activeOwner, owner);
    final sameKind = contentTarget.runtimeType == target.runtimeType;
    _captureOwner();
    final saved = _checkpoints[owner];
    final restored =
        saved != null &&
            saved.scope == accountScope() &&
            saved.videoId == video?.summary.id &&
            saved.cid == selected?.cid &&
            saved.target == target
        ? saved
        : null;
    _activeOwner = owner;
    _ownerVisible = true;
    _subtitlePreference = restored?.subtitleLabel;
    await open(
      video,
      selected,
      force: true,
      quality:
          restored?.quality ??
          (sameOwner && sameKind ? _quality : null) ??
          (target is LivePlaybackTarget ? 10000 : _settings.preferredQuality),
      position: restored?.position,
      desiredPlaying:
          restored?.desiredPlaying ??
          (sameOwner ? _desiredPlaying : _settings.autoPlay),
      rate:
          restored?.rate ??
          (sameOwner
              ? _temporaryRateOriginal ?? snapshots.value.rate
              : _settings.defaultPlaybackRate),
      volume:
          restored?.volume ??
          (sameOwner ? snapshots.value.volume : _settings.defaultVolume),
      target: target,
      title: title,
    );
  }

  Future<void> deactivate(Object owner) async {
    if (!identical(_activeOwner, owner) || _disposed) return;
    // Visibility owns the surface and input, not playback intent. Keep the
    // active source running while browsing an ordinary workspace tab.
    _captureOwner();
    _ownerVisible = false;
    final generation = _generation;
    await endTemporaryRate();
    if (!identical(_activeOwner, owner) ||
        generation != _generation ||
        _disposed) {
      return;
    }
    await _saveProgress();
  }

  void detach(Object owner) {
    _owners.remove(owner);
    _checkpoints.remove(owner);
    if (_activeOwner == null) {
      scheduleMicrotask(() {
        if (!_disposed && _activeOwner == null && _owners.isEmpty) {
          unawaited(stop());
        }
      });
      return;
    }
    if (!identical(_activeOwner, owner) && _activeOwner != null) return;
    _activeOwner = null;
    _ownerVisible = false;
    scheduleMicrotask(() {
      if (!_disposed && _activeOwner == null) {
        unawaited(stop(clearCheckpoints: false));
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open(
    VideoDetail? video,
    VideoPart? selected, {
    int quality = 80,
    bool force = false,
    Duration? position,
    bool? desiredPlaying,
    double? rate,
    double? volume,
    ContentPlaybackTarget? target,
    String? title,
  }) async {
    if (_disposed || _closing) return;
    if (target == null && (video == null || selected == null)) return;
    if (!force &&
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target &&
        (_resolving || (error == null && media != null))) {
      return;
    }
    final generation = ++_generation;
    // Capture source settings together; a preference change during resolution
    // applies to the next open rather than half of this source generation.
    final preferredCodec = _settings.preferredVideoCodec;
    final videoDecoding = switch (_settings.videoDecoding) {
      VideoDecodingPreference.automatic => VideoDecodingMode.automatic,
      VideoDecodingPreference.software => VideoDecodingMode.software,
    };
    _sponsorCancellation?.cancel();
    sponsorSegments = const [];
    sponsorLoading = false;
    sponsorMessage = null;
    _skippedSponsors.clear();
    _sponsorSeeking = false;
    _sourceCancellation?.cancel();
    _subtitleCancellation?.cancel();
    for (final token in _segmentRequests.values) {
      token.cancel();
    }
    _segmentRequests.clear();
    _segments.clear();
    _failedSegments.clear();
    _prefetchFailedSegments.clear();
    _lastCommentWindow = -1;
    final savedProgress = _saveProgress();
    final cancellation = RequestCancellation();
    _sourceCancellation = cancellation;
    final samePart =
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target;
    if (desiredPlaying != null) {
      _desiredPlaying = desiredPlaying;
    } else if (!samePart) {
      _desiredPlaying = true;
      _subtitlePreference = null;
    }
    final oldRate = rate ?? _temporaryRateOriginal ?? snapshots.value.rate;
    _temporaryRateOriginal = null;
    _temporaryRateGeneration = null;
    _temporaryRateRevision++;
    final oldVolume = volume ?? snapshots.value.volume;
    _openingPosition = position;
    _openingRate = oldRate;
    _openingVolume = oldVolume;
    _quality = quality;
    detail = video;
    part = selected;
    contentTarget = target;
    contentTitle = title;
    media = null;
    error = null;
    auxiliaryMessage = null;
    subtitleTracks = const [];
    subtitleCues = const [];
    _clearTimeline();
    selectedSubtitle = -1;
    _scope = accountScope();
    _resolving = true;
    danmaku.replaceEvents(const []);
    _notify();
    try {
      await savedProgress;
      if (generation != _generation || _disposed) return;
      await engine.stop();
      if (generation != _generation) return;
      final contentResolver = contentRepository;
      final PlaybackMedia resolved;
      if (target != null) {
        if (contentResolver == null) {
          throw const AppFailure(AppFailureKind.playback, '内容播放服务未配置');
        }
        resolved = await contentResolver.resolve(
          target,
          quality: quality,
          preferredCodec: preferredCodec,
          cancellation: cancellation,
        );
      } else if (video != null && selected != null) {
        resolved = await repository.resolve(
          video.summary.id,
          selected.cid,
          quality: quality,
          preferredCodec: preferredCodec,
          cancellation: cancellation,
        );
      } else {
        return;
      }
      if (generation != _generation || _scope != accountScope()) return;
      final resume = isLive
          ? Duration.zero
          : position ??
                (_settings.resumePlayback && video != null && selected != null
                    ? await progress.read(
                        _scope,
                        video.summary.id,
                        selected.cid,
                      )
                    : Duration.zero);
      if (generation != _generation) return;
      final policy = MediaRequestPolicy(headers: resolved.headers);
      _openingPosition = resume;
      PlayerFailure? lastFailure;
      final audio = resolved.audio;
      if (resolved.kind == PlaybackMediaKind.dash && audio == null) {
        throw const AppFailure(AppFailureKind.playback, '未取得点播音频轨道');
      }
      // At most two opens in one resolution, using only server-provided backups.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (generation != _generation) return;
        try {
          await engine.open(
            resolved.kind == PlaybackMediaKind.liveHls
                ? ManifestSource(
                    MediaTrack(
                      uri:
                          resolved.video.urls[attempt.clamp(
                            0,
                            resolved.video.urls.length - 1,
                          )],
                      requestPolicy: policy,
                    ),
                    isLive: true,
                  )
                : resolved.kind == PlaybackMediaKind.liveFlv
                ? ProgressiveSource(
                    MediaTrack(
                      uri:
                          resolved.video.urls[attempt.clamp(
                            0,
                            resolved.video.urls.length - 1,
                          )],
                      requestPolicy: policy,
                    ),
                  )
                : DashPairSource(
                    video: MediaTrack(
                      uri:
                          resolved.video.urls[attempt.clamp(
                            0,
                            resolved.video.urls.length - 1,
                          )],
                      requestPolicy: policy,
                      codec: resolved.video.codec,
                      bandwidth: resolved.video.bandwidth,
                    ),
                    audio: audio == null
                        ? null
                        : MediaTrack(
                            uri: audio
                                .urls[attempt.clamp(0, audio.urls.length - 1)],
                            requestPolicy: policy,
                            codec: audio.codec,
                            bandwidth: audio.bandwidth,
                          ),
                  ),
            OpenOptions(
              startPosition: resume,
              play: false,
              rate: isLive ? 1 : oldRate,
              volume: oldVolume,
              videoDecoding: videoDecoding,
            ),
          );
          lastFailure = null;
          break;
        } on PlayerFailure catch (failure) {
          lastFailure = failure;
          if (resolved.video.urls.length < 2 && (audio?.urls.length ?? 0) < 2) {
            break;
          }
        }
      }
      if (lastFailure != null) throw lastFailure;
      if (generation != _generation) return;
      media = resolved;
      _resolving = false;
      danmaku.seekConfirmed(engine.currentSnapshot.position);
      if (_desiredPlaying) await engine.play();
      if (generation != _generation) return;
      _notify();
      _ensureComments(engine.currentSnapshot.position);
      if (!isLive && video != null && selected != null) {
        unawaited(
          _loadSubtitleTracks(generation, video, selected, cancellation),
        );
      }
      if (target == null) unawaited(_loadSponsorSegments());
    } on AppFailure catch (failure) {
      if (generation == _generation &&
          failure.kind != AppFailureKind.cancelled) {
        error = failure.message;
        _resolving = false;
        _notify();
      }
    } on PlayerFailure catch (failure) {
      if (generation == _generation) {
        error = failure.message;
        _resolving = false;
        _notify();
      }
    } catch (_) {
      if (generation == _generation) {
        error = '播放准备失败，请检查网络后重试';
        _resolving = false;
        _notify();
      }
    }
  }

  void _onSnapshot(PlaybackSnapshot value) {
    if (_disposed || value.generation != engine.currentSnapshot.generation) {
      return;
    }
    final enteredEnded =
        value.phase == PlaybackPhase.ended &&
        snapshots.value.phase != PlaybackPhase.ended;
    snapshots.value = value;
    if (enteredEnded && !_resolving) {
      _desiredPlaying = false;
    }
    danmaku.sync(
      confirmedPosition: value.position,
      playing: value.phase == PlaybackPhase.playing,
      buffering: value.isBuffering,
      seeking: value.isSeeking,
      rate: value.rate,
    );
    if (!_resolving && media != null) {
      _ensureComments(value.position);
      final sponsor = currentSponsor;
      if (_settings.sponsorBlockMode == SponsorBlockMode.automatic &&
          value.phase == PlaybackPhase.playing &&
          !value.isSeeking &&
          !value.isBuffering &&
          sponsor != null &&
          !_skippedSponsors.contains(sponsor.id) &&
          !_sponsorSeeking) {
        final sourceGeneration = _generation;
        // Native adapters may emit synchronously inside seek. Defer commands
        // until the current position event finishes, then recheck the source.
        scheduleMicrotask(() {
          if (!_disposed &&
              sourceGeneration == _generation &&
              identical(currentSponsor, sponsor) &&
              _settings.sponsorBlockMode == SponsorBlockMode.automatic &&
              snapshots.value.phase == PlaybackPhase.playing &&
              !snapshots.value.isSeeking &&
              !snapshots.value.isBuffering) {
            unawaited(skipSponsor(sponsor));
          }
        });
      }
      if (_clock.elapsed - _lastSaved >= const Duration(seconds: 5)) {
        _lastSaved = _clock.elapsed;
        unawaited(_saveProgress());
      }
    }
  }

  Future<void> _saveProgress() async {
    final generation = _generation;
    final video = detail;
    final selected = part;
    final snapshot = snapshots.value;
    final scope = _scope;
    if (isLive ||
        video == null ||
        selected == null ||
        media == null ||
        snapshot.duration <= Duration.zero) {
      return;
    }
    try {
      await progress.write(
        scope,
        video.summary,
        selected,
        snapshot.position,
        snapshot.duration,
        episodeId: switch (contentTarget) {
          PgcPlaybackTarget(:final episodeId) => episodeId,
          _ => null,
        },
      );
    } catch (_) {
      if (generation == _generation && !_closing) {
        auxiliaryMessage = '本地进度保存失败，本次仍可继续播放';
        _notify();
      }
    }
  }

  /// Only the visible owner applies settings to the shared engine.
  void configureSettings(AppSettings settings) {
    final previous = _settings;
    _settings = settings.normalized();
    danmaku.configure(
      area: _settings.danmakuArea,
      speed: _settings.danmakuSpeed,
      topInset: _settings.danmakuTopMargin,
      offset: _settings.danmakuOffset,
      mergeDuplicates: _settings.danmakuMergeDuplicates,
      maxOnScreen: _settings.danmakuMaxOnScreen,
      textStyle: DanmakuTextStyle(
        fontFamily: _settings.danmakuFont == DanmakuFontPreference.harmonyOsSans
            ? 'HarmonyOS Sans'
            : null,
        bold: _settings.danmakuBold,
        effect: switch (_settings.danmakuStyle) {
          DanmakuStylePreference.shadow => DanmakuTextEffect.shadow,
          DanmakuStylePreference.stroke => DanmakuTextEffect.stroke,
          DanmakuStylePreference.plain => DanmakuTextEffect.plain,
        },
      ),
    );
    configureComments(
      enabled: _settings.danmakuEnabled,
      fontScale: _settings.danmakuFontScale,
    );
    _refreshCommentWindow(snapshots.value.position);
    if (previous.danmakuOffset != _settings.danmakuOffset) {
      _lastCommentWindow = -1;
      _ensureComments(snapshots.value.position);
    }
    if (media != null) {
      if (previous.defaultPlaybackRate != _settings.defaultPlaybackRate) {
        unawaited(setRate(_settings.defaultPlaybackRate));
      }
      if (previous.defaultVolume != _settings.defaultVolume) {
        unawaited(setVolume(_settings.defaultVolume));
      }
      if (previous.subtitlesEnabled != _settings.subtitlesEnabled) {
        unawaited(
          selectSubtitle(
            _settings.subtitlesEnabled && subtitleTracks.isNotEmpty ? 0 : -1,
          ),
        );
      }
      if (previous.sponsorBlockMode != _settings.sponsorBlockMode ||
          previous.sponsorBlockCategories.join(',') !=
              _settings.sponsorBlockCategories.join(',')) {
        unawaited(_loadSponsorSegments());
      }
    }
  }

  Future<void> _loadSponsorSegments() async {
    _sponsorCancellation?.cancel();
    sponsorSegments = const [];
    sponsorMessage = null;
    sponsorLoading = false;
    final repository = sponsorRepository;
    final video = detail;
    final selected = part;
    if (_settings.sponsorBlockMode == SponsorBlockMode.disabled ||
        repository == null ||
        video == null ||
        selected == null ||
        media == null) {
      _notify();
      return;
    }
    final generation = _generation;
    final token = RequestCancellation();
    _sponsorCancellation = token;
    sponsorLoading = true;
    _notify();
    try {
      final result = await repository.segments(
        video.summary.id,
        selected.cid,
        categories: _settings.sponsorBlockCategories,
        cancellation: token,
      );
      if (_disposed || token.isCancelled || generation != _generation) return;
      sponsorSegments = List.unmodifiable(
        result
            .where((item) => item.matches(media?.duration ?? Duration.zero))
            .take(512),
      );
      sponsorMessage = sponsorSegments.isEmpty ? '当前视频没有可跳过片段' : null;
    } catch (_) {
      if (_disposed || token.isCancelled || generation != _generation) return;
      sponsorMessage = '空降助手暂时不可用，视频播放不受影响';
    } finally {
      if (!_disposed &&
          identical(_sponsorCancellation, token) &&
          generation == _generation) {
        sponsorLoading = false;
        _notify();
      }
    }
  }

  Future<void> skipSponsor(SponsorSegment segment) async {
    final generation = _generation;
    if (_disposed ||
        _resolving ||
        (!_ownerVisible &&
            _settings.sponsorBlockMode != SponsorBlockMode.automatic) ||
        _sponsorSeeking ||
        _settings.sponsorBlockMode == SponsorBlockMode.disabled ||
        !sponsorSegments.contains(segment) ||
        !segment.matches(snapshots.value.duration)) {
      return;
    }
    _skippedSponsors.add(segment.id);
    _sponsorSeeking = true;
    try {
      await engine.seek(segment.end);
      if (_disposed || generation != _generation) return;
      danmaku.seekConfirmed(engine.currentSnapshot.position);
      _lastCommentWindow = -1;
      _ensureComments(engine.currentSnapshot.position);
      sponsorMessage = '已跳过${sponsorCategoryLabel(segment.category)}';
      _notify();
    } on PlayerFailure {
      if (generation == _generation && !_disposed) {
        sponsorMessage = '跳过失败，可手动调整进度';
        _notify();
      }
    } finally {
      if (generation == _generation) _sponsorSeeking = false;
    }
  }

  void configureComments({required bool enabled, required double fontScale}) {
    final changed = commentsEnabled != enabled || commentFontScale != fontScale;
    commentsEnabled = enabled;
    commentFontScale = fontScale;
    if (changed) {
      _lastCommentWindow = -1;
      if (enabled) _ensureComments(snapshots.value.position);
    }
  }

  void _ensureComments(Duration position) {
    final cid = danmakuCid;
    if (!commentsEnabled || cid == null || _resolving || media == null) {
      return;
    }
    final displayPosition = position - _settings.danmakuOffset;
    final current = _commentSegmentAt(position);
    final resolvedDuration = media?.duration ?? Duration.zero;
    final partDuration = part?.duration ?? Duration.zero;
    final snapshotDuration = snapshots.value.duration;
    final duration = resolvedDuration > Duration.zero
        ? resolvedDuration
        : partDuration > Duration.zero
        ? partDuration
        : snapshotDuration;
    for (final entry in _segmentRequests.entries.toList()) {
      if ((entry.key - current).abs() > 1) {
        entry.value.cancel();
        _segmentRequests.remove(entry.key);
      }
    }
    _segments.removeWhere((segment, _) => (segment - current).abs() > 1);
    _failedSegments.removeWhere((segment) => (segment - current).abs() > 1);
    _prefetchFailedSegments.removeWhere(
      (segment) => (segment - current).abs() > 1,
    );
    for (final segment in [
      if (current > 1) current - 1,
      current,
      current + 1,
    ]) {
      if (duration > Duration.zero &&
          Duration(seconds: (segment - 1) * 360) >= duration) {
        continue;
      }
      if (segment == current) _prefetchFailedSegments.remove(segment);
      if (!_segments.containsKey(segment) &&
          !_segmentRequests.containsKey(segment) &&
          !_failedSegments.contains(segment) &&
          !_prefetchFailedSegments.contains(segment)) {
        unawaited(_loadComments(_generation, cid, segment));
      }
    }
    final window = displayPosition.inSeconds ~/ 15;
    if (window != _lastCommentWindow) {
      _lastCommentWindow = window;
      _refreshCommentWindow(position);
    }
  }

  Future<void> _loadComments(int generation, String cid, int segment) async {
    final token = RequestCancellation();
    _segmentRequests[segment] = token;
    try {
      final events = await repository.comments(
        cid,
        segment,
        cancellation: token,
      );
      if (generation != _generation || token.isCancelled) return;
      _segments[segment] = events.take(6000).toList(growable: false);
      _prefetchFailedSegments.remove(segment);
      _refreshCommentWindow(snapshots.value.position);
    } catch (failure) {
      if (generation == _generation && !token.isCancelled) {
        final current = _commentSegmentAt(snapshots.value.position);
        if (segment == current) {
          _failedSegments.add(segment);
          auxiliaryMessage = '弹幕暂时不可用，视频播放不受影响';
          _notify();
        } else {
          _prefetchFailedSegments.add(segment);
        }
      }
    } finally {
      if (identical(_segmentRequests[segment], token)) {
        _segmentRequests.remove(segment);
      }
    }
  }

  void _refreshCommentWindow(Duration position) {
    if (_disposed) return;
    final displayPosition = position - _settings.danmakuOffset;
    final events = _segments.values.expand((events) => events).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final density = <int, int>{};
    danmaku.replaceEvents(
      events
          .where(
            (event) =>
                event.position >=
                    displayPosition - const Duration(seconds: 16) &&
                event.position <= displayPosition + const Duration(seconds: 60),
          )
          .where((event) {
            final modeEnabled = switch (event.mode) {
              4 => _settings.danmakuBottomEnabled,
              5 => _settings.danmakuTopEnabled,
              _ => _settings.danmakuScrollEnabled,
            };
            if (!modeEnabled ||
                (_settings.danmakuBlockColored &&
                    (event.color & 0xffffff) != 0xffffff) ||
                (_settings.danmakuMinimumWeight > 0 &&
                    event.weight < _settings.danmakuMinimumWeight) ||
                _settings.danmakuBlockedWords.any(
                  (word) => word.isNotEmpty && event.text.contains(word),
                )) {
              return false;
            }
            final second = event.position.inSeconds;
            final count = (density[second] ?? 0) + 1;
            density[second] = count;
            return _settings.danmakuMaxPerSecond == 0 ||
                count <= _settings.danmakuMaxPerSecond;
          })
          .map(
            (event) => DanmakuEvent(
              id: event.id,
              at: event.position,
              text: event.text,
              mode: switch (event.mode) {
                4 => DanmakuMode.bottom,
                5 => DanmakuMode.top,
                _ => DanmakuMode.scroll,
              },
              color: Color(0xff000000 | event.color),
              fontSize: event.fontSize.clamp(12, 36) * commentFontScale,
            ),
          ),
    );
  }

  int _commentSegmentAt(Duration playerPosition) {
    final seconds = (playerPosition - _settings.danmakuOffset).inSeconds;
    return (seconds < 0 ? 0 : seconds) ~/ 360 + 1;
  }

  Future<void> _loadSubtitleTracks(
    int generation,
    VideoDetail video,
    VideoPart selected,
    RequestCancellation token,
  ) async {
    try {
      final List<SubtitleTrack> tracks;
      if (metadataRepository case final repository?) {
        final metadata = await repository.metadata(
          video,
          selected,
          cancellation: token,
        );
        if (!_acceptMetadata(generation, token)) return;
        chapters = normalizeChapters(
          metadata.chapters,
          media?.duration ?? selected.duration,
        );
        chaptersMessage = metadata.chapterFailure?.message;
        tracks = metadata.subtitles;
      } else {
        tracks = await repository.subtitles(
          video.summary.id,
          selected.cid,
          cancellation: token,
        );
      }
      if (!_acceptMetadata(generation, token)) return;
      subtitleTracks = tracks;
      final preference = _subtitlePreference;
      _notify();
      if (preference == null &&
          _settings.subtitlesEnabled &&
          tracks.isNotEmpty) {
        await selectSubtitle(0);
      } else if (preference != null) {
        final index = tracks.indexWhere((track) => track.label == preference);
        if (index >= 0) await selectSubtitle(index);
      }
    } on AppFailure catch (failure) {
      if (!_acceptMetadata(generation, token) ||
          failure.kind == AppFailureKind.cancelled) {
        return;
      }
      chaptersMessage = failure.message;
      _notify();
    }
  }

  bool _acceptMetadata(int generation, RequestCancellation token) =>
      !_disposed &&
      !_closing &&
      generation == _generation &&
      !token.isCancelled &&
      _scope == accountScope();

  void _clearTimeline() {
    _storyboardCancellation?.cancel();
    _storyboardCancellation = null;
    chapters = const [];
    chaptersMessage = null;
    storyboard = null;
    storyboardLoading = false;
    storyboardMessage = null;
    _storyboardRequested = false;
  }

  /// Hover loads only metadata/images; the active engine never seeks for preview.
  Future<void> ensureStoryboard() async {
    final repository = metadataRepository;
    final video = detail?.summary.id;
    final cid = danmakuCid;
    if (_disposed ||
        _closing ||
        isLive ||
        media == null ||
        repository == null ||
        video == null ||
        cid == null ||
        _storyboardRequested) {
      return;
    }
    _storyboardRequested = true;
    storyboardLoading = true;
    final generation = _generation;
    final token = RequestCancellation();
    _storyboardCancellation = token;
    _notify();
    try {
      final result = await repository.storyboard(
        video,
        cid,
        cancellation: token,
      );
      if (!_acceptMetadata(generation, token)) return;
      storyboard = result;
    } on AppFailure catch (failure) {
      if (!_acceptMetadata(generation, token) ||
          failure.kind == AppFailureKind.cancelled) {
        return;
      }
      storyboardMessage = '缩略图暂时不可用';
    } finally {
      if (_acceptMetadata(generation, token)) {
        storyboardLoading = false;
        _notify();
      }
    }
  }

  Future<void> selectSubtitle(int index) async {
    final sourceGeneration = _generation;
    final generation = ++_subtitleGeneration;
    _subtitleCancellation?.cancel();
    selectedSubtitle = index;
    _subtitlePreference = index >= 0 && index < subtitleTracks.length
        ? subtitleTracks[index].label
        : '__off__';
    subtitleCues = const [];
    _notify();
    if (index < 0 || index >= subtitleTracks.length) return;
    final token = RequestCancellation();
    _subtitleCancellation = token;
    try {
      final cues = await repository.subtitleCues(
        subtitleTracks[index],
        cancellation: token,
      );
      if (generation != _subtitleGeneration ||
          sourceGeneration != _generation) {
        return;
      }
      subtitleCues = cues;
      _notify();
    } catch (_) {
      if (generation != _subtitleGeneration ||
          sourceGeneration != _generation) {
        return;
      }
      auxiliaryMessage = '字幕加载失败，请重新选择';
      _notify();
    }
  }

  Future<void> togglePlaying() async {
    if (snapshots.value.phase == PlaybackPhase.ended && !_resolving) {
      if (isLive) {
        _desiredPlaying = true;
        await retry();
        return;
      }
      final generation = _generation;
      _desiredPlaying = true;
      try {
        await engine.seek(Duration.zero);
        if (_disposed || generation != _generation) return;
        danmaku.seekConfirmed(engine.currentSnapshot.position);
        _lastCommentWindow = -1;
        _ensureComments(engine.currentSnapshot.position);
        await engine.play();
        if (_disposed || generation != _generation) return;
        await _saveProgress();
      } on PlayerFailure catch (failure) {
        if (generation == _generation && !_disposed) {
          error = failure.message;
          _notify();
        }
      }
      return;
    }
    _desiredPlaying = !_desiredPlaying;
    if (_resolving) {
      _notify();
      return;
    }
    await _command(_desiredPlaying ? engine.play : engine.pause);
    await _saveProgress();
  }

  Future<void> pause() async {
    _desiredPlaying = false;
    await _command(engine.pause);
  }

  Future<void> seek(Duration target) async {
    if (isLive) return;
    await _command(() => engine.seek(target));
    danmaku.seekConfirmed(engine.currentSnapshot.position);
    _lastCommentWindow = -1;
    _ensureComments(engine.currentSnapshot.position);
    await _saveProgress();
  }

  double? _temporaryRateOriginal;
  int? _temporaryRateGeneration;
  int _temporaryRateRevision = 0;
  Future<void> beginTemporaryRate(double rate) {
    if (isLive) return Future.value();
    _temporaryRateOriginal ??= snapshots.value.rate;
    _temporaryRateGeneration = snapshots.value.generation;
    _temporaryRateRevision++;
    return _command(() => engine.setRate(rate));
  }

  Future<void> endTemporaryRate({int? expectedGeneration}) async {
    if (expectedGeneration != null &&
        expectedGeneration != _temporaryRateGeneration) {
      return;
    }
    final rate = _temporaryRateOriginal;
    final sameSource = _temporaryRateGeneration == snapshots.value.generation;
    final revision = ++_temporaryRateRevision;
    // A source switch can capture a checkpoint before this native command
    // completes. Keep its permanent rate available throughout restoration.
    if (rate != null && sameSource) await setRate(rate);
    if (_temporaryRateRevision == revision) {
      _temporaryRateOriginal = null;
      _temporaryRateGeneration = null;
    }
  }

  Future<void> setRate(double rate) =>
      isLive ? Future.value() : _command(() => engine.setRate(rate));
  Future<void> setVolume(double volume) =>
      _command(() => engine.setVolume(volume));
  Future<void> _command(Future<void> Function() action) async {
    final generation = _generation;
    try {
      await action();
    } on PlayerFailure catch (failure) {
      if (generation == _generation && !_disposed) {
        error = failure.message;
        _notify();
      }
    }
  }

  Future<void> changeQuality(int quality) async {
    final video = detail;
    final selected = part;
    if (contentTarget == null && (video == null || selected == null)) return;
    await open(
      video,
      selected,
      quality: quality,
      force: true,
      position: snapshots.value.position,
      target: contentTarget,
      title: contentTitle,
    );
  }

  Future<void> retry() async {
    final video = detail;
    final selected = part;
    if (contentTarget != null || (video != null && selected != null)) {
      await open(
        video,
        selected,
        force: true,
        quality: _quality,
        position: media == null ? _openingPosition : snapshots.value.position,
        rate:
            _temporaryRateOriginal ??
            (media == null ? _openingRate : snapshots.value.rate),
        volume: media == null ? _openingVolume : snapshots.value.volume,
        desiredPlaying: _desiredPlaying,
        target: contentTarget,
        title: contentTitle,
      );
    }
  }

  Future<void> stop({bool clearCheckpoints = true}) async {
    if (clearCheckpoints) _checkpoints.clear();
    _activeOwner = null;
    _openingPosition = null;
    _temporaryRateOriginal = null;
    _temporaryRateGeneration = null;
    _temporaryRateRevision++;
    _subtitlePreference = null;
    final generation = ++_generation;
    _clearTimeline();
    _sponsorCancellation?.cancel();
    sponsorSegments = const [];
    sponsorLoading = false;
    sponsorMessage = null;
    _skippedSponsors.clear();
    _sponsorSeeking = false;
    _sourceCancellation?.cancel();
    _subtitleCancellation?.cancel();
    for (final token in _segmentRequests.values) {
      token.cancel();
    }
    _segmentRequests.clear();
    // Capture the old progress before invalidating the source. A same-source
    // reopen during the write must advance generation instead of reusing it.
    final savedProgress = _saveProgress();
    media = null;
    _resolving = false;
    await savedProgress;
    if (generation != _generation || _disposed) return;
    contentTarget = null;
    contentTitle = null;
    error = null;
    await engine.stop();
    if (generation != _generation || _disposed) return;
    danmaku.replaceEvents(const []);
    _notify();
  }

  Future<void> close() async {
    if (_disposed || _closing) return;
    _closing = true;
    Object? firstError;
    StackTrace? firstStack;
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    await attempt(stop);
    _disposed = true;
    for (final subscription in _subscriptions) {
      await attempt(subscription.cancel);
    }
    await attempt(engine.dispose);
    await attempt(() async => snapshots.dispose());
    await attempt(() async => danmaku.dispose());
    _clock.stop();
    super.dispose();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }
}

final class _PlaybackCheckpoint {
  const _PlaybackCheckpoint({
    required this.videoId,
    required this.cid,
    required this.scope,
    required this.position,
    required this.rate,
    required this.volume,
    required this.quality,
    required this.desiredPlaying,
    this.subtitleLabel,
    this.target,
  });
  final VideoId? videoId;
  final String? cid;
  final ContentPlaybackTarget? target;
  final String scope;
  final Duration? position;
  final double rate;
  final double volume;
  final int quality;
  final bool desiredPlaying;
  final String? subtitleLabel;
}

String sponsorCategoryLabel(String category) => switch (category) {
  'sponsor' => '赞助广告',
  'intro' => '片头',
  'outro' => '片尾',
  'selfpromo' => '自我推广',
  'interaction' => '互动提醒',
  'preview' => '预告',
  _ => '标记片段',
};

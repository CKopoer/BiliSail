import 'media_command_pump.dart';

import 'dart:async';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/playback_repository.dart';
import '../domain/high_energy_trend.dart';
import '../domain/subtitle_cue_index.dart';
import '../domain/content_playback.dart';
import '../domain/comment_window.dart';
import '../domain/sponsor_repository.dart';
import '../domain/playback_history_repository.dart';
import 'playback_history_reporter.dart';
import 'playback_rate_memory.dart';
import 'playback_volume_memory.dart';
import 'playback_startup_diagnostics.dart';
import '../../settings/domain/app_settings.dart';

final playbackSessionProvider = Provider<PlaybackSession>(
  (ref) => throw UnimplementedError('PlaybackSession'),
  dependencies: const [],
);

/// One page-owned native engine. Metadata and frequent position notifications
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
    this.historyRepository,
    int Function()? sessionEpoch,
    Duration Function()? historyNow,
    Duration Function()? danmakuNow,
    this.startupNow,
    PlaybackRateMemory? rateMemory,
    PlaybackVolumeMemory? volumeMemory,
    PlaybackStartupDiagnostics? startupDiagnostics,
  }) : sessionEpoch = sessionEpoch ?? _zeroEpoch,
       startupDiagnostics = startupDiagnostics ?? PlaybackStartupDiagnostics(),
       _rateMemory = rateMemory ?? PlaybackRateMemory(),
       _volumeMemory = volumeMemory ?? PlaybackVolumeMemory() {
    _clock.start();
    final history = historyRepository;
    _historyReporter = history == null
        ? null
        : PlaybackHistoryReporter(
            repository: history,
            accountScope: accountScope,
            sessionEpoch: this.sessionEpoch,
            now: historyNow ?? () => _clock.elapsed,
            onResult: (generation, failure) {
              if (_disposed ||
                  generation != _generation ||
                  media == null ||
                  _scope != accountScope() ||
                  _epoch != this.sessionEpoch()) {
                return;
              }
              if (failure != null) {
                auxiliaryMessage = '云端进度上报失败，本地进度仍会保存';
                _notify();
              } else if (auxiliaryMessage == '云端进度上报失败，本地进度仍会保存') {
                auxiliaryMessage = null;
                _notify();
              }
            },
          );
    danmaku = DanmakuController(
      monotonicNow: danmakuNow ?? () => _clock.elapsed,
    );
    _subscriptions.add(engine.snapshots.listen(_onSnapshot));
    _subscriptions.add(
      engine.failures.listen((failure) {
        if (failure.generation != engine.currentSnapshot.generation ||
            _resolving ||
            _audioRecovery?.preparing == true) {
          return;
        }
        if (failure.kind == PlayerFailureKind.videoInterrupted &&
            _videoRecoveryGeneration != _generation &&
            media != null &&
            !isLive &&
            _desiredPlaying &&
            _playbackAllowed) {
          final generation = _generation;
          final engineGeneration = failure.generation;
          scheduleMicrotask(() {
            if (_disposed ||
                _closing ||
                generation != _generation ||
                engineGeneration != engine.currentSnapshot.generation ||
                _scope != accountScope() ||
                _epoch != this.sessionEpoch()) {
              return;
            }
            if (!_desiredPlaying || !_playbackAllowed) {
              error = failure.message;
              _notify();
              return;
            }
            // retry/open advances the source generation before its first
            // await. Carry the one-attempt limit into the replacement source.
            final recovery = retry();
            _videoRecoveryGeneration = _generation;
            unawaited(recovery);
          });
          return;
        }
        error = contentTarget is OfflinePlaybackTarget
            ? '本地视频播放失败，文件可能无法解码或已不可访问'
            : failure.message;
        _notify();
      }),
    );
  }

  final SponsorRepository? sponsorRepository;
  final PlaybackRateMemory _rateMemory;
  final PlaybackVolumeMemory _volumeMemory;
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
  int? _videoRecoveryGeneration;
  final PlaybackRepository repository;
  final PlaybackMetadataRepository? metadataRepository;
  final ContentPlaybackRepository? contentRepository;
  final PlaybackProgressStore progress;
  final PlaybackStartupDiagnostics startupDiagnostics;
  final PlaybackHistoryRepository? historyRepository;
  late final PlaybackHistoryReporter? _historyReporter;
  final int Function() sessionEpoch;
  static int _zeroEpoch() => 0;
  int _epoch = 0;
  final String Function() accountScope;
  final _clock = Stopwatch();
  final Duration Function()? startupNow;
  _PlaybackStartupRecovery? _audioRecovery;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _owners = <Object>{};
  final _checkpoints = <Object, _PlaybackCheckpoint>{};
  // Only media identity and local playback preferences are retained, never
  // resolved URLs. Closing the session or changing accounts clears this cache.
  final _navigationCheckpoints =
      <(VideoId?, String?, ContentPlaybackTarget?), _PlaybackCheckpoint>{};
  Object? _activeOwner;
  bool _ownerVisible = true;
  Duration? _openingPosition;
  double _openingRate = 1;
  double _openingVolume = 100;
  int _quality = 80;
  int _liveLine = 0;
  LiveStreamPreference _liveStreamPreference = LiveStreamPreference.automatic;
  LiveStreamPreference get liveStreamPreference => _liveStreamPreference;
  int get requestedQuality => _quality;

  /// Index in the selected live stream's server-ordered url_info list.
  int get liveLine => _liveLine;
  String? _subtitlePreference;
  PlaybackVoice _voice = const PlaybackVoice.original();
  List<PlaybackVoice> _voices = const [];
  final snapshots = ValueNotifier(
    const PlaybackSnapshot(phase: PlaybackPhase.idle, generation: 0),
  );
  late final DanmakuController danmaku;
  final _segments = <int, CommentSegment>{};
  bool _commentsConfigured = false;
  Object? _commentRefreshRequest;
  final _segmentRequests = <int, RequestCancellation>{};
  final _failedSegments = <int>{};
  final _prefetchFailedSegments = <int>{};
  RequestCancellation? _sourceCancellation;
  RequestCancellation? _cloudResumeCancellation;
  int _resumeRevision = 0;
  RequestCancellation? _subtitleCancellation;
  int _generation = 0;
  int _mediaGeneration = 0;
  int _subtitleGeneration = 0;
  bool _disposed = false;
  bool _closing = false;
  bool _resolving = false;
  bool _desiredPlaying = true;
  ({
    VideoId id,
    String? cid,
    bool playing,
    Duration? position,
    String scope,
    int epoch,
  })?
  _nextSourceIntent;
  bool _playbackAllowed = true;
  Future<void>? _playbackCommands;
  Duration _lastSaved = const Duration(seconds: -10);
  int? _lastCommentWindow;
  String _scope = 'guest';
  VideoDetail? detail;
  VideoPart? part;
  ContentPlaybackTarget? contentTarget;
  String? contentTitle;
  bool get isLive => contentTarget is LivePlaybackTarget;
  bool _audioOnly = false;
  bool get audioOnly => _audioOnly;
  bool get canListen =>
      !isLive &&
      media?.kind == PlaybackMediaKind.dash &&
      (media?.audio?.urls.isNotEmpty ?? false);
  String get title => contentTitle ?? detail?.summary.title ?? '播放器';
  PlaybackMedia? media;
  String? error;
  String? auxiliaryMessage;
  List<SubtitleTrack> subtitleTracks = const [];
  List<SubtitleCue> _subtitleCues = const [];
  List<SubtitleCue> get subtitleCues => _subtitleCues;
  SubtitleCueIndex _subtitleIndex = SubtitleCueIndex(const []);
  set subtitleCues(List<SubtitleCue> cues) {
    _subtitleCues = List.unmodifiable(cues);
    _subtitleIndex = SubtitleCueIndex(_subtitleCues);
  }

  SubtitleCue? subtitleAt(Duration position) => _subtitleIndex.at(position);

  @visibleForTesting
  int get subtitleLookupCount => _subtitleIndex.lookupCount;
  bool subtitleLoading = false;
  String? subtitleMessage;
  PlaybackVoice get selectedVoice => _voice;
  List<PlaybackVoice> get voiceTracks =>
      contentTarget == null && repository is VoicePlaybackRepository
      ? _voices
      : const [];
  List<VideoChapter> chapters = const [];
  VideoStoryboard? storyboard;
  bool storyboardLoading = false;
  bool _storyboardRequested = false;
  String? storyboardMessage;
  String? chaptersMessage;
  RequestCancellation? _storyboardCancellation;
  final highEnergy = ValueNotifier<HighEnergyTrend?>(null);
  final _highEnergySurfaces = <Object>{};
  RequestCancellation? _highEnergyCancellation;
  bool _chaptersConfirmedEmpty = false;
  bool _highEnergyRequested = false;

  Duration get _highEnergyDuration {
    final resolved = media?.duration ?? Duration.zero;
    if (resolved > Duration.zero) return resolved;
    final selected = part?.duration ?? Duration.zero;
    return selected > Duration.zero ? selected : snapshots.value.duration;
  }

  void setHighEnergySurfaceVisible(Object owner, bool visible) {
    if (_disposed || _closing) return;
    if (visible) {
      _highEnergySurfaces.add(owner);
      unawaited(ensureHighEnergy());
    } else {
      _highEnergySurfaces.remove(owner);
      if (_highEnergySurfaces.isEmpty) _cancelHighEnergy();
    }
  }

  void _cancelHighEnergy() {
    if (_highEnergyCancellation != null) {
      _highEnergyCancellation?.cancel();
      _highEnergyCancellation = null;
      _highEnergyRequested = false;
    }
  }

  Future<void> ensureHighEnergy() async {
    final candidate = metadataRepository is HighEnergyRepository
        ? metadataRepository
        : repository;
    final video = detail;
    final selected = part;
    if (_disposed ||
        _closing ||
        _audioOnly ||
        !_ownerVisible ||
        _highEnergySurfaces.isEmpty ||
        !_settings.highEnergyProgressEnabled ||
        !_chaptersConfirmedEmpty ||
        chapters.isNotEmpty ||
        media == null ||
        isLive ||
        contentTarget is OfflinePlaybackTarget ||
        candidate is! HighEnergyRepository ||
        video == null ||
        selected == null ||
        selected.cid != danmakuCid ||
        _scope != accountScope() ||
        _epoch != sessionEpoch() ||
        _highEnergyDuration <= Duration.zero ||
        _highEnergyRequested) {
      return;
    }
    final generation = _generation;
    final token = RequestCancellation();
    _highEnergyCancellation = token;
    _highEnergyRequested = true;
    try {
      final result = await candidate.highEnergy(
        video,
        selected,
        cancellation: token,
      );
      if (!_acceptMetadata(generation, token) ||
          !_settings.highEnergyProgressEnabled ||
          !_chaptersConfirmedEmpty ||
          chapters.isNotEmpty ||
          _highEnergySurfaces.isEmpty ||
          !_ownerVisible) {
        return;
      }
      final duration = _highEnergyDuration;
      highEnergy.value = result != null && result.matchesDuration(duration)
          ? result
          : null;
    } on AppFailure catch (failure) {
      if (_acceptMetadata(generation, token) &&
          failure.kind != AppFailureKind.cancelled) {
        highEnergy.value = null;
      }
    } finally {
      if (identical(_highEnergyCancellation, token)) {
        _highEnergyCancellation = null;
      }
    }
  }

  int selectedSubtitle = -1;
  bool commentsEnabled = true;
  double commentFontScale = 1;
  bool get isResolving => _resolving;
  int get sourceGeneration => _generation;
  String get sourceAccountScope => _scope;
  bool get sourceMatchesAccount =>
      _scope == accountScope() && _epoch == sessionEpoch();

  /// Carry the user's play/pause choice across a video route's loading gap.
  /// A completed source is the one exception: advancing starts the next item.
  bool prepareNextVideo(
    VideoId id,
    String cid, {
    required VideoId nextId,
    String? nextCid,
    bool completed = false,
  }) {
    if (_disposed ||
        detail?.summary.id != id ||
        part?.cid != cid ||
        _scope != accountScope() ||
        _epoch != sessionEpoch() ||
        (completed && snapshots.value.phase != PlaybackPhase.ended)) {
      return false;
    }
    _nextSourceIntent = (
      id: nextId,
      cid: nextCid,
      playing: completed ? true : _desiredPlaying,
      position: completed ? Duration.zero : null,
      scope: _scope,
      epoch: _epoch,
    );
    return true;
  }

  void discardNextVideo() => _nextSourceIntent = null;

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
    final checkpoint = _PlaybackCheckpoint(
      videoId: video?.summary.id,
      cid: selected?.cid,
      target: contentTarget,
      scope: _scope,
      epoch: _epoch,
      position: preparing
          ? _openingPosition ?? previous?.position
          : snapshot.position,
      rate:
          _temporaryRateOriginal ?? (preparing ? _openingRate : snapshot.rate),
      volume: preparing ? _openingVolume : snapshot.volume,
      quality: _quality,
      liveLine: _liveLine,
      liveStream: _liveStreamPreference,
      desiredPlaying: _desiredPlaying,
      subtitleLabel: _subtitlePreference,
      voice: _voice,
      audioOnly: _audioOnly,
    );
    _checkpoints[owner] = checkpoint;
    if (_settings.navigationMode != WorkspaceNavigationMode.multipleTabs) {
      final key = (video?.summary.id, selected?.cid, contentTarget);
      _navigationCheckpoints.remove(key);
      _navigationCheckpoints[key] = checkpoint;
      // Sixteen back entries plus the current source while capturing a pop.
      while (_navigationCheckpoints.length > 17) {
        _navigationCheckpoints.remove(_navigationCheckpoints.keys.first);
      }
    }
  }

  Future<void> activate(
    Object owner,
    VideoDetail? video,
    VideoPart? selected, {
    ContentPlaybackTarget? target,
    String? title,
    bool visible = true,
  }) async {
    if (_disposed || !_owners.contains(owner)) return;
    if (identical(_activeOwner, owner) &&
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target &&
        _scope == accountScope() &&
        _epoch == sessionEpoch() &&
        (media != null || _resolving)) {
      final wasVisible = _ownerVisible;
      _ownerVisible = visible;
      if (!wasVisible && visible) _resumeCommentPresentation();
      if (wasVisible && !visible) _suspendCommentPresentation();
      if (!visible) _cancelHighEnergy();
      if (visible) unawaited(ensureHighEnergy());
      return;
    }
    final sameOwner = identical(_activeOwner, owner);
    final sameKind = contentTarget.runtimeType == target.runtimeType;
    _captureOwner();
    final owned = _checkpoints[owner];
    final saved =
        owned?.videoId == video?.summary.id &&
            owned?.cid == selected?.cid &&
            owned?.target == target
        ? owned
        : _navigationCheckpoints[(video?.summary.id, selected?.cid, target)];
    final restored =
        saved != null &&
            saved.scope == accountScope() &&
            saved.epoch == sessionEpoch() &&
            saved.videoId == video?.summary.id &&
            saved.cid == selected?.cid &&
            saved.target == target
        ? saved
        : null;
    _activeOwner = owner;
    // Retained pages can advance to another part/episode while hidden. Updating
    // their source must not imply that a surface is being presented again.
    _ownerVisible = visible;
    if (!visible) _suspendCommentPresentation();
    _subtitlePreference = restored?.subtitleLabel;
    final nextIntent = _nextSourceIntent;
    final validIntent =
        nextIntent != null &&
        nextIntent.scope == accountScope() &&
        nextIntent.epoch == sessionEpoch();
    if (nextIntent != null && !validIntent) _nextSourceIntent = null;
    final nextPlaying =
        nextIntent != null &&
            validIntent &&
            nextIntent.id == video?.summary.id &&
            (nextIntent.cid == null || nextIntent.cid == selected?.cid)
        ? nextIntent.playing
        : null;
    if (nextPlaying != null) _nextSourceIntent = null;
    await open(
      video,
      selected,
      force: true,
      quality:
          restored?.quality ??
          (sameOwner &&
                  sameKind &&
                  (target is! LivePlaybackTarget || contentTarget == target)
              ? _quality
              : null) ??
          (target is LivePlaybackTarget
              ? _settings.preferredLiveQuality
              : _settings.preferredQuality),
      liveLine: restored?.liveLine,
      liveStream: restored?.liveStream,
      position: nextPlaying != null ? nextIntent?.position : restored?.position,
      desiredPlaying:
          nextPlaying ??
          restored?.desiredPlaying ??
          (sameOwner ? _desiredPlaying : _settings.autoPlay),
      rate:
          restored?.rate ?? _rateMemory.rateFor(_settings.defaultPlaybackRate),
      volume:
          restored?.volume ?? _volumeMemory.volumeFor(_settings.defaultVolume),
      target: target,
      title: title,
      voice: restored?.voice ?? const PlaybackVoice.original(),
      audioOnly: restored?.audioOnly ?? (sameOwner && sameKind && _audioOnly),
    );
  }

  Future<void> deactivate(Object owner) async {
    if (!identical(_activeOwner, owner) || _disposed) return;
    // Visibility owns the surface and input, not playback intent. Keep the
    // active source running while browsing an ordinary workspace tab.
    _captureOwner();
    _ownerVisible = false;
    _cancelHighEnergy();
    _suspendCommentPresentation();
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
    if (identical(_activeOwner, owner)) _captureOwner();
    _owners.remove(owner);
    _checkpoints.remove(owner);
    if (_activeOwner == null) {
      scheduleMicrotask(() {
        if (!_disposed && _activeOwner == null && _owners.isEmpty) {
          unawaited(stop(clearCheckpoints: false));
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

  void _suspendCommentPresentation() {
    for (final token in _segmentRequests.values) {
      token.cancel();
    }
    _segmentRequests.clear();
    _commentRefreshRequest = null;
    _lastCommentWindow = null;
    final snapshot = snapshots.value;
    danmaku.sync(
      confirmedPosition: snapshot.position,
      playing: false,
      buffering: snapshot.isBuffering,
      seeking: snapshot.isSeeking,
      rate: snapshot.rate,
    );
    danmaku.releaseRasterCache();
  }

  void _resumeCommentPresentation() {
    if (!_ownerVisible || !commentsEnabled || _audioOnly) return;
    final snapshot = snapshots.value;
    // Hidden time is not a paused animation. Rebuild only the current media
    // window so comments seen before hiding cannot resume with a stale age.
    danmaku.seekConfirmed(snapshot.position);
    _syncDanmaku(snapshot);
    _lastCommentWindow = null;
    _ensureComments(snapshot.position);
  }

  void _syncDanmaku(PlaybackSnapshot snapshot) {
    danmaku.sync(
      confirmedPosition: snapshot.position,
      playing: !_audioOnly && snapshot.phase == PlaybackPhase.playing,
      buffering: snapshot.isBuffering,
      seeking: snapshot.isSeeking,
      rate: snapshot.rate,
    );
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
    PlaybackVoice? voice,
    int? liveLine,
    LiveStreamPreference? liveStream,
    bool? audioOnly,
  }) async {
    if (_disposed || _closing) return;
    if (target == null && (video == null || selected == null)) return;
    if (!force &&
        (audioOnly == null || audioOnly == _audioOnly) &&
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target &&
        (_resolving || (error == null && media != null))) {
      return;
    }
    final generation = ++_generation;
    final requestedAudioOnly = audioOnly ?? _audioOnly;
    _audioOnly = requestedAudioOnly;
    _audioRecovery = null;
    // Capture source settings together; a preference change during resolution
    // applies to the next open rather than half of this source generation.
    final preferredCodec = _settings.preferredVideoCodec;
    final mediaCdn = _settings.mediaCdn;
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
    _commentRefreshRequest = null;
    _failedSegments.clear();
    _prefetchFailedSegments.clear();
    _lastCommentWindow = null;
    final savedProgress = startupDiagnostics.measure(
      generation,
      PlaybackStartupStage.saveProgress,
      _saveProgress,
    );
    _cancelCloudResume();
    final resumeRevision = _resumeRevision;
    final mediaReady = Completer<bool>();
    final cancellation = RequestCancellation();
    _sourceCancellation = cancellation;
    final samePart =
        detail?.summary.id == video?.summary.id &&
        part?.cid == selected?.cid &&
        contentTarget == target;
    final requestedLiveLine = target is LivePlaybackTarget
        ? liveLine ?? (samePart ? _liveLine : 0)
        : 0;
    final requestedLiveStream = target is LivePlaybackTarget
        ? liveStream ??
              (samePart
                  ? _liveStreamPreference
                  : _settings.liveStreamPreference)
        : LiveStreamPreference.automatic;
    _voice = target == null
        ? voice ?? (samePart ? _voice : const PlaybackVoice.original())
        : const PlaybackVoice.original();
    if (!samePart) _voices = const [];
    if (desiredPlaying != null) {
      _desiredPlaying = desiredPlaying;
    } else if (!samePart) {
      _desiredPlaying = true;
      _subtitlePreference = null;
    }
    final oldRate =
        rate ??
        (samePart && media != null
            ? _temporaryRateOriginal ?? snapshots.value.rate
            : _rateMemory.rateFor(_settings.defaultPlaybackRate));
    _temporaryRateOriginal = null;
    _temporaryRateGeneration = null;
    _temporaryRateRevision++;
    final oldVolume =
        volume ??
        (samePart && media != null
            ? snapshots.value.volume
            : _volumeMemory.volumeFor(_settings.defaultVolume));
    _openingPosition = position;
    _openingRate = oldRate;
    _openingVolume = oldVolume;
    _quality = quality;
    _liveLine = requestedLiveLine;
    _liveStreamPreference = requestedLiveStream;
    detail = video;
    part = selected;
    contentTarget = target;
    contentTitle = title;
    media = null;
    error = null;
    auxiliaryMessage = null;
    subtitleTracks = const [];
    subtitleCues = const [];
    subtitleLoading = false;
    subtitleMessage = null;
    _clearTimeline();
    selectedSubtitle = -1;
    _scope = accountScope();
    _epoch = sessionEpoch();
    final sourceScope = _scope;
    final sourceEpoch = _epoch;
    bool isCurrent() =>
        generation == _generation &&
        !_disposed &&
        !_closing &&
        !cancellation.isCancelled &&
        sourceScope == accountScope() &&
        sourceEpoch == sessionEpoch();
    _resolving = true;
    danmaku.replaceEvents(const []);
    _notify();
    try {
      await savedProgress;
      if (!isCurrent()) return;
      // Saving the previous source must finish before reading its local resume
      // record. Release, resolution and that read otherwise share no state.
      final scope = _scope;
      final requestedVoice = _voice;
      final readResume =
          !isLive &&
          position == null &&
          _settings.resumePlayback &&
          video != null &&
          selected != null;
      final stopped = startupDiagnostics.measure(
        generation,
        PlaybackStartupStage.stopPrevious,
        engine.stop,
      );
      final contentResolver = contentRepository;
      final resolution = startupDiagnostics.measure(
        generation,
        PlaybackStartupStage.resolve,
        () async {
          if (target != null) {
            if (contentResolver == null) {
              throw const AppFailure(AppFailureKind.playback, '内容播放服务未配置');
            }
            if (target is LivePlaybackTarget &&
                contentResolver is LiveStreamPlaybackRepository) {
              return (contentResolver as LiveStreamPlaybackRepository)
                  .resolveLive(
                    target,
                    quality: quality,
                    preference: requestedLiveStream,
                    cancellation: cancellation,
                  );
            }
            return contentResolver.resolve(
              target,
              quality: quality,
              preferredCodec: preferredCodec,
              cancellation: cancellation,
            );
          } else if (video != null && selected != null) {
            final resolver = repository;
            if (!requestedVoice.isOriginal &&
                resolver is VoicePlaybackRepository) {
              return (resolver as VoicePlaybackRepository).resolveVoice(
                video.summary.id,
                selected.cid,
                voice: requestedVoice,
                quality: quality,
                preferredCodec: preferredCodec,
                cancellation: cancellation,
              );
            } else {
              return repository.resolve(
                video.summary.id,
                selected.cid,
                quality: quality,
                preferredCodec: preferredCodec,
                cancellation: cancellation,
              );
            }
          } else {
            throw const AppFailure(AppFailureKind.playback, '缺少播放内容');
          }
        },
      );
      Duration? localResume;
      late final PlaybackMedia resolved;
      // Attach handlers to every operation immediately, and settle all of them
      // even on error. No new native source can open before release finishes.
      await Future.wait<void>([
        stopped,
        resolution.then<void>((value) {
          resolved = value;
        }),
        if (readResume)
          startupDiagnostics
              .measure(
                generation,
                PlaybackStartupStage.localResumeRead,
                () => progress.read(scope, video.summary.id, selected.cid),
              )
              .then<void>((value) {
                localResume = value;
              }),
      ]);
      if (!isCurrent()) return;
      // A user may enable resume while resolution is pending. Preserve that
      // intent without treating an unread local record as a cache miss.
      if (!readResume &&
          !isLive &&
          position == null &&
          _settings.resumePlayback &&
          video != null &&
          selected != null) {
        localResume = await startupDiagnostics.measure(
          generation,
          PlaybackStartupStage.localResumeRead,
          () => progress.read(scope, video.summary.id, selected.cid),
        );
        if (!isCurrent()) return;
      }
      final resume = isLive
          ? Duration.zero
          : position ??
                (_settings.resumePlayback && video != null && selected != null
                    ? _resumePosition(
                        localResume,
                        resolved.duration,
                        generation,
                        cancellation,
                        mediaReady.future,
                        resumeRevision,
                      )
                    : Duration.zero);
      if (!isCurrent()) return;
      final policy = MediaRequestPolicy(headers: resolved.headers);
      _openingPosition = resume;
      PlayerFailure? lastFailure;
      final audio = resolved.audio;
      if (resolved.kind == PlaybackMediaKind.dash && audio == null) {
        throw const AppFailure(AppFailureKind.playback, '未取得点播音频轨道');
      }
      if (requestedAudioOnly &&
          (isLive ||
              resolved.kind != PlaybackMediaKind.dash ||
              audio == null ||
              audio.urls.isEmpty)) {
        throw const AppFailure(AppFailureKind.playback, '当前内容没有独立音轨，请返回视频播放');
      }
      // Live lines follow url_info order, independently of VOD CDN preferences.
      final liveLineIndex =
          isLive &&
              requestedLiveLine >= 0 &&
              requestedLiveLine < resolved.video.urls.length
          ? requestedLiveLine
          : 0;
      final videoPrimary = resolved.video.urls[isLive ? liveLineIndex : 0];
      final videoBackup = isLive
          ? resolved.video.urls.length > 1
                ? resolved.video.urls[(liveLineIndex + 1) %
                      resolved.video.urls.length]
                : null
          : backupMediaCdnUrl(resolved.video.urls, mediaCdn);
      final audioBackup = audio == null
          ? null
          : backupMediaCdnUrl(audio.urls, mediaCdn);
      final hasBackup = requestedAudioOnly
          ? audioBackup != null
          : videoBackup != null || audioBackup != null;
      final recovery = _PlaybackStartupRecovery(
        now: startupNow ?? () => _clock.elapsed,
        hasBackup: hasBackup,
        isCurrent: isCurrent,
      )..start();
      var openedLiveLine = liveLineIndex;
      // At most two opens in one resolution, using only server-provided backups.
      Future<void> openMedia(PlaybackSnapshot? checkpoint) async {
        for (; recovery.attempts < 2;) {
          if (!isCurrent()) return;
          final remaining = isLive || !hasBackup
              ? _PlaybackStartupRecovery.totalBudget
              : recovery.totalRemaining;
          if (remaining <= Duration.zero) {
            throw PlayerFailure(
              PlayerFailureKind.nativePlayback,
              'Playback preparation timed out.',
              engine.currentSnapshot.generation,
            );
          }
          final attempt = recovery.attempts++;
          // Leave time for a different returned CDN when the primary stalls.
          // Single-URL and live sources retain their existing startup budget.
          final attemptBudget =
              !isLive &&
                  hasBackup &&
                  attempt == 0 &&
                  remaining > _PlaybackStartupRecovery.primaryBudget
              ? _PlaybackStartupRecovery.primaryBudget
              : remaining;
          final videoUri = attempt == 0
              ? videoPrimary
              : videoBackup ?? videoPrimary;
          final audioUri = audio == null
              ? null
              : attempt == 0
              ? audio.urls.first
              : audioBackup ?? audio.urls.first;
          try {
            await startupDiagnostics.measure(
              generation,
              PlaybackStartupStage.nativeOpen,
              () => engine.open(
                requestedAudioOnly && audio != null && audioUri != null
                    ? ProgressiveSource(
                        MediaTrack(
                          uri: audioUri,
                          requestPolicy: policy,
                          codec: audio.codec,
                          bandwidth: audio.bandwidth,
                        ),
                      )
                    : resolved.kind == PlaybackMediaKind.liveHls
                    ? ManifestSource(
                        MediaTrack(uri: videoUri, requestPolicy: policy),
                        isLive: true,
                      )
                    : resolved.kind == PlaybackMediaKind.liveFlv ||
                          resolved.kind == PlaybackMediaKind.progressive
                    ? ProgressiveSource(
                        MediaTrack(uri: videoUri, requestPolicy: policy),
                      )
                    : DashPairSource(
                        video: MediaTrack(
                          uri: videoUri,
                          requestPolicy: policy,
                          codec: resolved.video.codec,
                          bandwidth: resolved.video.bandwidth,
                        ),
                        audio: audio == null || audioUri == null
                            ? null
                            : MediaTrack(
                                uri: audioUri,
                                requestPolicy: policy,
                                codec: audio.codec,
                                bandwidth: audio.bandwidth,
                              ),
                      ),
                OpenOptions(
                  startPosition: checkpoint?.position ?? resume,
                  play: false,
                  rate: isLive ? 1 : checkpoint?.rate ?? oldRate,
                  volume: checkpoint?.volume ?? oldVolume,
                  audioGainDb: _audioGainFor(resolved),
                  videoDecoding: videoDecoding,
                  openTimeout: attemptBudget,
                ),
              ),
            );
            lastFailure = null;
            if (isLive) openedLiveLine = resolved.video.urls.indexOf(videoUri);
            break;
          } on PlayerFailure catch (failure) {
            lastFailure = failure;
            if (!hasBackup ||
                failure.kind != PlayerFailureKind.nativePlayback) {
              break;
            }
          }
        }
        if (lastFailure case final failure?) throw failure;
      }

      recovery.reopen = (checkpoint) => openMedia(checkpoint);
      await openMedia(null);
      recovery.stop();
      if (!isCurrent()) return;
      if (resolved.kind == PlaybackMediaKind.dash && audio != null) {
        _audioRecovery = recovery;
      }
      media = resolved;
      if (isLive) {
        _liveLine = openedLiveLine;
        if (!requestedLiveStream.isAutomatic &&
            resolved.liveStream != null &&
            resolved.liveStream != requestedLiveStream) {
          auxiliaryMessage = '当前房间未提供偏好的直播流，已使用可用组合';
        }
        if (samePart && quality != 0 && resolved.quality != quality) {
          auxiliaryMessage =
              '该清晰度当前不可用，已切换到${resolved.qualityLabels[resolved.quality] ?? resolved.quality}';
        } else if (requestedLiveLine != openedLiveLine) {
          auxiliaryMessage = '所选直播线路不可用，已切换到${liveLineLabel(openedLiveLine)}';
        }
      }
      if (target == null) {
        _voice = resolved.voice;
        _voices = resolved.voices;
      }
      _mediaGeneration = generation;
      _resolving = false;
      // Settings may have changed while the native source was opening.
      // Apply the latest mode before restoring the user's play intent.
      await _applyAudioGain();
      if (!isCurrent()) return;
      danmaku.seekConfirmed(engine.currentSnapshot.position);
      await startupDiagnostics.measure(
        generation,
        PlaybackStartupStage.playAndAudioReady,
        _syncPlayback,
      );
      if (!isCurrent()) return;
      _reportProgress();
      _notify();
      mediaReady.complete(true);
      _ensureComments(engine.currentSnapshot.position);
      if (!isLive && video != null && selected != null) {
        unawaited(
          _loadSubtitleTracks(generation, video, selected, cancellation),
        );
      }
      if (target == null) unawaited(_loadSponsorSegments());
    } on AppFailure catch (failure) {
      if (isCurrent() && failure.kind != AppFailureKind.cancelled) {
        error = failure.message;
        _resolving = false;
        _notify();
      }
    } on PlayerFailure catch (failure) {
      if (isCurrent()) {
        error = contentTarget is OfflinePlaybackTarget
            ? '无法播放本地视频，文件可能无法解码或已不可访问'
            : failure.message;
        _resolving = false;
        _notify();
      }
    } catch (_) {
      if (isCurrent()) {
        error = contentTarget is OfflinePlaybackTarget
            ? '无法打开本地视频，请确认文件存在且格式受支持'
            : '播放准备失败，请检查网络后重试';
        _resolving = false;
        _notify();
      }
    } finally {
      if (!mediaReady.isCompleted) mediaReady.complete(false);
    }
  }

  void _onSnapshot(PlaybackSnapshot value) {
    if (_disposed || value.generation != engine.currentSnapshot.generation) {
      return;
    }
    final previous = snapshots.value;
    final previousPhase = previous.phase;
    final enteredEnded =
        value.phase == PlaybackPhase.ended &&
        snapshots.value.phase != PlaybackPhase.ended;
    snapshots.value = value;
    if (previous.duration != value.duration && value.duration > Duration.zero) {
      unawaited(ensureHighEnergy());
    }
    if (enteredEnded && !_resolving) {
      _desiredPlaying = false;
    }
    if (_ownerVisible &&
        commentsEnabled &&
        (previous.position != value.position ||
            previous.phase != value.phase ||
            previous.isBuffering != value.isBuffering ||
            previous.isSeeking != value.isSeeking ||
            previous.rate != value.rate ||
            previous.generation != value.generation)) {
      _syncDanmaku(value);
    }
    if (!_resolving && media != null) {
      if (value.phase == PlaybackPhase.playing ||
          enteredEnded ||
          value.phase == PlaybackPhase.paused &&
              previousPhase == PlaybackPhase.playing) {
        _reportProgress(
          force: enteredEnded || value.phase == PlaybackPhase.paused,
        );
      }
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
              _playbackAllowed &&
              _desiredPlaying &&
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
        unawaited(_saveProgress(report: false));
      }
      if (enteredEnded) unawaited(_saveProgress(report: false));
    }
  }

  Future<void> _saveProgress({bool report = true}) async {
    // A temporary start-at-zero position must not replace the resume record.
    if (_cloudResumeCancellation != null) return;
    if (report) _reportProgress(force: true);
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
          OfflinePlaybackTarget(:final episodeId) => episodeId,
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

  PlaybackHistoryTarget? get _historyTarget {
    final video = detail;
    final selected = part;
    if (isLive ||
        contentTarget is OfflinePlaybackTarget ||
        video == null ||
        selected == null ||
        !video.summary.id.isValid ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(selected.cid)) {
      return null;
    }
    return PlaybackHistoryTarget(
      video.summary.id,
      selected.cid,
      episodeId: switch (contentTarget) {
        PgcPlaybackTarget(:final episodeId) => episodeId,
        _ => null,
      },
      seasonId: switch (contentTarget) {
        PgcPlaybackTarget(:final seasonId) => seasonId,
        _ => null,
      },
    );
  }

  Duration _resumePosition(
    Duration? local,
    Duration duration,
    int generation,
    RequestCancellation cancellation,
    Future<bool> mediaReady,
    int resumeRevision,
  ) {
    final scope = _scope;
    final epoch = _epoch;
    if (local != null) return local;
    if (generation != _generation ||
        cancellation.isCancelled ||
        scope != accountScope() ||
        epoch != sessionEpoch()) {
      return Duration.zero;
    }
    final history = historyRepository;
    final target = _historyTarget;
    if (history == null ||
        target == null ||
        !scope.startsWith('user:') ||
        !_settings.resumePlayback ||
        resumeRevision != _resumeRevision) {
      return Duration.zero;
    }
    final cloudCancellation = RequestCancellation();
    cancellation.onCancel(cloudCancellation.cancel);
    _cloudResumeCancellation = cloudCancellation;
    unawaited(
      _resumeFromCloud(
        history,
        target,
        duration,
        generation,
        scope,
        epoch,
        cloudCancellation,
        mediaReady,
        resumeRevision,
      ),
    );
    return Duration.zero;
  }

  void _cancelCloudResume() {
    _resumeRevision++;
    _cloudResumeCancellation?.cancel();
    _cloudResumeCancellation = null;
  }

  Future<void> _resumeFromCloud(
    PlaybackHistoryRepository history,
    PlaybackHistoryTarget target,
    Duration duration,
    int generation,
    String scope,
    int epoch,
    RequestCancellation cancellation,
    Future<bool> mediaReady,
    int resumeRevision,
  ) async {
    bool current() =>
        !_disposed &&
        !_closing &&
        generation == _generation &&
        scope == accountScope() &&
        epoch == sessionEpoch() &&
        _settings.resumePlayback &&
        resumeRevision == _resumeRevision &&
        !cancellation.isCancelled &&
        identical(_cloudResumeCancellation, cancellation);
    try {
      final remote = await history.read(
        target,
        scope: scope,
        cancellation: cancellation,
      );
      if (!current() ||
          remote == null ||
          remote <= Duration.zero ||
          duration > Duration.zero &&
              remote >= duration - const Duration(seconds: 5)) {
        return;
      }
      if (!await mediaReady ||
          !current() ||
          _mediaGeneration != generation ||
          media == null ||
          error != null ||
          snapshots.value.phase == PlaybackPhase.ended ||
          remote <= snapshots.value.position) {
        return;
      }
      final confirmedDuration = snapshots.value.duration;
      if (confirmedDuration > Duration.zero &&
          remote >= confirmedDuration - const Duration(seconds: 5)) {
        return;
      }
      // Seeking preserves the latest play/pause intent. Manual seeks cancel
      // this request before entering the engine's serial command queue.
      await engine.seek(remote);
      if (!current()) return;
      danmaku.seekConfirmed(engine.currentSnapshot.position);
      _lastCommentWindow = null;
      _ensureComments(engine.currentSnapshot.position);
    } on AppFailure catch (failure) {
      if (current() && failure.kind != AppFailureKind.cancelled) {
        auxiliaryMessage = '云端进度读取失败，本次从头播放';
      }
    } on PlayerFailure {
      if (current()) auxiliaryMessage = '云端续播定位失败，继续当前播放';
    } catch (_) {
      if (current()) auxiliaryMessage = '云端进度读取失败，本次从头播放';
    } finally {
      if (identical(_cloudResumeCancellation, cancellation)) {
        final stillCurrent = current();
        _cloudResumeCancellation = null;
        if (stillCurrent) {
          _reportProgress();
          if (media != null) unawaited(_saveProgress(report: false));
          _notify();
        }
      }
    }
  }

  void _reportProgress({bool force = false}) {
    final target = _historyTarget;
    final snapshot = snapshots.value;
    if (target == null ||
        media == null ||
        snapshot.duration <= Duration.zero ||
        _resolving ||
        _cloudResumeCancellation != null ||
        snapshot.isSeeking ||
        _epoch != sessionEpoch() ||
        _scope != accountScope()) {
      if (_epoch != sessionEpoch() || _scope != accountScope()) {
        _historyReporter?.clear();
      }
      return;
    }
    _historyReporter?.submit(
      PlaybackHistoryRecord(
        target: target,
        position: snapshot.position,
        duration: snapshot.duration,
        completed: snapshot.phase == PlaybackPhase.ended,
      ),
      scope: _scope,
      epoch: _epoch,
      generation: _mediaGeneration,
      force: force,
    );
  }

  /// Applies this page's settings without changing another page's engine.
  void configureSettings(AppSettings settings) {
    final previous = _settings;
    _settings = settings.normalized();
    _volumeMemory.configure(
      enabled: _settings.rememberVolumeGlobally,
      defaultVolume: _settings.defaultVolume,
    );
    if (_settings.navigationMode == WorkspaceNavigationMode.multipleTabs) {
      _navigationCheckpoints.clear();
    }
    if (!_settings.highEnergyProgressEnabled) {
      _cancelHighEnergy();
      highEnergy.value = null;
      _highEnergyRequested = false;
    } else if (!previous.highEnergyProgressEnabled) {
      unawaited(ensureHighEnergy());
    }
    if (!_settings.resumePlayback) _cancelCloudResume();
    final presentationChanged =
        !_commentsConfigured ||
        _commentPresentationSettings(previous) !=
            _commentPresentationSettings(_settings);
    final windowChanged =
        !_commentsConfigured ||
        previous.danmakuOffset != _settings.danmakuOffset ||
        previous.danmakuSpeed != _settings.danmakuSpeed ||
        previous.danmakuFontScale != _settings.danmakuFontScale ||
        previous.danmakuScrollEnabled != _settings.danmakuScrollEnabled ||
        previous.danmakuTopEnabled != _settings.danmakuTopEnabled ||
        previous.danmakuBottomEnabled != _settings.danmakuBottomEnabled ||
        previous.danmakuBlockColored != _settings.danmakuBlockColored ||
        previous.danmakuMinimumWeight != _settings.danmakuMinimumWeight ||
        previous.danmakuMaxPerSecond != _settings.danmakuMaxPerSecond ||
        !listEquals(
          previous.danmakuBlockedWords,
          _settings.danmakuBlockedWords,
        );
    _commentsConfigured = true;
    if (presentationChanged) {
      danmaku.configure(
        area: _settings.danmakuArea,
        speed: _settings.danmakuSpeed,
        topInset: _settings.danmakuTopMargin,
        lineSpacing: _settings.danmakuLineSpacing,
        offset: _settings.danmakuOffset,
        mergeDuplicates: _settings.danmakuMergeDuplicates,
        maxOnScreen: _settings.danmakuMaxOnScreen,
        textStyle: DanmakuTextStyle(
          fontFamily: _settings.danmakuFontFamily,
          bold: _settings.danmakuBold,
          effect: switch (_settings.danmakuStyle) {
            DanmakuStylePreference.shadow => DanmakuTextEffect.shadow,
            DanmakuStylePreference.stroke => DanmakuTextEffect.stroke,
            DanmakuStylePreference.plain => DanmakuTextEffect.plain,
          },
        ),
      );
    }
    if (windowChanged) _lastCommentWindow = null;
    configureComments(
      enabled: _settings.danmakuEnabled,
      fontScale: _settings.danmakuFontScale,
    );
    if (windowChanged) {
      _ensureComments(snapshots.value.position);
    }
    if (media != null) {
      if (previous.audioNormalization != _settings.audioNormalization) {
        unawaited(_applyAudioGain());
      }
      if (previous.defaultPlaybackRate != _settings.defaultPlaybackRate) {
        unawaited(
          _applyRate(_rateMemory.rateFor(_settings.defaultPlaybackRate)),
        );
      }
      if (!_settings.rememberVolumeGlobally &&
          previous.defaultVolume != _settings.defaultVolume) {
        unawaited(
          _applyVolume(_volumeMemory.volumeFor(_settings.defaultVolume)),
        );
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

  Object _commentPresentationSettings(AppSettings settings) => (
    settings.danmakuArea,
    settings.danmakuSpeed,
    settings.danmakuTopMargin,
    settings.danmakuLineSpacing,
    settings.danmakuOffset,
    settings.danmakuMergeDuplicates,
    settings.danmakuMaxOnScreen,
    settings.danmakuFontFamily,
    settings.danmakuBold,
    settings.danmakuStyle,
  );

  Future<void> _loadSponsorSegments() async {
    _sponsorCancellation?.cancel();
    sponsorSegments = const [];
    sponsorMessage = null;
    sponsorLoading = false;
    final repository = sponsorRepository;
    final video = detail;
    final selected = part;
    if (contentTarget is OfflinePlaybackTarget ||
        _settings.sponsorBlockMode == SponsorBlockMode.disabled ||
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
    _cancelCloudResume();
    _sponsorSeeking = true;
    try {
      await engine.seek(segment.end);
      if (_disposed || generation != _generation) return;
      danmaku.seekConfirmed(engine.currentSnapshot.position);
      _lastCommentWindow = null;
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
    final wasEnabled = commentsEnabled;
    final changed = commentsEnabled != enabled || commentFontScale != fontScale;
    commentsEnabled = enabled;
    commentFontScale = fontScale;
    if (changed) {
      _lastCommentWindow = null;
      if (!enabled) {
        _suspendCommentPresentation();
      } else if (!wasEnabled) {
        _resumeCommentPresentation();
      } else {
        _ensureComments(snapshots.value.position);
      }
    }
  }

  void _ensureComments(Duration position) {
    final cid = danmakuCid;
    if (_audioOnly ||
        !_ownerVisible ||
        !commentsEnabled ||
        cid == null ||
        _resolving ||
        media == null) {
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
      _segments[segment] = CommentSegment(events);
      _prefetchFailedSegments.remove(segment);
      _scheduleCommentRefresh();
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

  void _scheduleCommentRefresh() {
    if (_commentRefreshRequest != null) return;
    final request = Object();
    _commentRefreshRequest = request;
    final generation = _generation;
    scheduleMicrotask(() {
      if (!identical(_commentRefreshRequest, request)) return;
      _commentRefreshRequest = null;
      if (generation == _generation) {
        _refreshCommentWindow(snapshots.value.position);
      }
    });
  }

  void _refreshCommentWindow(Duration position) {
    if (_disposed || !_ownerVisible || !commentsEnabled) return;
    final displayPosition = position - _settings.danmakuOffset;
    final requiredHistory = danmaku.requiredHistory;
    final history = requiredHistory > const Duration(seconds: 16)
        ? requiredHistory
        : const Duration(seconds: 16);
    final events = mergeCommentWindow(
      _segments.values,
      displayPosition - history,
      displayPosition + const Duration(seconds: 60),
    );
    final density = <int, int>{};
    danmaku.replaceEvents(
      events
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
      sorted: true,
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
        _chaptersConfirmedEmpty =
            metadata.chapterFailure == null && metadata.chapters.isEmpty;
        if (!_chaptersConfirmedEmpty) {
          _cancelHighEnergy();
          highEnergy.value = null;
        }
        unawaited(ensureHighEnergy());
        tracks = metadata.subtitles;
        subtitleMessage = metadata.subtitleFailure?.message;
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
        final index = tracks.indexWhere(
          (track) => track.preferenceKey == preference,
        );
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
      _scope == accountScope() &&
      _epoch == sessionEpoch();

  void _clearTimeline() {
    _cancelHighEnergy();
    _highEnergyRequested = false;
    _chaptersConfirmedEmpty = false;
    highEnergy.value = null;
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
        _scope != accountScope() ||
        _epoch != sessionEpoch() ||
        _storyboardRequested) {
      return;
    }
    _storyboardRequested = true;
    storyboardLoading = true;
    storyboardMessage = null;
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
      if (result == null) {
        _storyboardRequested = false;
      }
    } on AppFailure catch (failure) {
      if (!_acceptMetadata(generation, token) ||
          failure.kind == AppFailureKind.cancelled) {
        return;
      }
      storyboardMessage = '缩略图暂时不可用';
      // Like the official progress bar, a new preview interaction can retry.
      // The widget invokes this once on entry/drag start, never on every move.
      _storyboardRequested = false;
    } finally {
      if (_acceptMetadata(generation, token)) {
        _storyboardCancellation = null;
        storyboardLoading = false;
        _notify();
      }
    }
  }

  Future<void> selectSubtitle(int index) async {
    if (_disposed || _closing || index < -1 || index >= subtitleTracks.length) {
      return;
    }
    final sourceGeneration = _generation;
    final generation = ++_subtitleGeneration;
    _subtitleCancellation?.cancel();
    selectedSubtitle = index;
    _subtitlePreference = index >= 0 && index < subtitleTracks.length
        ? subtitleTracks[index].preferenceKey
        : '__off__';
    subtitleCues = const [];
    subtitleLoading = index >= 0;
    subtitleMessage = null;
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
          !_acceptMetadata(sourceGeneration, token)) {
        return;
      }
      subtitleCues = cues;
      subtitleMessage = cues.isEmpty ? '这条字幕没有可显示的内容' : null;
    } on AppFailure catch (failure) {
      if (generation != _subtitleGeneration ||
          !_acceptMetadata(sourceGeneration, token) ||
          failure.kind == AppFailureKind.cancelled) {
        return;
      }
      subtitleMessage = '字幕加载失败，请重新选择重试';
    } catch (_) {
      if (generation != _subtitleGeneration ||
          !_acceptMetadata(sourceGeneration, token)) {
        return;
      }
      subtitleMessage = '字幕加载失败，请重新选择重试';
    } finally {
      if (generation == _subtitleGeneration &&
          _acceptMetadata(sourceGeneration, token)) {
        subtitleLoading = false;
        _notify();
      }
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
      _cancelCloudResume();
      _desiredPlaying = true;
      try {
        await engine.seek(Duration.zero);
        if (_disposed || generation != _generation) return;
        danmaku.seekConfirmed(engine.currentSnapshot.position);
        _lastCommentWindow = null;
        _ensureComments(engine.currentSnapshot.position);
        await _syncPlayback();
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
    await _command(_syncPlayback);
    await _saveProgress();
  }

  /// Idempotent system play commands must never toggle a playing source off.
  Future<void> play() async {
    if (_disposed || _closing) return;
    if (error != null && !_resolving) {
      _desiredPlaying = true;
      await retry();
      return;
    }
    if (snapshots.value.phase == PlaybackPhase.ended && !_resolving) {
      await togglePlaying();
      return;
    }
    _desiredPlaying = true;
    if (_resolving) {
      _notify();
      return;
    }
    await _command(_syncPlayback);
    await _saveProgress();
  }

  Future<void> pause() async {
    _desiredPlaying = false;
    await _command(() => _syncPlayback(forcePause: true));
    await _saveProgress();
  }

  /// Navigation suspension keeps the source, position and play/pause intent.
  /// The permission changes synchronously so a late resolve cannot autoplay.
  Future<void> setPlaybackAllowed(bool allowed) {
    if (_disposed || _closing || _playbackAllowed == allowed) {
      return _playbackCommands ?? Future.value();
    }
    _playbackAllowed = allowed;
    return _syncPlayback();
  }

  Future<void> _playWithAudioRecovery() async {
    final recovery = _audioRecovery;
    if (recovery == null) {
      await engine.play();
      return;
    }
    recovery.preparing = true;
    recovery.start();
    try {
      while (recovery.isCurrent()) {
        if (!_desiredPlaying || !_playbackAllowed) return;
        try {
          final remaining = recovery.remaining;
          if (remaining <= Duration.zero) {
            throw PlayerFailure(
              PlayerFailureKind.nativePlayback,
              'Playback preparation timed out.',
              engine.currentSnapshot.generation,
            );
          }
          // Future timeout alone cannot cancel native I/O. The backup path
          // stops this generation before reopening, also interrupting decoding.
          await engine.play().timeout(
            remaining,
            onTimeout: () {
              throw PlayerFailure(
                PlayerFailureKind.nativePlayback,
                'Audio preparation timed out.',
                engine.currentSnapshot.generation,
              );
            },
          );
        } on PlayerFailure catch (failure) {
          if (!recovery.isCurrent()) return;
          if (failure.kind != PlayerFailureKind.nativePlayback ||
              !recovery.canRetry) {
            // Exhausting a deadline must also cancel the underlying command.
            if (recovery.remaining <= Duration.zero) await engine.stop();
            rethrow;
          }
          final checkpoint = engine.currentSnapshot;
          _resolving = true;
          _notify();
          await engine.stop();
          if (!recovery.isCurrent()) return;
          await recovery.reopen(checkpoint);
          if (!recovery.isCurrent()) return;
          await _applyAudioGain();
          if (!recovery.isCurrent()) return;
          danmaku.seekConfirmed(engine.currentSnapshot.position);
          _resolving = false;
          continue;
        }
        if (!recovery.isCurrent()) return;
        _audioRecovery = null;
        if (!_desiredPlaying || !_playbackAllowed) await engine.pause();
        return;
      }
    } on PlayerFailure {
      if (!recovery.isCurrent()) return;
      _audioRecovery = null;
      rethrow;
    } finally {
      recovery.stop();
      recovery.preparing = false;
      if (recovery.isCurrent()) {
        _resolving = false;
        _notify();
      }
    }
  }

  Future<void> _syncPlayback({bool forcePause = false}) {
    final generation = _generation;
    final operation = (_playbackCommands ?? Future<void>.value()).then((
      _,
    ) async {
      if (_disposed || generation != _generation) return;
      if (!_playbackAllowed) {
        if (engine.currentSnapshot.desiredPlaying ||
            engine.currentSnapshot.phase == PlaybackPhase.playing) {
          await engine.pause();
        }
      } else if (!_resolving && media != null) {
        if (_desiredPlaying && !engine.currentSnapshot.desiredPlaying) {
          await _playWithAudioRecovery();
        } else if (!_desiredPlaying &&
            (forcePause || engine.currentSnapshot.desiredPlaying)) {
          await engine.pause();
        }
      }
    });
    final completed = operation.then(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _playbackCommands = completed;
    unawaited(
      completed.then((_) {
        if (identical(_playbackCommands, completed)) _playbackCommands = null;
      }),
    );
    return operation;
  }

  Future<void> seek(Duration target) async {
    if (isLive) return;
    _cancelCloudResume();
    await _command(() => engine.seek(target));
    danmaku.seekConfirmed(engine.currentSnapshot.position);
    _lastCommentWindow = null;
    _ensureComments(engine.currentSnapshot.position);
    await _saveProgress();
  }

  double? _temporaryRateOriginal;
  int? _temporaryRateGeneration;
  int _temporaryRateRevision = 0;
  double? _rateTarget, _volumeTarget;
  int? _rateTargetGeneration, _volumeTargetGeneration;
  int _rateTargetRevision = 0, _volumeTargetRevision = 0;
  int? _pendingRateMemoryRevision;
  final _rateCommands = MediaCommandPump();
  final _volumeCommands = MediaCommandPump();
  final _audioGainCommands = MediaCommandPump();

  double _audioGainFor(PlaybackMedia source) =>
      isLive || contentTarget is OfflinePlaybackTarget
      ? 0
      : source.loudness?.gainDb(_settings.audioNormalization) ?? 0;

  Future<void> _applyAudioGain() {
    final control = engine;
    if (control is! AudioGainControl) return Future.value();
    final generation = _generation;
    return _audioGainCommands.submit(
      () => _command(() async {
        final source = media;
        if (_disposed ||
            _closing ||
            generation != _generation ||
            _scope != accountScope() ||
            _epoch != sessionEpoch() ||
            source == null) {
          return;
        }
        await (control as AudioGainControl).setAudioGain(_audioGainFor(source));
      }),
    );
  }

  double get commandRate => _rateTargetGeneration == _generation
      ? _rateTarget ?? _temporaryRateOriginal ?? snapshots.value.rate
      : _temporaryRateOriginal ?? snapshots.value.rate;
  double get commandVolume => _volumeTargetGeneration == _generation
      ? _volumeTarget ?? snapshots.value.volume
      : snapshots.value.volume;

  Future<void> _serializeRate(Future<void> Function() action) {
    final generation = _generation;
    return _rateCommands.submit(() async {
      if (_disposed || _closing || generation != _generation) return;
      await action();
      // Restoration can replace a queued permanent native call. Confirm and
      // remember its latest target here as well as in setRate's direct path.
      final target = _rateTarget;
      final memoryRevision = _pendingRateMemoryRevision;
      if (generation == _generation &&
          target != null &&
          memoryRevision != null &&
          engine.currentSnapshot.rate == target) {
        _rateMemory.remember(target, revision: memoryRevision);
        _rateTarget = null;
      }
    });
  }

  Future<void> beginTemporaryRate(double rate) {
    if (isLive) return Future.value();
    _temporaryRateOriginal ??= commandRate;
    _temporaryRateGeneration = snapshots.value.generation;
    final revision = ++_temporaryRateRevision;
    return _serializeRate(() async {
      if (revision != _temporaryRateRevision) return;
      await _command(() => engine.setRate(rate));
    });
  }

  Future<void> endTemporaryRate({int? expectedGeneration}) async {
    if (expectedGeneration != null &&
        expectedGeneration != _temporaryRateGeneration) {
      return;
    }
    final rate = _temporaryRateOriginal;
    final sameSource = _temporaryRateGeneration == snapshots.value.generation;
    final revision = ++_temporaryRateRevision;
    if (rate != null && sameSource) await _applyRate(rate);
    if (_temporaryRateRevision == revision) {
      _temporaryRateOriginal = null;
      _temporaryRateGeneration = null;
    }
  }

  Future<void> _applyRate(double rate) => isLive
      ? Future.value()
      : _serializeRate(() => _command(() => engine.setRate(rate)));

  Future<void> setRate(double rate) {
    if (isLive || _disposed || _closing) return Future.value();
    final generation = _generation;
    final revision = ++_rateTargetRevision;
    _rateTarget = rate;
    _rateTargetGeneration = generation;
    if (_temporaryRateOriginal != null) _temporaryRateOriginal = rate;
    final memoryRevision = _rateMemory.beginChange();
    _pendingRateMemoryRevision = memoryRevision;
    return _serializeRate(
      () => _command(() async {
        try {
          await engine.setRate(rate);
          if (_disposed || _closing || generation != _generation) return;
          _rateMemory.remember(rate, revision: memoryRevision);
        } on PlayerFailure {
          if (generation == _generation) {
            _rateCommands.discardPending();
            _rateTarget = null;
            ++_rateTargetRevision;
          }
          rethrow;
        } finally {
          if (revision == _rateTargetRevision) _rateTarget = null;
        }
      }),
    );
  }

  Future<void> setVolume(double volume) => _applyVolume(volume, remember: true);

  Future<void> _applyVolume(double volume, {bool remember = false}) {
    if (_disposed || _closing) return Future.value();
    final generation = _generation;
    final revision = ++_volumeTargetRevision;
    _volumeTargetGeneration = generation;
    _volumeTarget = volume;
    final memoryRevision = remember ? _volumeMemory.beginChange() : null;
    return _volumeCommands.submit(
      () => _command(() async {
        if (_disposed || _closing || generation != _generation) return;
        try {
          await engine.setVolume(volume);
          if (_disposed || _closing || generation != _generation) return;
          if (memoryRevision != null) {
            _volumeMemory.remember(volume, revision: memoryRevision);
          }
        } on PlayerFailure {
          if (generation == _generation) {
            _volumeCommands.discardPending();
            _volumeTarget = null;
            ++_volumeTargetRevision;
          }
          rethrow;
        } finally {
          if (revision == _volumeTargetRevision) _volumeTarget = null;
        }
      }),
    );
  }

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
      position: media == null ? _openingPosition : snapshots.value.position,
      rate:
          _temporaryRateOriginal ??
          (media == null ? _openingRate : snapshots.value.rate),
      volume: media == null ? _openingVolume : snapshots.value.volume,
      target: contentTarget,
      title: contentTitle,
    );
  }

  Future<void> setAudioOnly(bool enabled) async {
    if (_disposed ||
        _closing ||
        enabled == _audioOnly ||
        (enabled && (!canListen || _resolving))) {
      return;
    }
    await open(
      detail,
      part,
      target: contentTarget,
      title: contentTitle,
      quality: _quality,
      force: true,
      audioOnly: enabled,
      position: media == null ? _openingPosition : snapshots.value.position,
      rate:
          _temporaryRateOriginal ??
          (media == null ? _openingRate : snapshots.value.rate),
      volume: media == null ? _openingVolume : snapshots.value.volume,
      desiredPlaying: _desiredPlaying,
    );
  }

  Future<void> changeLiveLine(int line) async {
    final current = media;
    if (!isLive ||
        current == null ||
        line < 0 ||
        line >= current.video.urls.length ||
        (line == _liveLine && error == null)) {
      return;
    }
    await open(
      null,
      null,
      quality: _quality,
      liveLine: line,
      force: true,
      desiredPlaying: _desiredPlaying,
      volume: snapshots.value.volume,
      target: contentTarget,
      title: contentTitle,
    );
  }

  Future<void> changeLiveStream(
    LiveStreamPreference preference, {
    required int quality,
    required int line,
  }) async {
    if (!isLive || media == null) return;
    await open(
      null,
      null,
      quality: quality,
      liveLine: line,
      liveStream: preference,
      force: true,
      desiredPlaying: _desiredPlaying,
      volume: snapshots.value.volume,
      target: contentTarget,
      title: contentTitle,
    );
  }

  Future<void> changeVoice(PlaybackVoice voice) async {
    final video = detail;
    final selected = part;
    if (_disposed ||
        _closing ||
        contentTarget != null ||
        video == null ||
        selected == null ||
        repository is! VoicePlaybackRepository) {
      return;
    }
    final option = voice.isOriginal
        ? const PlaybackVoice.original()
        : voiceTracks.where((track) => track.key == voice.key).firstOrNull;
    if (option == null || (option.key == _voice.key && media != null)) return;
    if (_subtitlePreference != '__off__' &&
        (_subtitlePreference != null || _settings.subtitlesEnabled) &&
        option.subtitleLanguage.isNotEmpty) {
      _subtitlePreference = option.subtitleLanguage;
    }
    await open(
      video,
      selected,
      voice: option,
      quality: _quality,
      force: true,
      position: media == null ? _openingPosition : snapshots.value.position,
      rate:
          _temporaryRateOriginal ??
          (media == null ? _openingRate : snapshots.value.rate),
      volume: media == null ? _openingVolume : snapshots.value.volume,
      desiredPlaying: _desiredPlaying,
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
    _audioRecovery = null;
    _audioOnly = false;
    _nextSourceIntent = null;
    if (clearCheckpoints) {
      _checkpoints.clear();
      _navigationCheckpoints.clear();
    }
    _activeOwner = null;
    _openingPosition = null;
    _temporaryRateOriginal = null;
    _temporaryRateGeneration = null;
    _temporaryRateRevision++;
    _subtitlePreference = null;
    _voice = const PlaybackVoice.original();
    _voices = const [];
    subtitleLoading = false;
    subtitleMessage = null;
    final generation = ++_generation;
    subtitleTracks = const [];
    subtitleCues = const [];
    selectedSubtitle = -1;
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
    _commentRefreshRequest = null;
    // Capture the old progress before invalidating the source. A same-source
    // reopen during the write must advance generation instead of reusing it.
    final savedProgress = _saveProgress();
    _cancelCloudResume();
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
    await attempt(() async => _historyReporter?.close());
    _disposed = true;
    for (final subscription in _subscriptions) {
      await attempt(subscription.cancel);
    }
    final playbackCommands = _playbackCommands;
    if (playbackCommands != null) await attempt(() => playbackCommands);
    await attempt(engine.dispose);
    await attempt(() async => snapshots.dispose());
    await attempt(() async => highEnergy.dispose());
    await attempt(() async => danmaku.dispose());
    _clock.stop();
    super.dispose();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
  }
}

// A resolution owns one opening budget, including the first audio decode.
// Paused user time is excluded, and a deferred first play keeps the same attempts.
final class _PlaybackStartupRecovery {
  static const totalBudget = Duration(seconds: 35);
  static const primaryBudget = Duration(seconds: 6);

  _PlaybackStartupRecovery({
    required this.now,
    required this.hasBackup,
    required this.isCurrent,
  });

  final Duration Function() now;
  final bool hasBackup;
  final bool Function() isCurrent;
  late final Future<void> Function(PlaybackSnapshot) reopen;
  int attempts = 0;
  bool preparing = false;
  Duration _elapsed = Duration.zero;
  Duration? _startedAt;

  Duration get elapsed =>
      _elapsed +
      switch (_startedAt) {
        final started? => now() - started,
        null => Duration.zero,
      };
  Duration get remaining =>
      (hasBackup && attempts == 1 ? primaryBudget : totalBudget) - elapsed;
  Duration get totalRemaining => totalBudget - elapsed;
  bool get canRetry =>
      hasBackup && attempts < 2 && totalRemaining > Duration.zero;

  void start() => _startedAt ??= now();
  void stop() {
    _elapsed = elapsed;
    _startedAt = null;
  }
}

final class _PlaybackCheckpoint {
  const _PlaybackCheckpoint({
    required this.videoId,
    required this.cid,
    required this.scope,
    required this.epoch,
    required this.position,
    required this.rate,
    required this.volume,
    required this.quality,
    this.liveLine = 0,
    this.liveStream = LiveStreamPreference.automatic,
    required this.desiredPlaying,
    this.subtitleLabel,
    this.target,
    this.voice = const PlaybackVoice.original(),
    this.audioOnly = false,
  });
  final VideoId? videoId;
  final String? cid;
  final ContentPlaybackTarget? target;
  final String scope;
  final int epoch;
  final Duration? position;
  final double rate;
  final double volume;
  final int quality;
  final int liveLine;
  final LiveStreamPreference liveStream;
  final bool desiredPlaying;
  final String? subtitleLabel;
  final PlaybackVoice voice;
  final bool audioOnly;
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

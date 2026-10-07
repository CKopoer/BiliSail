import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/input/input_stroke.dart';
import '../../../core/input/shortcut_dispatcher.dart';
import '../../../domain/playback_rates.dart';
import '../../settings/domain/shortcut_settings.dart';
import 'playback_session.dart';

enum _RateHoldInput { keyboard, touch }

/// One controller per PlaybackPanel owner, shared by inline/fullscreen views.
final class PlaybackShortcutController extends ChangeNotifier {
  PlaybackShortcutController({
    required this.session,
    required this.settings,
    required this.active,
    required this.fullscreen,
    required this.toggleFullscreen,
    required this.toggleDanmaku,
    required this.volumeFeedback,
    this.timer = Timer.new,
  }) {
    session.addListener(_sourceChanged);
  }
  final PlaybackSession session;
  final ShortcutSettings Function() settings;
  final bool Function() active, fullscreen;
  final void Function() toggleFullscreen, toggleDanmaku;
  final void Function(double) volumeFeedback;
  final Timer Function(Duration, void Function()) timer;
  Timer? _hold, _feedback;
  int? _holdGeneration;
  _RateHoldInput? _holdInput;
  bool _accelerating = false, rateFeedback = false, _disposed = false;
  bool get isHoldingRate => _accelerating;
  double _savedVolume = 100;
  Set<ShortcutAction> get capabilities => {
    ShortcutAction.playPause,
    ShortcutAction.fullscreen,
    if (fullscreen()) ShortcutAction.exitFullscreen,
    ShortcutAction.volumeUp,
    ShortcutAction.volumeDown,
    ShortcutAction.mute,
    if (!session.isLive) ...{
      ShortcutAction.seekBack,
      ShortcutAction.seekForward,
      ShortcutAction.seekLarge,
      ShortcutAction.slower,
      ShortcutAction.faster,
      ShortcutAction.toggleRate,
      ShortcutAction.danmaku,
      ShortcutAction.subtitles,
    },
  };
  void _sourceChanged() {
    if (_holdGeneration != null &&
        _holdGeneration != session.sourceGeneration) {
      cancel();
    }
  }

  void cancel() {
    _hold?.cancel();
    _hold = null;
    final generation = _holdGeneration;
    _holdGeneration = null;
    _holdInput = null;
    final accelerating = _accelerating;
    if (_accelerating && generation == session.sourceGeneration) {
      unawaited(
        session.endTemporaryRate(
          expectedGeneration: session.snapshots.value.generation,
        ),
      );
    }
    _accelerating = false;
    if (accelerating && !_disposed) notifyListeners();
  }

  void _beginRateHold() {
    // Record the hold before awaiting the engine so early release restores
    // even a pending rate change.
    _accelerating = true;
    unawaited(session.beginTemporaryRate(settings().holdRate));
    notifyListeners();
  }

  void prepareTouchHold() {
    // Register at pointer down so navigation, focus or source changes can
    // invalidate the gesture before the recognizer's deadline is reached.
    if (_disposed || !active() || session.isLive) return;
    cancel();
    _holdInput = _RateHoldInput.touch;
    _holdGeneration = session.sourceGeneration;
  }

  void beginTouchHold() {
    if (_disposed ||
        !active() ||
        session.isLive ||
        _holdInput != _RateHoldInput.touch ||
        _holdGeneration != session.sourceGeneration) {
      return;
    }
    _beginRateHold();
  }

  void endTouchHold() {
    if (_holdInput == _RateHoldInput.touch) cancel();
  }

  Future<CommandOutcome> execute(
    ShortcutAction action,
    InputStroke stroke,
  ) async {
    if (_disposed || !active()) return CommandOutcome.stale;
    final generation = session.sourceGeneration;
    if (action == ShortcutAction.seekForward &&
        stroke.device == InputDevice.keyboard) {
      if (stroke.phase == InputPhase.down) {
        cancel();
        _holdInput = _RateHoldInput.keyboard;
        _holdGeneration = generation;
        _hold = timer(Duration(milliseconds: settings().holdDelayMs), () {
          if (_disposed ||
              !active() ||
              _holdGeneration != session.sourceGeneration) {
            cancel();
            return;
          }
          _beginRateHold();
        });
      } else if (stroke.phase == InputPhase.up &&
          _holdInput == _RateHoldInput.keyboard) {
        final short = !_accelerating && _holdGeneration == generation;
        cancel();
        if (short) {
          await session.seek(
            session.snapshots.value.position +
                Duration(seconds: settings().seekSeconds),
          );
        }
      }
      return CommandOutcome.completed;
    }
    if (stroke.phase == InputPhase.up) return CommandOutcome.noOp;
    switch (action) {
      case ShortcutAction.playPause:
        await (session.error != null
            ? session.retry()
            : session.togglePlaying());
      case ShortcutAction.fullscreen:
        cancel();
        toggleFullscreen();
      case ShortcutAction.exitFullscreen:
        if (!fullscreen()) return CommandOutcome.noOp;
        cancel();
        toggleFullscreen();
      case ShortcutAction.seekBack:
        await session.seek(
          session.snapshots.value.position -
              Duration(seconds: settings().seekSeconds),
        );
      case ShortcutAction.seekForward:
        await session.seek(
          session.snapshots.value.position +
              Duration(seconds: settings().seekSeconds),
        );
      case ShortcutAction.seekLarge:
        await session.seek(
          session.snapshots.value.position + const Duration(seconds: 90),
        );
      case ShortcutAction.volumeUp:
        await session.setVolume((session.commandVolume + 5).clamp(0, 100));
      case ShortcutAction.volumeDown:
        await session.setVolume((session.commandVolume - 5).clamp(0, 100));
      case ShortcutAction.mute:
        final volume = session.commandVolume;
        if (volume > 0) _savedVolume = volume;
        await session.setVolume(volume > 0 ? 0 : _savedVolume);
      case ShortcutAction.slower:
        await session.setRate(PlaybackRates.slower(session.commandRate));
      case ShortcutAction.faster:
        await session.setRate(PlaybackRates.faster(session.commandRate));
      case ShortcutAction.toggleRate:
        await session.setRate(session.commandRate == 1 ? 2 : 1);
      case ShortcutAction.danmaku:
        toggleDanmaku();
      case ShortcutAction.subtitles:
        await session.selectSubtitle(
          session.selectedSubtitle < 0 && session.subtitleTracks.isNotEmpty
              ? 0
              : -1,
        );
      default:
        return CommandOutcome.noOp;
    }
    if (_disposed || !active() || session.sourceGeneration != generation) {
      return CommandOutcome.stale;
    }
    if (session.error != null) return CommandOutcome.failed;
    if ({
      ShortcutAction.volumeUp,
      ShortcutAction.volumeDown,
      ShortcutAction.mute,
    }.contains(action)) {
      volumeFeedback(session.snapshots.value.volume);
    }
    if ({
      ShortcutAction.slower,
      ShortcutAction.faster,
      ShortcutAction.toggleRate,
    }.contains(action)) {
      _feedback?.cancel();
      rateFeedback = true;
      notifyListeners();
      _feedback = timer(const Duration(milliseconds: 1500), () {
        rateFeedback = false;
        notifyListeners();
      });
    }
    return CommandOutcome.completed;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    _feedback?.cancel();
    session.removeListener(_sourceChanged);
    super.dispose();
  }
}

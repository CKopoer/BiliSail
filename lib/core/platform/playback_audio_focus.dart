import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';

enum PlaybackAudioEvent {
  interrupt,
  resume,
  endWithoutResume,
  stop,
  duck,
  unduck,
}

typedef PlaybackAudioListener = void Function(PlaybackAudioEvent);

/// All audible tabs in a mobile process share one OS audio session.
class PlaybackAudioFocus {
  PlaybackAudioFocus({
    required this.events,
    required this.setActive,
    this.abandonBeforeReclaim = false,
  });

  final Stream<PlaybackAudioEvent> events;
  final Future<bool> Function(bool) setActive;
  final bool abandonBeforeReclaim;
  final _owners = <PlaybackAudioListener>{};
  StreamSubscription<PlaybackAudioEvent>? _subscription;
  Future<void> _commands = Future.value();
  bool _active = false;
  bool _interrupted = false;
  bool _ducked = false;
  int _lossRevision = 0;

  static Future<PlaybackAudioFocus?> mobile() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    return PlaybackAudioFocus.fromSession(
      await AudioSession.instance,
      android: Platform.isAndroid,
    );
  }

  factory PlaybackAudioFocus.fromSession(
    AudioSession session, {
    required bool android,
  }) {
    return PlaybackAudioFocus(
      abandonBeforeReclaim: android,
      // The plugin configures its music/playback fallback on first activation.
      setActive: (active) => session.setActive(active),
      events: Stream.multi((controller) {
        final interruptions = session.interruptionEventStream.listen((event) {
          controller.add(switch ((event.begin, event.type)) {
            (true, AudioInterruptionType.duck) => PlaybackAudioEvent.duck,
            (false, AudioInterruptionType.duck) => PlaybackAudioEvent.unduck,
            (false, AudioInterruptionType.pause) => PlaybackAudioEvent.resume,
            (false, AudioInterruptionType.unknown) =>
              PlaybackAudioEvent.endWithoutResume,
            (true, AudioInterruptionType.unknown) when android =>
              PlaybackAudioEvent.stop, // Permanent Android focus loss.
            _ => PlaybackAudioEvent.interrupt,
          });
        });
        final noisy = session.becomingNoisyEventStream.listen(
          (_) => controller.add(PlaybackAudioEvent.stop),
        );
        controller.onCancel = () async {
          await Future.wait([interruptions.cancel(), noisy.cancel()]);
        };
      }, isBroadcast: true),
    );
  }

  void _onEvent(PlaybackAudioEvent event) {
    if (event == PlaybackAudioEvent.interrupt ||
        event == PlaybackAudioEvent.stop) {
      _active = false;
      _interrupted = true;
      _ducked = false;
      ++_lossRevision;
    } else if (event == PlaybackAudioEvent.resume) {
      _interrupted = false;
    } else if (event == PlaybackAudioEvent.duck ||
        event == PlaybackAudioEvent.unduck) {
      _ducked = event == PlaybackAudioEvent.duck;
    }
    for (final listener in _owners.toList()) {
      listener(event);
    }
  }

  Future<bool> _activate(bool active) async {
    try {
      return await setActive(active).timeout(const Duration(seconds: 3));
    } on Exception {
      debugPrint('Unable to change mobile playback audio focus.');
      return false;
    }
  }

  Future<bool> request(PlaybackAudioListener owner) {
    if (_owners.add(owner) && _ducked) owner(PlaybackAudioEvent.duck);
    _subscription ??= events.listen(_onEvent);
    final revision = _lossRevision;
    final operation = _commands.then((_) async {
      if (!_owners.contains(owner) || revision != _lossRevision) return false;
      if (_active) return true;
      // audio_session caches Android requests, including a transiently lost
      // one. A user pressing play before focus gain needs a fresh request.
      if (_interrupted && abandonBeforeReclaim) await _activate(false);
      if (!_owners.contains(owner) || revision != _lossRevision) return false;
      _interrupted = false;
      final granted = await _activate(true);
      if (!granted && abandonBeforeReclaim) await _activate(false);
      if (revision != _lossRevision) return false;
      _active = granted;
      return granted && _owners.contains(owner);
    });
    _commands = operation.then((_) {});
    return operation;
  }

  Future<void> release(PlaybackAudioListener owner) {
    if (!_owners.remove(owner) || _owners.isNotEmpty) return _commands;
    final operation = _commands.then((_) async {
      if (_owners.isNotEmpty) return;
      final subscription = _subscription;
      _subscription = null;
      _active = false;
      _interrupted = false;
      _ducked = false;
      await subscription?.cancel();
      await _activate(false);
    });
    _commands = operation;
    return operation;
  }
}

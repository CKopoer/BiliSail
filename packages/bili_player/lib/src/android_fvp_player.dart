import 'dart:async';

import 'package:flutter/services.dart';

import 'fvp_native_player.dart';
import 'fvp_information_message.dart';
import 'player_contract.dart';
import 'player_playback_information.dart';

/// A native fault kills the Android worker, while the UI keeps its session.
final class FvpProcessException implements Exception {
  const FvpProcessException();
}

final class AndroidFvpPlayer
    implements
        FvpPlayerPort,
        FvpInformationPort,
        FvpAudioActivityPort,
        FvpAudioClockPort,
        FvpCommandCompletionPort,
        FvpPauseConfirmationPort {
  AndroidFvpPlayer._(this._id);

  static const channel = MethodChannel('dev.bilisail/fvp_process');
  static const _events = EventChannel('dev.bilisail/fvp_process/events');
  static final _players = <int, AndroidFvpPlayer>{};
  static StreamSubscription<Object?>? _subscription;
  final int _id;
  final _statuses = StreamController<FvpNativeStatus>.broadcast(sync: true);
  int _position = 0, _buffered = 0;
  int _decodedAudioFrames = 0;
  int? _audioPosition;
  @override
  int? get audioPositionMilliseconds => _audioPosition;
  int _seekRevision = 0;
  bool _closed = false, _lost = false;
  int? exitStatus;
  Future<void>? _disposal;

  static Future<FvpPlayerPort> create() async {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map<Object?, Object?>) return;
        final player = _players[event['player']];
        if (player == null || player._closed) return;
        if (event['kind'] == 'processExited') {
          if (event['exitStatus'] case final int status) {
            player.exitStatus = status;
          }
          player._processExited();
        } else if (event['kind'] == 'status') {
          if ((event['seekRevision'] ?? 0) != player._seekRevision) return;
          final name = event['status'];
          final status = FvpNativeStatus.values
              .where((s) => s.name == name)
              .firstOrNull;
          if (status != null) player._statuses.add(status);
        } else if (event['kind'] == 'sample') {
          if ((event['seekRevision'] ?? 0) != player._seekRevision) return;
          if (event['position'] case final int value) player._position = value;
          if (event['buffered'] case final int value) player._buffered = value;
          if (event['audioFrames'] case final int value) {
            player._decodedAudioFrames = value;
          }
          player._audioPosition = event['audioPosition'] as int?;
        }
      },
      onError: (Object _) {
        for (final player in _players.values.toList()) {
          player._processExited();
        }
      },
    );
    int? id;
    try {
      id = await channel.invokeMethod<int>('create');
    } on PlatformException catch (error) {
      if (error.code == 'native_process_exited' ||
          error.code == 'native_process_timeout') {
        throw const FvpProcessException();
      }
      rethrow;
    }
    if (id == null) throw const FvpProcessException();
    final player = AndroidFvpPlayer._(id);
    _players[id] = player;
    return player;
  }

  void _processExited() {
    if (_closed || _lost) return;
    _lost = true;
    _statuses.add(FvpNativeStatus.processExited);
  }

  Future<Object?> _call(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    if (_lost && method != 'dispose') throw const FvpProcessException();
    if (_closed && method != 'dispose') throw StateError('Player disposed');
    try {
      return await channel.invokeMethod<Object?>(method, {
        'player': _id,
        ...args,
      });
    } on PlatformException catch (error) {
      if (error.code == 'native_process_exited' ||
          error.code == 'native_process_timeout') {
        _processExited();
        throw const FvpProcessException();
      }
      rethrow;
    }
  }

  void _command(String method, [Map<String, Object?> args = const {}]) {
    if (_closed || _lost) return;
    unawaited(
      _call(method, args).then<void>(
        (_) {},
        onError: (Object error) {
          if (!_closed && !_lost) _statuses.add(FvpNativeStatus.invalid);
        },
      ),
    );
  }

  @override
  Stream<FvpNativeStatus> get statuses => _statuses.stream;
  @override
  int get positionMilliseconds => _position;
  @override
  int get bufferedMilliseconds => _buffered;
  @override
  int get decodedAudioFrames => _decodedAudioFrames;

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation({
    required int generation,
    required double audioGainDb,
  }) async => decodeFvpInformation(
    await _call('information', {'generation': generation, 'gain': audioGainDb}),
  );

  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    bool isLive = false,
  }) async {
    Map<String, Object?> track(MediaTrack value) => {
      'uri': value.uri.toString(),
      'headers': value.requestPolicy.headers,
    };
    final result = await _call('prepare', {
      'media': track(media),
      if (audio != null) 'audio': track(audio),
      'silent': silent,
      'live': isLive,
      'start': options.startPosition.inMilliseconds,
      'software': options.videoDecoding == VideoDecodingMode.software,
      'directSurface':
          options.androidVideoOutput == AndroidVideoOutputMode.directTexture &&
          options.videoDecoding == VideoDecodingMode.automatic,
      'rate': options.rate,
      'volume': options.volume,
      'gain': options.audioGainDb,
      'buffer': options.maxBufferAhead.inMilliseconds,
      'timeout': options.openTimeout.inMilliseconds,
    });
    if (result case {
      'duration': final int duration,
      'width': final int width,
      'height': final int height,
      'audio': final bool hasAudio,
    }) {
      return FvpMediaInfo(
        duration: Duration(milliseconds: duration),
        dimensions: width > 0 && height > 0
            ? VideoDimensions(width, height)
            : null,
        hasAudio: hasAudio,
        hasVideo: result['video'] as bool?,
        directSurface: result['direct'] == true,
      );
    }
    throw StateError('Invalid worker media information');
  }

  @override
  Future<int> createTexture() async => (await _call('texture')) as int;
  @override
  Future<bool> confirmVideoFrame() async => await _call('confirmVideo') == true;
  @override
  Future<bool> confirmAudio() async => await _call('confirmAudio') == true;
  @override
  void play() => _command('play');
  @override
  Future<void> playAndWait() async => await _call('play');
  @override
  void pause() => _command('pause');
  @override
  Future<void> pauseAndWait() async => await _call('pause');
  @override
  Future<bool> pauseAndConfirm() async => await _call('pause') == true;
  @override
  void interrupt() => _command('interrupt');
  @override
  Future<int> seek(Duration target) async {
    final revision = ++_seekRevision;
    final result = (await _call('seek', {
      'position': target.inMilliseconds,
      'seekRevision': revision,
    })) as int;
    if (revision == _seekRevision && result >= 0) _position = result;
    return result;
  }

  @override
  Future<void> cancelSeek() async => await _call('cancelSeek');
  @override
  void setRate(double rate) => _command('rate', {'value': rate});
  @override
  Future<void> setRateAndWait(double rate) async =>
      await _call('rate', {'value': rate});
  @override
  void setVolume(double volume, double gainDb) =>
      _command('volume', {'value': volume, 'gain': gainDb});
  @override
  Future<void> setVolumeAndWait(double volume, double gainDb) async =>
      await _call('volume', {'value': volume, 'gain': gainDb});
  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    if (_closed) return;
    try {
      // The local Binder host must also discard its lost-player bookkeeping.
      await _call('dispose');
    } on FvpProcessException {
      // The dead process already released its native handles and descriptors.
    } finally {
      _closed = true;
      _players.remove(_id);
      await _statuses.close();
    }
  }
}

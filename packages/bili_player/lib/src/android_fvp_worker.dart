import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'android_media_leases.dart';
import 'fvp_native_player.dart';
import 'fvp_information_message.dart';
import 'player_contract.dart';

/// Runs exclusively in :fvp_player. All inputs live in memory in this process.
void runFvpWorker(
  Future<FvpPlayerPort> Function() create,
  int Function(FvpPlayerPort) nativeHandle,
  void Function(FvpPlayerPort) frameConsumed,
) {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.bilisail/fvp_worker');
  final players = <int, _WorkerPlayer>{};
  Future<void> event(int id, Map<String, Object?> value) async {
    await channel.invokeMethod<void>('event', {'player': id, ...value});
  }

  channel.setMethodCallHandler((call) async {
    final args = Map<String, Object?>.from(call.arguments as Map);
    final id = args['player'] as int;
    if (call.method == 'create') {
      if (players.length >= 16) throw StateError('Player limit reached');
      final port = await create();
      final owned = _WorkerPlayer(port);
      players[id] = owned;
      owned.subscription = port.statuses.listen((status) {
        if (owned.seeking) return;
        unawaited(
          event(id, {
            'kind': 'status',
            'seekRevision': owned.seekRevision,
            'status': status.name,
          }),
        );
      });
      owned.timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (owned.seeking) return;
        unawaited(
          event(id, {
            'kind': 'sample',
            'seekRevision': owned.seekRevision,
            'position': port.positionMilliseconds,
            'buffered': port.bufferedMilliseconds,
            if (port is FvpAudioClockPort)
              'audioPosition':
                  (port as FvpAudioClockPort).audioPositionMilliseconds,
            if (port is FvpAudioActivityPort)
              'audioFrames': (port as FvpAudioActivityPort).decodedAudioFrames,
          }),
        );
      });
      return null;
    }
    final owned = players[id];
    if (owned == null && call.method == 'frameConsumed') return null;
    if (owned == null) throw StateError('Player unavailable');
    final port = owned.port;
    switch (call.method) {
      case 'frameConsumed':
        if (owned.directSurface) frameConsumed(port);
        return null;
      case 'information':
        if (port is! FvpInformationPort) return null;
        final info = await (port as FvpInformationPort)
            .inspectPlaybackInformation(
              generation: args['generation'] as int,
              audioGainDb: (args['gain'] as num).toDouble(),
            );
        return info == null ? null : encodeFvpInformation(info);
      case 'prepare':
        owned.directSurface =
            args['directSurface'] == true && args['software'] != true;
        MediaTrack track(Object? value) {
          final map = Map<String, Object?>.from(value as Map);
          return MediaTrack(
            uri: Uri.parse(map['uri'] as String),
            requestPolicy: MediaRequestPolicy(
              headers: Map<String, String>.from(map['headers'] as Map),
            ),
          );
        }
        Future<MediaTrack> lease(MediaTrack track) async {
          final opened = await owned.leases.open(track);
          if (owned.closing) {
            await owned.leases.close();
            throw StateError('Player preparation cancelled');
          }
          return opened;
        }
        final media = await lease(track(args['media']));
        final originalAudio = args['audio'] == null
            ? null
            : track(args['audio']);
        final audio = originalAudio == null ? null : await lease(originalAudio);
        final info = await port.prepare(
          media,
          audio,
          OpenOptions(
            startPosition: Duration(milliseconds: args['start'] as int),
            rate: (args['rate'] as num).toDouble(),
            volume: (args['volume'] as num).toDouble(),
            audioGainDb: (args['gain'] as num).toDouble(),
            videoDecoding: args['software'] == true
                ? VideoDecodingMode.software
                : VideoDecodingMode.automatic,
            androidVideoOutput: args['directSurface'] == true
                ? AndroidVideoOutputMode.directTexture
                : AndroidVideoOutputMode.renderedTexture,
            maxBufferAhead: Duration(milliseconds: args['buffer'] as int),
            openTimeout: Duration(milliseconds: args['timeout'] as int),
          ),
          silent: args['silent'] == true,
          isLive: args['live'] == true,
        );
        owned.directSurface = info.directSurface;
        return {
          'duration': info.duration.inMilliseconds,
          'width': info.dimensions?.width ?? 0,
          'height': info.dimensions?.height ?? 0,
          'audio': info.hasAudio,
          'video': info.hasVideo,
          'direct': info.directSurface,
        };
      case 'surface':
        await channel.invokeMethod<void>('bindSurface', {
          'player': id,
          'handle': nativeHandle(port),
          'direct': owned.directSurface,
        });
        return null;
      case 'confirmVideo':
        return port.confirmVideoFrame();
      case 'confirmAudio':
        return port.confirmAudio();
      case 'play':
        port.play();
      case 'pause':
        if (port is FvpPauseConfirmationPort) {
          return await (port as FvpPauseConfirmationPort).pauseAndConfirm();
        }
        await port.pauseAndWait();
        return true;
      case 'interrupt':
        port.interrupt();
      case 'cancelSeek':
        await port.cancelSeek();
      case 'seek':
        final revision = args['seekRevision'] as int;
        owned.seekRevision = revision;
        owned.seeking = true;
        try {
          return await port.seek(
            Duration(milliseconds: args['position'] as int),
          );
        } finally {
          if (owned.seekRevision == revision) owned.seeking = false;
        }
      case 'rate':
        port.setRate((args['value'] as num).toDouble());
      case 'volume':
        port.setVolume(
          (args['value'] as num).toDouble(),
          (args['gain'] as num).toDouble(),
        );
      case 'dispose':
        owned.closing = true;
        port.interrupt();
        owned.timer?.cancel();
        // Detach the borrowed Surface before destroying the MDK player.
        await channel.invokeMethod<void>('unbindSurface', {'player': id});
        await port.dispose();
        await owned.subscription?.cancel();
        await owned.leases.close();
        players.remove(id);
      default:
        throw UnsupportedError('Unknown worker command');
    }
    return null;
  });
  unawaited(channel.invokeMethod<void>('ready'));
}

final class _WorkerPlayer {
  _WorkerPlayer(this.port);
  final FvpPlayerPort port;
  final leases = AndroidMediaLeases();
  StreamSubscription<FvpNativeStatus>? subscription;
  Timer? timer;
  bool closing = false;
  bool directSurface = false;
  int seekRevision = 0;
  bool seeking = false;
}

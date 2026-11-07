import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// Source hooks require synchronous calls so they never await a reply on the
/// event loop they are holding. Native access stays within this adapter.
extension NativePlayerProperties on mk.Player {
  mk.NativePlayer get native => platform as mk.NativePlayer;
  int get nativeHandle => native.ctx.address;

  Future<void> setPropertyAsync(String name, String value) =>
      native.setProperty(name, value);

  Future<String> getPropertyAsync(String name) => native.getProperty(name);

  void setProperty(String name, String value) {
    final player = native;
    if (player.disposed) throw StateError('Native player is disposed.');
    final key = name.toNativeUtf8();
    final data = value.toNativeUtf8();
    try {
      final result = player.mpv.mpv_set_property_string(
        player.ctx,
        key.cast(),
        data.cast(),
      );
      if (result < 0) {
        throw StateError('Native property $name failed ($result).');
      }
    } finally {
      calloc.free(key);
      calloc.free(data);
    }
  }

  String getProperty(String name) {
    final player = native;
    if (player.disposed) throw StateError('Native player is disposed.');
    final key = name.toNativeUtf8();
    try {
      final data = player.mpv.mpv_get_property_string(player.ctx, key.cast());
      if (data == nullptr) return '';
      try {
        return data.cast<Utf8>().toDartString();
      } finally {
        player.mpv.mpv_free(data.cast());
      }
    } finally {
      calloc.free(key);
    }
  }
}

Future<mk.Player> createNativePlayer() async {
  final player = mk.Player(
    configuration: const mk.PlayerConfiguration(logLevel: mk.MPVLogLevel.warn),
  );
  try {
    await player.handle;
    return player;
  } on Object {
    await player.dispose();
    rethrow;
  }
}

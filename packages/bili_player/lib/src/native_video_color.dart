import 'dart:convert';

/// The OpenGL libmpv render API cannot reshape Dolby Vision Profile 5's
/// IPTPQc2 base layer. Convert its RPU-tagged frames before that renderer.
/// Flutter's embedded texture is SDR; this is not Dolby Vision passthrough.
const dolbyVisionSdrFilter =
    '@bilisail_dovi:lavfi=['
    'libplacebo=apply_dolbyvision=1:colorspace=bt709:'
    'color_primaries=bt709:color_trc=iec61966-2-1:format=yuv420p10le]';

/// Configures paused output after track discovery, before presentation is
/// admitted. Uses demuxer metadata, including local media without a codec tag.
bool configureNativeVideoColor({
  required String Function(String) read,
  required void Function(String, String) write,
  bool isAndroid = false,
  void Function()? onAndroidDolbyVision,
  String? codecHint,
}) {
  final count = int.tryParse(read('track-list/count')) ?? 0;
  // A malformed container must not cause an unbounded native property walk.
  if (count < 0 || count > 128) {
    throw StateError('Too many native media tracks.');
  }
  var needsReshaping = false;
  var hasProfile = false;
  for (var index = 0; index < count; index++) {
    final track = 'track-list/$index';
    if (read('$track/type') != 'video' || read('$track/albumart') == 'yes') {
      continue;
    }
    final profile = read('$track/dolby-vision-profile');
    hasProfile |= profile.isNotEmpty;
    if (profile == '5') {
      needsReshaping = true;
      break;
    }
  }
  // Older libmpv builds lack the demuxed profile property. A supplied DV codec
  // must still go through a Dolby-aware path rather than ordinary YUV output.
  needsReshaping |= !hasProfile && isDolbyVisionCodec(codecHint);
  if (!needsReshaping) return false;

  final requiredChoice = isAndroid ? 'gpu-next' : 'libplacebo';
  final option = isAndroid ? 'vo' : 'vf';
  if (!nativeOptionChoices(read('option-info/$option'))
      .contains(requiredChoice)) {
    throw StateError('Dolby Vision color conversion is unavailable.');
  }

  if (isAndroid) {
    // MediaCodec's opaque/copy decoders do not forward the RPU to libplacebo.
    // The native HEVC decoder retains it. Only this source changes renderer.
    onAndroidDolbyVision?.call();
    write('hwdec', 'no');
    write('vo', 'gpu-next');
    write('target-prim', 'bt.709');
    write('target-trc', 'srgb');
    if (read('hwdec') != 'no' || read('vo') != 'gpu-next') {
      throw StateError('Dolby Vision renderer configuration failed.');
    }
    return true;
  }

  // libplacebo's lavfi bridge takes software frames. Keep hardware decoding
  // when requested, with a download before Vulkan processing. Other media
  // retains the SDK's direct hardware path; explicit software stays software.
  if (read('hwdec') != 'no') {
    write('hwdec', 'auto-copy');
    if (read('hwdec') != 'auto-copy') {
      throw StateError('Dolby Vision decoder configuration failed.');
    }
  }
  write('vf', dolbyVisionSdrFilter);
  if (!read('vf').contains('@bilisail_dovi:lavfi')) {
    throw StateError('Dolby Vision color conversion is unavailable.');
  }
  return true;
}

bool isDolbyVisionCodec(String? codec) {
  final value = codec?.toLowerCase() ?? '';
  return value.startsWith('dvh1') || value.startsWith('dvhe');
}

/// Public mpv option introspection, without calling a private FFmpeg ABI.
Set<String> nativeOptionChoices(String info) {
  if (info.isEmpty) return const {};
  final Object? decoded = jsonDecode(info);
  if (decoded case {'choices': final List<Object?> choices}) {
    return choices.whereType<String>().toSet();
  }
  return const {};
}

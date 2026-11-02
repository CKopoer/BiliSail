/// The OpenGL libmpv render API cannot reshape Dolby Vision Profile 5's
/// IPTPQc2 base layer. Convert its RPU-tagged frames before that renderer.
/// Flutter's embedded texture is SDR; this is not Dolby Vision passthrough.
const dolbyVisionSdrFilter =
    '@bilisail_dovi:lavfi=['
    'libplacebo=apply_dolbyvision=1:colorspace=bt709:'
    'color_primaries=bt709:color_trc=iec61966-2-1:format=yuv420p10le]';

/// Runs in on_preloaded, before track selection and decoder initialization.
/// Uses demuxer metadata, including local media without a supplied codec tag.
void configureNativeVideoColor({
  required String Function(String) read,
  required void Function(String, String) write,
}) {
  final count = int.tryParse(read('track-list/count')) ?? 0;
  // A malformed container must not cause an unbounded native property walk.
  if (count < 0 || count > 128) {
    throw StateError('Too many native media tracks.');
  }
  var needsReshaping = false;
  for (var index = 0; index < count; index++) {
    final track = 'track-list/$index';
    if (read('$track/type') == 'video' &&
        read('$track/dolby-vision-profile') == '5' &&
        read('$track/albumart') != 'yes') {
      needsReshaping = true;
      break;
    }
  }
  if (!needsReshaping) return;

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
}

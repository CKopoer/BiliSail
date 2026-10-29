import 'video_codec.dart';

/// Only a stream's stable attributes are persisted, never its signed URLs.
final class LiveStreamPreference {
  const LiveStreamPreference({
    this.protocol = '',
    this.format = '',
    this.codec = '',
  });
  final String protocol, format, codec;
  bool get isAutomatic => protocol.isEmpty && format.isEmpty && codec.isEmpty;
  String get key => '$protocol/$format/$codec';
  String get label {
    if (isAutomatic) return '自动兼容';
    final protocolLabel = switch (protocol) {
      'http_hls' => 'HLS',
      'http_stream' => 'HTTP-FLV',
      _ => protocol,
    };
    final codecLabel = switch (VideoCodecPreference.fromCodec(codec)) {
      VideoCodecPreference.h264 => 'H.264',
      VideoCodecPreference.hevc => 'HEVC',
      VideoCodecPreference.av1 => 'AV1',
      VideoCodecPreference.dolbyVision => '杜比视界',
      null => codec,
    };
    return '$protocolLabel · ${format == 'fmp4' ? 'fMP4' : format.toUpperCase()} · $codecLabel';
  }

  static const automatic = LiveStreamPreference();
  static LiveStreamPreference fromJson(Object? value) {
    if (value is! Map<String, Object?>) return automatic;
    final protocol = value['protocol'];
    final format = value['format'];
    final codec = value['codec'];
    if (protocol is! String ||
        format is! String ||
        codec is! String ||
        !const ['http_hls', 'http_stream'].contains(protocol) ||
        !const ['fmp4', 'ts', 'flv'].contains(format) ||
        !RegExp(r'^[a-zA-Z0-9._-]{1,128}$').hasMatch(codec) ||
        VideoCodecPreference.fromCodec(codec) == null) {
      return automatic;
    }
    return LiveStreamPreference(
      protocol: protocol,
      format: format,
      codec: codec,
    );
  }

  Map<String, String> toJson() => {
    'protocol': protocol,
    'format': format,
    'codec': codec,
  };
  @override
  bool operator ==(Object other) =>
      other is LiveStreamPreference && key == other.key;
  @override
  int get hashCode => key.hashCode;
}

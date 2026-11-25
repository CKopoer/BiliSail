import 'dart:async';

import 'package:flutter/services.dart';

bool isDolbyDigitalPlus(String? codec) => const {
  'ec-3',
  'ec+3',
  'eac3',
  'audio/eac3',
  'audio/eac3-joc',
}.contains(codec?.toLowerCase());

bool isAtmosProfile(String? profile) =>
    profile?.toLowerCase().contains('dolby atmos') == true ||
    profile?.toLowerCase() == 'audio/eac3-joc';

/// mpv owns the bitstream decoder and automatically retries decoded audio
/// when WASAPI cannot acquire exclusive access. Only opt in on an exact
/// carrier match: mpv otherwise also tries advertising DD+ as plain AC-3.
final class WindowsDolbyOutput {
  WindowsDolbyOutput({
    required this.write,
    required this.isCurrent,
    required this.rate,
    required this.volume,
    required this.gain,
  });
  static const _channel = MethodChannel('bilisail/audio_passthrough');
  final void Function(String, String) write;
  final bool Function() isCurrent;
  double rate, volume, gain;
  bool _accepts = false, _enabled = false, _checking = false, _stopped = false;
  Timer? _routes;

  Future<void> start() async {
    await _refresh();
    if (!_stopped && isCurrent()) {
      _routes = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (_checking || _stopped || !isCurrent()) return;
    _checking = true;
    try {
      try {
        _accepts =
            await _channel
                .invokeMethod<bool>('acceptsEac3')
                .timeout(const Duration(seconds: 1)) ==
            true;
      } on MissingPluginException {
        _accepts = false;
      } on PlatformException {
        _accepts = false;
      } on TimeoutException {
        _accepts = false;
      }
      // The native player may start closing during the route query. A failed
      // refresh leaves the last successful state available for the next poll.
      try {
        apply();
      } on StateError {
        return;
      }
    } finally {
      _checking = false;
    }
  }

  void apply() {
    final enable = _accepts && rate == 1 && volume == 100 && gain == 0;
    if (_stopped || !isCurrent() || _enabled == enable) return;
    write('audio-spdif', enable ? 'eac3' : '');
    _enabled = enable;
  }

  void stop() {
    _stopped = true;
    _routes?.cancel();
    _routes = null;
    _enabled = false;
  }
}

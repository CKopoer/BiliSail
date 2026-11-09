import 'dart:math' as math;

/// Convert each native packet queue to the same media timeline before taking
/// their intersection. Audio and video presentation clocks can differ.
int fvpBufferedMilliseconds({
  required int position,
  required int buffered,
  int? audioPosition,
  int? audioBuffered,
}) {
  final start = math.max<int>(0, position);
  var end = start + math.max<int>(0, buffered);
  if (audioPosition != null && audioBuffered != null) {
    end = math.min<int>(
      end,
      math.max<int>(0, audioPosition) + math.max<int>(0, audioBuffered),
    );
  }
  return math.max<int>(0, end - start);
}

/// MDK reports undecoded packet duration, which falls in decoder-sized steps
/// independently of the presentation clock. Suppress only sub-sample endpoint
/// jitter for display; native health and cached-seek decisions keep raw data.
final class FvpBufferDisplay {
  static const tolerance = Duration(milliseconds: 250);
  Duration? _position, _end;

  Duration update({
    required Duration position,
    required Duration buffered,
    required bool buffering,
  }) {
    final previous = _end;
    final previousPosition = _position;
    var end = buffered;
    if (!buffering &&
        previous != null &&
        previousPosition != null &&
        position >= previousPosition &&
        buffered - position > tolerance &&
        previous > buffered &&
        previous - buffered <= tolerance) {
      end = previous;
    }
    _position = position;
    _end = end;
    return end;
  }

  void reset() {
    _position = null;
    _end = null;
  }
}

import 'dart:typed_data';

/// Byte ranges and decode timestamps from an MP4 index, never a bitrate guess.
final class Mp4BufferSpan {
  const Mp4BufferSpan(this.offset, this.length, this.start, this.end);
  final int offset, length;
  final Duration start, end;
}

final class Mp4BufferIndex {
  Mp4BufferIndex(this.spans);
  final List<Mp4BufferSpan> spans;
  static const maximumMetadataBytes = 2 * 1024 * 1024;
  static const _maximumEntries = 262144;

  /// Only complete top-level sidx/moov boxes are inspected. An absent, nested,
  /// oversized or unsupported index stays unknown; bytes are never converted
  /// to media time using the nominal bitrate.
  static Mp4BufferIndex? parse(Uint8List prefix) {
    try {
      final root = _Box(ByteData.sublistView(prefix), 0, prefix.length);
      for (final box in root.children()) {
        try {
          final index = switch (box.type) {
            'sidx' => _sidx(box),
            'moov' => _moov(box),
            _ => null,
          };
          if (index != null) return index;
        } on FormatException {
          // Fragmented MP4 may have an empty/unsupported moov followed by sidx.
        } on RangeError {
          /* Try the next complete top-level index. */
        }
      }
    } on FormatException {
      return null;
    } on RangeError {
      return null;
    }
    return null;
  }

  static Duration _time(int ticks, int scale) {
    final seconds = ticks ~/ scale;
    if (seconds < -3153600000 || seconds > 3153600000) {
      throw const FormatException('MP4 timestamp outside supported timeline');
    }
    // Divide before multiplying so valid v1 timestamps cannot overflow int64.
    return Duration(
      microseconds:
          seconds * Duration.microsecondsPerSecond +
          ticks.remainder(scale) * Duration.microsecondsPerSecond ~/ scale,
    );
  }

  static Mp4BufferIndex? _sidx(_Box box) {
    final version = box.u8(0);
    if (version > 1) return null;
    final scale = box.u32(8);
    if (scale == 0) return null;
    var ticks = version == 0 ? box.u32(12) : box.u64(12);
    var offset = box.end + (version == 0 ? box.u32(16) : box.u64(20));
    final countOffset = version == 0 ? 22 : 30;
    final count = box.u16(countOffset);
    final spans = <Mp4BufferSpan>[];
    for (var i = 0; i < count; i++) {
      final p = countOffset + 2 + i * 12;
      final size = box.u32(p);
      final duration = box.u32(p + 4);
      if (size & 0x80000000 != 0 || size == 0 || duration == 0) return null;
      spans.add(
        Mp4BufferSpan(
          offset,
          size,
          _time(ticks, scale),
          _time(ticks + duration, scale),
        ),
      );
      offset += size;
      ticks += duration;
    }
    return spans.isEmpty ? null : Mp4BufferIndex(spans);
  }

  static Mp4BufferIndex? _moov(_Box moov) {
    final tracks = moov.children().where((b) => b.type == 'trak').toList();
    if (tracks.length != 1) return null;
    final track = tracks.single;
    final media = track.child('mdia');
    final header = media.child('mdhd');
    final scale = header.u32(header.u8(0) == 1 ? 20 : 12);
    if (scale == 0) return null;
    final table = media.child('minf').child('stbl');
    final sizes = table.child('stsz');
    final sampleSize = sizes.u32(4);
    final sampleCount = sizes.u32(8);
    if (sampleCount == 0 || sampleCount > _maximumEntries) return null;
    final offsets = table
        .children()
        .where((b) => b.type == 'stco' || b.type == 'co64')
        .firstOrNull;
    if (offsets == null) return null;
    final chunkCount = offsets.u32(4);
    final chunks = table.child('stsc');
    final chunkEntries = chunks.u32(4);
    final times = table.child('stts');
    final timeEntries = times.u32(4);
    if (chunkCount > _maximumEntries ||
        chunkEntries == 0 ||
        timeEntries == 0 ||
        chunkEntries > chunkCount ||
        timeEntries > sampleCount ||
        chunks.u32(8) != 1) {
      return null;
    }
    var edit = 0;
    for (final edts in track.children().where((b) => b.type == 'edts')) {
      final list = edts.child('elst');
      // An empty edit introduces a separate movie timescale. Do not invent a
      // timeline for that case or for multiple edits.
      if (list.u32(4) != 1) return null;
      edit = list.u8(0) == 1 ? list.i64(16) : list.i32(12);
      if (edit < 0) return null;
    }
    var sample = 0, ticks = 0, timeEntry = 0, timeLeft = times.u32(8);
    var delta = times.u32(12), chunkEntry = 0;
    final spans = <Mp4BufferSpan>[];
    for (var chunk = 1; chunk <= chunkCount; chunk++) {
      while (chunkEntry + 1 < chunkEntries &&
          chunks.u32(8 + (chunkEntry + 1) * 12) <= chunk) {
        chunkEntry++;
      }
      final samples = chunks.u32(12 + chunkEntry * 12);
      if (samples == 0 || sample + samples > sampleCount) return null;
      var offset = offsets.type == 'co64'
          ? offsets.u64(8 + (chunk - 1) * 8)
          : offsets.u32(8 + (chunk - 1) * 4);
      var bytes = 0;
      for (var i = 0; i < samples; i++) {
        final start = ticks;
        bytes = sampleSize == 0 ? sizes.u32(12 + sample * 4) : sampleSize;
        if (bytes == 0) return null;
        sample++;
        if (timeLeft == 0) {
          if (++timeEntry >= timeEntries) return null;
          timeLeft = times.u32(8 + timeEntry * 8);
          delta = times.u32(12 + timeEntry * 8);
        }
        if (timeLeft == 0 || delta == 0) return null;
        ticks += delta;
        timeLeft--;
        // A native seek may begin in the middle of a very large chunk.
        // Only the current sample and its successors need to be delivered.
        spans.add(
          Mp4BufferSpan(
            offset,
            bytes,
            _time(start - edit, scale),
            _time(ticks - edit, scale),
          ),
        );
        offset += bytes;
      }
    }
    return sample == sampleCount ? Mp4BufferIndex(spans) : null;
  }

  Duration buffered(Duration position, bool Function(int, int) contains) {
    var low = 0, high = spans.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (spans[middle].end <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    var end = position;
    for (var i = low; i < spans.length; i++) {
      final span = spans[i];
      if (span.start > end + const Duration(milliseconds: 1) ||
          !contains(span.offset, span.length)) {
        break;
      }
      end = span.end;
    }
    return end;
  }
}

final class _Box {
  _Box(this.data, this.start, this.end, {this.type = ''});
  final ByteData data;
  final int start, end;
  final String type;
  int _at(int offset, int width) {
    if (offset < 0 || start + offset + width > end) {
      throw const FormatException('Truncated MP4 index');
    }
    return start + offset;
  }

  int u8(int p) => data.getUint8(_at(p, 1));
  int u16(int p) => data.getUint16(_at(p, 2));
  int u32(int p) => data.getUint32(_at(p, 4));
  int i32(int p) => data.getInt32(_at(p, 4));
  int i64(int p) => data.getInt64(_at(p, 8));
  int u64(int p) {
    final value = data.getUint64(_at(p, 8));
    if (value < 0 || value > 0x1fffffffffffff) {
      throw const FormatException('MP4 offset exceeds exact integer range');
    }
    return value;
  }

  Iterable<_Box> children() sync* {
    var p = start;
    while (p + 8 <= end) {
      var length = data.getUint32(p);
      final type = String.fromCharCodes(
        List.generate(4, (i) => data.getUint8(p + 4 + i)),
      );
      var header = 8;
      if (length == 1) {
        if (p + 16 > end) return;
        length = data.getUint64(p + 8);
        header = 16;
      }
      if (length < header || p + length > end) return;
      yield _Box(data, p + header, p + length, type: type);
      p += length;
    }
  }

  _Box child(String type) => children().firstWhere(
    (box) => box.type == type,
    orElse: () => throw const FormatException('Missing MP4 table'),
  );
}

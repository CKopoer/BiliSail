import '../../../domain/request_cancellation.dart';

final class CdnSpeedSample {
  CdnSpeedSample(Iterable<Uri> urls, {required this.sessionEpoch})
    : urls = List.unmodifiable(urls);
  final List<Uri> urls;
  final int sessionEpoch;
}

final class CdnSpeedMeasurement {
  const CdnSpeedMeasurement({
    required this.bytes,
    required this.elapsed,
    required this.host,
  });
  final int bytes;
  final Duration elapsed;
  final String host;
  double get mebibytesPerSecond =>
      bytes *
      Duration.microsecondsPerSecond /
      (elapsed.inMicroseconds.clamp(1, 1 << 62) * 1024 * 1024);
}

abstract interface class CdnSpeedTestRepository {
  Future<CdnSpeedSample> loadSample({
    required RequestCancellation cancellation,
  });
  Future<CdnSpeedMeasurement> measure(
    Uri url, {
    required int sessionEpoch,
    required RequestCancellation cancellation,
  });
}

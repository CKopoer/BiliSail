import 'dart:convert';

import '../models.dart';
import '../transport.dart';

/// Read-only BilibiliSponsorBlock API, isolated from Bilibili credentials.
final class SponsorBlockClient {
  SponsorBlockClient(this.transport);
  final ApiTransport transport;

  Future<List<ApiSponsorSegment>> segments(
    String bvid,
    String cid, {
    required List<String> categories,
    ApiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'sponsor.segments');
    }
    if (categories.isEmpty) return const [];
    final response = await transport.get(
      Uri.https('bsbsb.top', '/api/skipSegments', {
        'videoID': bvid,
        'cid': cid,
        'categories': jsonEncode(categories.take(16).toList()),
      }),
      headers: const {'origin': 'bili-lite', 'x-ext-version': '0.1.0'},
      timeout: const Duration(seconds: 8),
      cancellation: cancellation,
    );
    if (cancellation?.isCancelled ?? false) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'sponsor.segments');
    }
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw ApiFailure(
        ApiFailureCategory.http,
        'sponsor.segments',
        httpStatus: response.statusCode,
      );
    }
    if (response.body.length > 512 * 1024) {
      throw const ApiFailure(ApiFailureCategory.protocol, 'sponsor.segments');
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! List || decoded.length > 512) {
        throw const FormatException('segment capacity');
      }
      final result = <ApiSponsorSegment>[];
      final ids = <String>{};
      for (final row in decoded) {
        if (row is! Map<String, Object?>) continue;
        final range = row['segment'];
        final id = row['UUID'];
        final category = row['category'];
        final duration = row['videoDuration'];
        if (row['cid']?.toString() != cid ||
            row['actionType'] != 'skip' ||
            id is! String ||
            id.isEmpty ||
            id.length > 128 ||
            category is! String ||
            !categories.contains(category) ||
            duration is! num ||
            !duration.isFinite ||
            duration < 0 ||
            duration > 7 * 24 * 3600 ||
            range is! List ||
            range.length != 2) {
          continue;
        }
        final start = range[0];
        final end = range[1];
        if (start is! num ||
            end is! num ||
            !start.isFinite ||
            !end.isFinite ||
            start < 0 ||
            end <= start ||
            end > 7 * 24 * 3600 ||
            !ids.add(id)) {
          continue;
        }
        result.add(
          ApiSponsorSegment(
            id: id,
            category: category,
            start: Duration(microseconds: (start * 1000000).round()),
            end: Duration(microseconds: (end * 1000000).round()),
            videoDuration: Duration(microseconds: (duration * 1000000).round()),
          ),
        );
      }
      result.sort((a, b) => a.start.compareTo(b.start));
      return List.unmodifiable(result);
    } on FormatException {
      throw const ApiFailure(ApiFailureCategory.protocol, 'sponsor.segments');
    }
  }
}

final class ApiSponsorSegment {
  const ApiSponsorSegment({
    required this.id,
    required this.category,
    required this.start,
    required this.end,
    required this.videoDuration,
  });
  final String id;
  final String category;
  final Duration start;
  final Duration end;
  final Duration videoDuration;
}

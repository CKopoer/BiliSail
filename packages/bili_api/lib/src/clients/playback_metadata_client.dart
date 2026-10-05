import '../api_client.dart';
import '../models.dart';

final class ApiVideoChapter {
  const ApiVideoChapter(this.start, this.end, this.title, this.image);
  final Duration start, end;
  final String title;
  final Uri? image;
}

final class ApiPlaybackMetadata {
  const ApiPlaybackMetadata({
    required this.subtitles,
    required this.chapters,
    this.subtitleFailure,
    this.chapterFailure,
  });
  final List<ApiSubtitleTrack> subtitles;
  final List<ApiVideoChapter> chapters;
  final ApiFailure? subtitleFailure, chapterFailure;
}

final class ApiVideoStoryboard {
  ApiVideoStoryboard({
    required this.columns,
    required this.rows,
    required this.tileWidth,
    required this.tileHeight,
    required Iterable<Uri> images,
    required Iterable<Duration> times,
  }) : images = List.unmodifiable(images),
       times = List.unmodifiable(times);
  final int columns, rows, tileWidth, tileHeight;
  final List<Uri> images;
  final List<Duration> times;
}

/// Optional player metadata shares Web identity, deadlines and bounded retries.
final class PlaybackMetadataClient {
  const PlaybackMetadataClient(this.api);
  final BiliApiClient api;

  Future<ApiPlaybackMetadata> load(
    String aid,
    String cid, {
    ApiRequestContext? context,
  }) async {
    _id(aid);
    _id(cid);
    final data = await api.requestWbiJson(
      '/x/player/wbi/v2',
      {'aid': aid, 'cid': cid},
      'player_metadata',
      context: context,
    );
    List<ApiSubtitleTrack> subtitles = const [];
    List<ApiVideoChapter> chapters = const [];
    ApiFailure? subtitleFailure, chapterFailure;
    // A malformed optional component cannot discard the other component.
    try {
      subtitles = _subtitles(data['subtitle']);
    } on ApiFailure catch (failure) {
      subtitleFailure = failure;
    }
    try {
      chapters = _chapters(data['view_points']);
    } on ApiFailure catch (failure) {
      chapterFailure = failure;
    }
    return ApiPlaybackMetadata(
      subtitles: subtitles,
      chapters: chapters,
      subtitleFailure: subtitleFailure,
      chapterFailure: chapterFailure,
    );
  }

  Future<ApiVideoStoryboard?> storyboard(
    String bvid,
    String cid, {
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid)) {
      throw ArgumentError('Invalid video ID');
    }
    _id(cid);
    const endpoint = 'video_storyboard';
    final data = await api.requestJson(
      Uri.https('api.bilibili.com', '/x/player/videoshot', {
        'bvid': bvid,
        'cid': cid,
        'index': '1',
      }),
      endpoint,
      context: context,
    );
    final images = _list(data['image'], 200, endpoint);
    final indices = _list(data['index'], 20001, endpoint);
    if (images.isEmpty || indices.isEmpty) return null;
    final columns = _integer(data['img_x_len'], endpoint);
    final rows = _integer(data['img_y_len'], endpoint);
    final width = _integer(data['img_x_size'], endpoint);
    final height = _integer(data['img_y_size'], endpoint);
    if (columns < 1 ||
        rows < 1 ||
        columns > 20 ||
        rows > 20 ||
        width < 1 ||
        height < 1 ||
        width > 4096 ||
        height > 4096) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    final urls = images.map((value) => _image(value, endpoint)).toList();
    final seconds = indices.map((value) => _integer(value, endpoint)).toList();
    // The Web response can prefix frame-zero's timestamp with a zero sentinel.
    if (seconds.length > 1 && seconds[0] == 0 && seconds[1] == 0) {
      seconds.removeAt(0);
    }
    if (seconds.length > 20000 ||
        seconds.length > columns * rows * urls.length) {
      throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
    }
    for (var i = 0; i < seconds.length; i++) {
      if (seconds[i] < 0 ||
          seconds[i] > 7 * 24 * 60 * 60 ||
          (i > 0 && seconds[i] <= seconds[i - 1])) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
    }
    return ApiVideoStoryboard(
      columns: columns,
      rows: rows,
      tileWidth: width,
      tileHeight: height,
      images: urls,
      times: seconds.map((s) => Duration(seconds: s)),
    );
  }

  static List<ApiVideoChapter> _chapters(Object? value) {
    if (value == null) return const [];
    const endpoint = 'video_chapters';
    return List.unmodifiable(
      _list(value, 200, endpoint).map((value) {
        final row = _map(value, endpoint);
        final start = _integer(row['from'], endpoint);
        final end = _integer(row['to'], endpoint);
        final title = row['content'];
        if (start < 0 ||
            end <= start ||
            end > 7 * 24 * 60 * 60 ||
            title is! String ||
            title.trim().isEmpty ||
            title.length > 1000) {
          throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
        }
        return ApiVideoChapter(
          Duration(seconds: start),
          Duration(seconds: end),
          title.trim(),
          _optionalImage(row['imgUrl']),
        );
      }),
    );
  }

  static List<ApiSubtitleTrack> _subtitles(Object? value) {
    if (value == null) return const [];
    const endpoint = 'subtitle_index';
    final data = _map(value, endpoint);
    if (data['subtitles'] == null) return const [];
    return List.unmodifiable(
      _list(data['subtitles'], 100, endpoint).map((value) {
        final row = _map(value, endpoint);
        return ApiSubtitleTrack(
          languageCode: row['lan'] is String ? row['lan'] as String : '',
          label: row['lan_doc'] is String ? row['lan_doc'] as String : '',
          url: _image(row['subtitle_url'], endpoint),
        );
      }),
    );
  }

  static Uri? _optionalImage(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 && uri.port != 80 ||
        !(uri.host == 'hdslb.com' ||
            uri.host.endsWith('.hdslb.com') ||
            uri.host == 'bilibili.com' ||
            uri.host.endsWith('.bilibili.com')) ||
        !const ['http', 'https'].contains(uri.scheme)) {
      return null;
    }
    return uri.replace(scheme: 'https');
  }

  static Uri _image(Object? value, String endpoint) =>
      _optionalImage(value) ??
      (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static int _integer(Object? value, String endpoint) => switch (value) {
    int number => number,
    String text =>
      int.tryParse(text) ??
          (throw ApiFailure(ApiFailureCategory.protocol, endpoint)),
    _ => throw ApiFailure(ApiFailureCategory.protocol, endpoint),
  };
  static Map<String, Object?> _map(Object? value, String endpoint) =>
      value is Map<String, Object?>
          ? value
          : (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static List<Object?> _list(Object? value, int capacity, String endpoint) =>
      value is List<Object?> && value.length <= capacity
          ? value
          : (throw ApiFailure(ApiFailureCategory.protocol, endpoint));
  static void _id(String value) {
    if (!RegExp(r'^[1-9]\d*$').hasMatch(value)) {
      throw ArgumentError('Invalid ID');
    }
  }
}

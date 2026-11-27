import 'download_models.dart';

enum OfflineGroupKind { season, collection, video }

/// An account's completed media, indexed once per library change. Versions
/// are actual tasks; an episode or part occupies a single place in the queue.
final class OfflineLibrary {
  OfflineLibrary(
    Iterable<DownloadTask> tasks,
    Map<String, DownloadWork> works,
  ) {
    final grouped = <String, Map<String, List<DownloadTask>>>{};
    for (final task in tasks) {
      final item = task.item;
      final work = works[item.workKey] ?? item.work;
      final groupId = item.episodeId == null && work?.collectionId != null
          ? 'collection:${work?.collectionId}'
          : item.workKey;
      final content = item.episodeId == null
          ? item.key
          : 'episode:${item.episodeId}';
      final versions = (grouped[groupId] ??= {})[content] ??= [];
      versions.add(task);
      if (work != null) _metadata[item.workKey] = work;
    }
    for (final group in grouped.entries) {
      final entries = [
        for (final versions in group.value.values) OfflineEntry(versions),
      ];
      entries.sort((a, b) {
        final left = a.task.item, right = b.task.item;
        final order = (workFor(left)?.collectionPosition ?? 0).compareTo(
          workFor(right)?.collectionPosition ?? 0,
        );
        if (order != 0) return order;
        final byWork = left.workKey.compareTo(right.workKey);
        if (byWork != 0) return byWork;
        final page = left.part.page.compareTo(right.part.page);
        return page != 0 ? page : left.key.compareTo(right.key);
      });
      if (entries.first.task.item.episodeId != null &&
          entries.any((entry) => entry.section != null)) {
        final sections = <String?, List<OfflineEntry>>{};
        for (final entry in entries) {
          (sections[entry.section] ??= []).add(entry);
        }
        final unknown = sections.remove(null);
        entries
          ..clear()
          ..addAll(sections.values.expand((items) => items));
        if (unknown != null) entries.addAll(unknown);
      }
      final first = entries.first.task.item;
      final kind = first.episodeId != null
          ? OfflineGroupKind.season
          : group.key.startsWith('collection:')
          ? OfflineGroupKind.collection
          : OfflineGroupKind.video;
      final work = workFor(first);
      final result = OfflineGroup(
        id: group.key,
        kind: kind,
        entries: entries,
        title: kind == OfflineGroupKind.collection
            ? work?.collectionTitle ?? first.video.title
            : first.video.title,
        multipart:
            (work?.partCount ?? 0) > 1 ||
            entries.length > 1 ||
            first.part.page > 1,
      );
      _groups.add(result);
      for (final entry in entries) {
        for (final task in entry.versions) {
          _locations[task.id] = (group: result, entry: entry);
        }
      }
    }
    _groups.sort((a, b) {
      final time = b.latest.compareTo(a.latest);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  }
  final _groups = <OfflineGroup>[];
  final _locations = <String, ({OfflineGroup group, OfflineEntry entry})>{};
  final _metadata = <String, DownloadWork>{};
  late final groups = List<OfflineGroup>.unmodifiable(_groups);
  ({OfflineGroup group, OfflineEntry entry})? find(String taskId) =>
      _locations[taskId];
  DownloadWork? workFor(DownloadItem item) =>
      _metadata[item.workKey] ?? item.work;
}

final class OfflineGroup {
  OfflineGroup({
    required this.id,
    required this.kind,
    required this.title,
    required List<OfflineEntry> entries,
    required this.multipart,
  }) : entries = List.unmodifiable(entries);
  final String id, title;
  final OfflineGroupKind kind;
  final bool multipart;
  final List<OfflineEntry> entries;
  late final Set<String> multipartVideos = _multipartVideos();
  Set<String> _multipartVideos() {
    final seen = <String>{}, multi = <String>{};
    for (final entry in entries) {
      final id = entry.task.item.video.id.value;
      if (!seen.add(id)) multi.add(id);
    }
    return Set.unmodifiable(multi);
  }

  late final latest = entries
      .map((entry) => entry.task.createdAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  bool get showCurrent => kind != OfflineGroupKind.video || multipart;
  String get label => switch (kind) {
    OfflineGroupKind.season => '本季剧集',
    OfflineGroupKind.collection => '视频合集',
    OfflineGroupKind.video => '视频分 P',
  };
  String get count => switch (kind) {
    OfflineGroupKind.season => '${entries.length} 集',
    OfflineGroupKind.collection =>
      '${entries.map((e) => e.task.item.video.id).toSet().length} 个投稿 · ${entries.length} P',
    OfflineGroupKind.video => multipart ? '${entries.length} P' : '1 个视频',
  };

  OfflineEntry? adjacent(
    OfflineEntry current,
    int direction, {
    bool loop = false,
  }) {
    final sequence = kind == OfflineGroupKind.season
        ? entries.where((e) => e.section == current.section).toList()
        : entries;
    final index = sequence.indexOf(current);
    if (index < 0) return null;
    final next = index + direction;
    if (loop) return sequence[next % sequence.length];
    return next >= 0 && next < sequence.length ? sequence[next] : null;
  }
}

final class OfflineEntry {
  OfflineEntry(List<DownloadTask> variants)
    : versions = List.unmodifiable(
        variants..sort((a, b) {
          final time = b.createdAt.compareTo(a.createdAt);
          return time != 0 ? time : a.id.compareTo(b.id);
        }),
      );
  final List<DownloadTask> versions;
  DownloadTask get task => versions.first;
  late final String? section = versions
      .map((v) => v.item.section)
      .nonNulls
      .firstOrNull;
  DownloadTask preferred(DownloadTask current) {
    var best = task, score = -1;
    for (final candidate in versions) {
      if (candidate.id == current.id) return candidate;
      final selection = candidate.selection, previous = current.selection;
      final match =
          (selection.quality == previous.quality ? 8 : 0) +
          (selection.codec == previous.codec ? 4 : 0) +
          (selection.output == previous.output ? 2 : 0) +
          (selection.audioQuality == previous.audioQuality ? 1 : 0);
      if (match > score) {
        best = candidate;
        score = match;
      }
    }
    return best;
  }
}

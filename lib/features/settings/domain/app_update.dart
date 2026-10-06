import '../../../domain/request_cancellation.dart';

final class AppUpdateLinks {
  static final repository = Uri.https('github.com', '/CKopoer/BiliSail');
  static final releases = Uri.https('github.com', '/CKopoer/BiliSail/releases');
}

/// Semantic version precedence, then the numeric Flutter build revision.
final class AppVersion implements Comparable<AppVersion> {
  AppVersion._(
    this.label,
    this.major,
    this.minor,
    this.patch,
    this.build,
    List<String> prerelease,
  ) : prerelease = List.unmodifiable(prerelease);

  final String label;
  final int major, minor, patch, build;
  final List<String> prerelease;

  static AppVersion? tryParse(String value) {
    if (value.length > 128) return null;
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
    ).firstMatch(value);
    if (match == null) return null;
    final core = [
      for (var i = 1; i <= 3; i++) int.tryParse(match.group(i) ?? ''),
    ];
    if (core.any((part) => part == null)) return null;
    final prerelease = match.group(4)?.split('.') ?? <String>[];
    for (final part in prerelease) {
      if (RegExp(r'^\d+$').hasMatch(part) &&
          (part.length > 1 && part.startsWith('0') ||
              int.tryParse(part) == null)) {
        return null;
      }
    }
    final metadata = match.group(5);
    final numericBuild =
        metadata != null && RegExp(r'^\d+$').hasMatch(metadata);
    final build = numericBuild ? int.tryParse(metadata) : 0;
    if (build == null) return null;
    return AppVersion._(
      value.startsWith('v') ? value.substring(1) : value,
      core[0] ?? 0,
      core[1] ?? 0,
      core[2] ?? 0,
      build,
      prerelease,
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final result = a.compareTo(b);
      if (result != 0) return result;
    }
    if (prerelease.isEmpty != other.prerelease.isEmpty) {
      return prerelease.isEmpty ? 1 : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i], b = other.prerelease[i];
      final aNumber = int.tryParse(a), bNumber = int.tryParse(b);
      final result = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : aNumber != null
          ? -1
          : bNumber != null
          ? 1
          : a.compareTo(b);
      if (result != 0) return result;
    }
    final length = prerelease.length.compareTo(other.prerelease.length);
    return length != 0 ? length : build.compareTo(other.build);
  }
}

final class AppRelease {
  const AppRelease({
    required this.version,
    required this.url,
    this.notes = '',
    this.prerelease = false,
  });
  final AppVersion version;
  final Uri url;
  final String notes;
  final bool prerelease;
}

abstract interface class AppUpdateRepository {
  Future<AppVersion> installedVersion();
  Future<AppRelease?> latestRelease(RequestCancellation cancellation);
}

abstract interface class UpdateCheckStore {
  /// Persist the local calendar day before the automatic network attempt.
  Future<bool> claimStartupDay(String day);
}

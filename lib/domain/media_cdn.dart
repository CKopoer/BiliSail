/// Preferences order server-provided URLs; they never rewrite signed hosts.
enum MediaCdnPreference { automatic, regular, tencent, huawei, alibaba, baidu }

/// A failed automatic primary should try a returned regular CDN rather than
/// another PCDN before exhausting the bounded recovery attempts. Explicit
/// preferences keep their order. The original signed URI is returned intact.
Uri? backupMediaCdnUrl(List<Uri> urls, MediaCdnPreference preference) {
  if (urls.isEmpty) return null;
  final alternatives = urls.where((url) => url != urls.first);
  return orderMediaCdnUrls(
    alternatives,
    preference == MediaCdnPreference.automatic
        ? MediaCdnPreference.regular
        : preference,
  ).firstOrNull;
}

List<Uri> orderMediaCdnUrls(Iterable<Uri> urls, MediaCdnPreference preference) {
  final unique = urls.toSet().toList();
  if (preference == MediaCdnPreference.automatic) {
    return List.unmodifiable(unique);
  }
  bool preferred(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.endsWith('.bilivideo.com')) return false;
    return switch (preference) {
      MediaCdnPreference.automatic => true,
      MediaCdnPreference.regular => host.startsWith('upos-'),
      MediaCdnPreference.tencent =>
        host.startsWith('upos-') &&
            RegExp(r'(?:mirror|estg)cos').hasMatch(host),
      MediaCdnPreference.huawei =>
        host.startsWith('upos-') && host.contains('mirrorhw'),
      MediaCdnPreference.alibaba =>
        host.startsWith('upos-') && host.contains('mirrorali'),
      MediaCdnPreference.baidu =>
        host.startsWith('upos-') && host.contains('mirrorbd'),
    };
  }

  return List.unmodifiable([
    ...unique.where(preferred),
    ...unique.where((url) => !preferred(url)),
  ]);
}

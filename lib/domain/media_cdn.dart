/// Preferences order server-provided URLs; they never rewrite signed hosts.
enum MediaCdnPreference { automatic, regular, tencent, huawei, alibaba, baidu }

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

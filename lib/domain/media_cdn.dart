enum MediaCdnPreference {
  automatic('自动（默认）'),
  regular('优先常规 CDN'),
  tencent('优先腾讯云'),
  huawei('优先华为云'),
  alibaba('优先阿里云'),
  baidu('优先百度云'),
  ali('ali（阿里云）', 'upos-sz-mirrorali.bilivideo.com'),
  alib('alib（阿里云）', 'upos-sz-mirroralib.bilivideo.com'),
  alio1('alio1（阿里云）', 'upos-sz-mirroralio1.bilivideo.com'),
  cos('cos（腾讯云）', 'upos-sz-mirrorcos.bilivideo.com'),
  cosb('cosb（腾讯云 VOD）', 'upos-sz-mirrorcosb.bilivideo.com'),
  coso1('coso1（腾讯云）', 'upos-sz-mirrorcoso1.bilivideo.com'),
  hw('hw（华为云）', 'upos-sz-mirrorhw.bilivideo.com'),
  hwb('hwb（华为云）', 'upos-sz-mirrorhwb.bilivideo.com'),
  hwo1('hwo1（华为云）', 'upos-sz-mirrorhwo1.bilivideo.com'),
  hw08c('08c（华为云）', 'upos-sz-mirror08c.bilivideo.com'),
  hw08h('08h（华为云）', 'upos-sz-mirror08h.bilivideo.com'),
  hw08ct('08ct（华为云）', 'upos-sz-mirror08ct.bilivideo.com'),
  tfHw('tf_hw（华为云）', 'upos-tf-all-hw.bilivideo.com'),
  tfTx('tf_tx（腾讯云）', 'upos-tf-all-tx.bilivideo.com'),
  akamai('akamai（海外）', 'upos-hz-mirrorakam.akamaized.net'),
  aliov('aliov（阿里云海外）', 'upos-sz-mirroraliov.bilivideo.com'),
  cosov('cosov（腾讯云海外）', 'upos-sz-mirrorcosov.bilivideo.com'),
  hwov('hwov（华为云海外）', 'upos-sz-mirrorhwov.bilivideo.com'),
  hkBcache('hk_bcache（Bilibili 海外）', 'cn-hk-eq-bcache-01.bilivideo.com');

  const MediaCdnPreference(this.label, [this.host]);
  final String label;
  final String? host;
}

/// A failed automatic primary should try a returned regular CDN rather than
/// another PCDN before exhausting the bounded recovery attempts. Explicit
/// preferences keep their order. The original signed URI is returned intact.
Uri? backupMediaCdnUrl(List<Uri> urls, MediaCdnPreference preference) {
  if (urls.isEmpty) return null;
  final alternatives = urls.where((url) => url != urls.first);
  return _orderProvidedUrls(
    alternatives,
    preference == MediaCdnPreference.automatic
        ? MediaCdnPreference.regular
        : preference,
  ).firstOrNull;
}

List<Uri> orderMediaCdnUrls(Iterable<Uri> urls, MediaCdnPreference preference) {
  final provided = _orderProvidedUrls(urls, preference);
  final host = preference.host;
  if (host == null) return provided;
  final existing = provided.where((url) => url.host == host).firstOrNull;
  // Only the shared UPOS object path can be used on a different mirror.
  // PCDN resource paths, arbitrary hosts, credentials and custom ports stay intact.
  final source = provided.where(_canUseMirror).firstOrNull;
  final target = existing ?? source?.replace(host: host);
  return List.unmodifiable({?target, ...provided});
}

Uri? mediaCdnProbeUrl(Iterable<Uri> urls, MediaCdnPreference preference) {
  final ordered = orderMediaCdnUrls(urls, preference);
  final host = preference.host;
  return host == null
      ? ordered.firstOrNull
      : ordered.where((url) => url.host == host).firstOrNull;
}

bool _canUseMirror(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') &&
    uri.userInfo.isEmpty &&
    !uri.hasPort &&
    uri.path.startsWith('/upgcxcode/') &&
    ((uri.host.startsWith('upos-') && uri.host.endsWith('.bilivideo.com')) ||
        uri.host == MediaCdnPreference.akamai.host);

List<Uri> _orderProvidedUrls(
  Iterable<Uri> urls,
  MediaCdnPreference preference,
) {
  final unique = urls.toSet().toList();
  if (preference == MediaCdnPreference.automatic) {
    return List.unmodifiable(unique);
  }
  bool preferred(Uri uri) {
    final host = uri.host.toLowerCase();
    if (preference.host case final target?) return host == target;
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
      _ => false,
    };
  }

  return List.unmodifiable([
    ...unique.where(preferred),
    ...unique.where((url) => !preferred(url)),
  ]);
}

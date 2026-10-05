/// Size public static CDN images before transfer, since decode dimensions only
/// limit decoded memory and cannot keep a large original within the byte limit.
/// Keep signed URLs, animation and existing CDN transforms unchanged.
Uri publicImageThumbnail(Uri source, {required int width, int height = 1280}) {
  final host = source.host.toLowerCase();
  if (!['http', 'https'].contains(source.scheme) ||
      source.userInfo.isNotEmpty ||
      source.hasPort ||
      source.hasQuery ||
      source.hasFragment ||
      !(host == 'hdslb.com' || host.endsWith('.hdslb.com')) ||
      source.path.contains('@') ||
      !RegExp(
        r'\.(?:jpe?g|png|webp)$',
        caseSensitive: false,
      ).hasMatch(source.path)) {
    return source;
  }
  // 0e fits within both bounds without cropping. 1e instead fills the bounds
  // and can produce a larger image than the requested width or height.
  return source.replace(
    scheme: 'https',
    path:
        '${source.path}@${width.clamp(1, 1280)}w_${height.clamp(1, 1280)}h_0e.webp',
  );
}

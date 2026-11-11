import 'package:flutter/material.dart';

import '../../core/presentation/public_image_variant.dart';
import 'app_network_image.dart';
import 'user_decoration_image.dart';

/// Public CDN avatars never receive account cookies. Leave loading avatars blank
/// and use a fallback only when their source is missing or unavailable.
class NetworkAvatar extends StatelessWidget {
  const NetworkAvatar({
    super.key,
    this.url,
    this.pendantUrl,
    this.name = '',
    this.radius = 18,
  });
  final Uri? url, pendantUrl;
  final String name;
  final double radius;

  static const _edges = [48, 64, 96, 128, 160, 240, 320, 480, 640, 960, 1280];

  @override
  Widget build(BuildContext context) {
    final pendant = pendantUrl;
    final diameter = radius * 2;
    // Reserve the same six logical pixels around decorated avatars as PiliPlus;
    // the artwork's transparent canvas extends beyond this fixed layout slot.
    final avatarSize = pendant == null
        ? diameter
        : (diameter - 6).clamp(1.0, diameter);
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: name.trim().isEmpty
            ? Icon(Icons.person_outline, size: radius * 1.15)
            : Text(
                name.characters.first,
                style: TextStyle(fontSize: radius * .8),
              ),
      ),
    );
    final source = url;
    // Share nearby sizes without requesting another URL for every pixel.
    final physicalEdge = avatarSize * MediaQuery.devicePixelRatioOf(context);
    final edge = _edges.firstWhere(
      (candidate) => candidate >= physicalEdge,
      orElse: () => _edges.last,
    );
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: avatarSize,
        child:
            source == null || !const ['https', 'http'].contains(source.scheme)
            ? fallback
            : AppNetworkImage(
                url: publicImageThumbnail(
                  source.replace(scheme: 'https'),
                  width: edge,
                  height: edge,
                ).toString(),
                cacheWidth: edge,
                cacheHeight: edge,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (_, child, frame, _) =>
                    frame != null ? child : const SizedBox.expand(),
              ),
      ),
    );
    final pendantSize = avatarSize * 1.75;
    return Semantics(
      label: name.isEmpty ? '用户头像' : '$name 的头像',
      image: true,
      child: pendant == null
          ? avatar
          : SizedBox.square(
              dimension: diameter,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  avatar,
                  Positioned(
                    left: (diameter - pendantSize) / 2,
                    top: (diameter - pendantSize) / 2,
                    width: pendantSize,
                    height: pendantSize,
                    child: IgnorePointer(
                      child: UserDecorationImage(
                        url: pendant,
                        width: pendantSize,
                        height: pendantSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

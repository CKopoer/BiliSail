import 'package:flutter/material.dart';

import 'app_network_image.dart';

/// Public CDN avatars never receive account cookies. Keep a stable fallback
/// while loading or when an upstream image has disappeared.
class NetworkAvatar extends StatelessWidget {
  const NetworkAvatar({super.key, this.url, this.name = '', this.radius = 18});
  final Uri? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
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
    return Semantics(
      label: name.isEmpty ? '用户头像' : '$name 的头像',
      image: true,
      child: ClipOval(
        child: SizedBox.square(
          dimension: radius * 2,
          child:
              source == null || !const ['https', 'http'].contains(source.scheme)
              ? fallback
              : AppNetworkImage(
                  url: source.replace(scheme: 'https').toString(),
                  cacheWidth: 96,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                  frameBuilder: (_, child, frame, _) =>
                      frame != null ? child : fallback,
                ),
        ),
      ),
    );
  }
}

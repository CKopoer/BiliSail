import 'package:flutter/widgets.dart';

import 'app_network_image.dart';

/// Decoration artwork includes transparent space used to position its contents.
/// Keep the original canvas and decode by one physical edge to retain its ratio.
class UserDecorationImage extends StatelessWidget {
  const UserDecorationImage({
    super.key,
    required this.url,
    required this.height,
    this.width,
  });

  final Uri url;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) => AppNetworkImage(
    url: url.toString(),
    width: width,
    height: height,
    cacheHeight: (height * MediaQuery.devicePixelRatioOf(context)).ceil(),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => SizedBox(width: width, height: height),
  );
}

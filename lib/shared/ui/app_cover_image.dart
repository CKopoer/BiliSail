import 'package:flutter/widgets.dart';

import '../../core/presentation/public_image_variant.dart';
import 'app_network_image.dart';

/// Request a CDN thumbnail at the cover's physical display width, then use the
/// shared visibility, transfer and decode caches just like other public images.
final class AppCoverImage extends StatelessWidget {
  const AppCoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorBuilder,
    this.frameBuilder,
    this.excludeFromSemantics = false,
  });

  final String url;
  final double? width, height;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageFrameBuilder? frameBuilder;
  final bool excludeFromSemantics;

  // Buckets let nearby card sizes share a URL rather than downloading a new
  // variant at every pixel during window resizing. Keep the decode edge bounded.
  static const _widths = [96, 160, 240, 320, 480, 640, 960, 1280];

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final physicalWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)
            : 640.0;
        final thumbnailWidth = _widths.firstWhere(
          (candidate) => candidate >= physicalWidth,
          orElse: () => _widths.last,
        );
        final source = Uri.tryParse(url);
        return AppNetworkImage(
          url: source == null
              ? url
              : publicImageThumbnail(source, width: thumbnailWidth).toString(),
          cacheWidth: thumbnailWidth,
          fit: fit,
          errorBuilder: errorBuilder,
          frameBuilder: frameBuilder,
          excludeFromSemantics: excludeFromSemantics,
        );
      },
    ),
  );
}

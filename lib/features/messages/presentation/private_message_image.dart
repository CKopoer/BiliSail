import 'package:flutter/material.dart';

import '../../../shared/ui/image_viewer.dart';

/// Private media uses credential-free memory decoding and never the disk cache.
class PrivateMessageImage extends StatefulWidget {
  const PrivateMessageImage({
    super.key,
    required this.url,
    this.aspectRatio,
    this.width,
    this.height,
    this.preview = true,
    this.compact = false,
    this.fallbackText,
    this.label = '查看消息图片',
  });
  final Uri url;
  final double? aspectRatio, width, height;
  final bool preview, compact;
  final String? fallbackText;
  final String label;

  @override
  State<PrivateMessageImage> createState() => _PrivateMessageImageState();
}

class _PrivateMessageImageState extends State<PrivateMessageImage> {
  late NetworkImage _image = NetworkImage(widget.url.toString());
  late ImageProvider<Object> _previewImage = ResizeImage(
    _image,
    width: widget.compact ? 96 : 880,
    height: widget.compact ? 96 : 1280,
    policy: ResizeImagePolicy.fit,
  );

  void _evict() {
    _previewImage.evict();
    _image.evict();
  }

  @override
  void didUpdateWidget(PrivateMessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.compact != widget.compact) {
      _evict();
      _image = NetworkImage(widget.url.toString());
      _previewImage = ResizeImage(
        _image,
        width: widget.compact ? 96 : 880,
        height: widget.compact ? 96 : 1280,
        policy: ResizeImagePolicy.fit,
      );
    }
  }

  @override
  void dispose() {
    _evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.aspectRatio;
    final image = Image(
      image: _previewImage,
      width: widget.compact ? 26 : widget.width ?? 280,
      height: widget.compact
          ? 26
          : widget.height ??
                (ratio == null
                    ? 180
                    : (280 / ratio.clamp(.4, 3)).clamp(80, 320)),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => widget.compact
          ? Text(
              widget.fallbackText ?? widget.label,
              style: Theme.of(context).textTheme.bodySmall,
            )
          : const Padding(padding: EdgeInsets.all(12), child: Text('图片暂时无法加载')),
    );
    if (!widget.preview) return image;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.label,
      button: true,
      child: InkWell(
        onTap: () => showImageViewer(context, [widget.url], 0),
        child: image,
      ),
    );
  }
}

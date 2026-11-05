import 'package:flutter/material.dart';

import '../../../shared/ui/image_viewer.dart';
import '../domain/message_repository.dart';

/// Renders normalized message content without interpreting protocol payloads.
class MessageContentView extends StatelessWidget {
  const MessageContentView({
    super.key,
    required this.message,
    this.onOpenTarget,
  });

  final PrivateMessage message;
  final ValueChanged<Uri>? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageOnly =
        message.kind == MessageContentKind.image ||
        message.type == 2 ||
        message.type == 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.title.isNotEmpty) ...[
          SelectableText(message.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
        ],
        if ((!imageOnly || message.imageUrl == null) && message.text.isNotEmpty)
          SelectableText(message.text),
        if (message.subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              message.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (message.kind == MessageContentKind.voice)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic_none_rounded, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    message.durationSeconds == null
                        ? '语音消息'
                        : '语音 ${message.durationSeconds} 秒',
                  ),
                ),
              ],
            ),
          ),
        if (message.imageUrl case final image?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: PrivateMessageImage(
              url: image,
              aspectRatio: message.imageAspectRatio,
              label: imageOnly ? '查看私信图片' : '查看消息图片',
            ),
          ),
        for (final detail in message.details)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 3,
              children: [
                Text(detail.label, style: theme.textTheme.bodySmall),
                SelectableText(detail.value),
              ],
            ),
          ),
        for (final card in message.cards)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _ContentCard(card: card, onOpenTarget: onOpenTarget),
          ),
        for (final link in message.links)
          TextButton(
            onPressed: onOpenTarget == null
                ? null
                : () => onOpenTarget?.call(link.url),
            child: Text(link.label.isEmpty ? '查看详情' : link.label),
          ),
        if (message.targetUrl case final target?
            when !imageOnly && message.links.isEmpty)
          TextButton(
            onPressed: onOpenTarget == null
                ? null
                : () => onOpenTarget?.call(target),
            child: const Text('查看分享内容'),
          ),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.card, this.onOpenTarget});
  final MessageCard card;
  final ValueChanged<Uri>? onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final target = card.targetUrl;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: target == null || onOpenTarget == null
            ? null
            : () => onOpenTarget?.call(target),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (card.imageUrl case final image?)
                PrivateMessageImage(
                  url: image,
                  aspectRatio: 16 / 9,
                  preview: false,
                ),
              if (card.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    card.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              if (card.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(card.description),
                ),
              if (target != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('查看内容'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Private media uses credential-free memory decoding and never the disk cache.
class PrivateMessageImage extends StatefulWidget {
  const PrivateMessageImage({
    super.key,
    required this.url,
    this.aspectRatio,
    this.preview = true,
    this.label = '查看消息图片',
  });
  final Uri url;
  final double? aspectRatio;
  final bool preview;
  final String label;

  @override
  State<PrivateMessageImage> createState() => _PrivateMessageImageState();
}

class _PrivateMessageImageState extends State<PrivateMessageImage> {
  late NetworkImage _image = NetworkImage(widget.url.toString());
  late ImageProvider<Object> _previewImage = ResizeImage(
    _image,
    width: 880,
    height: 1280,
    policy: ResizeImagePolicy.fit,
  );

  void _evict() {
    _previewImage.evict();
    _image.evict();
  }

  @override
  void didUpdateWidget(PrivateMessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _evict();
      _image = NetworkImage(widget.url.toString());
      _previewImage = ResizeImage(
        _image,
        width: 880,
        height: 1280,
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
      width: 280,
      height: ratio == null ? 180 : (280 / ratio.clamp(.4, 3)).clamp(80, 320),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          const Padding(padding: EdgeInsets.all(12), child: Text('图片暂时无法加载')),
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

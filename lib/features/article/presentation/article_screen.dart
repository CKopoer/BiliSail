import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/public_image_variant.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/article_address.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/image_viewer.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/state_view.dart';
import '../application/article_provider.dart';
import '../domain/article_document.dart';

final class ArticleScreen extends ConsumerWidget {
  const ArticleScreen({
    super.key,
    required this.address,
    required this.onOpenUser,
    required this.onOpenLink,
    required this.onOpenWeb,
  });

  final ArticleAddress address;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<Uri> onOpenLink, onOpenWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = articleProvider(address);
    final state = address.isValid ? ref.watch(provider) : null;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed:
                  PlaybackNavigation.maybeOf(context)?.onBack ??
                  () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text('专栏', style: Theme.of(context).textTheme.titleMedium),
            ),
            if (state != null)
              IconButton(
                tooltip: '在浏览器打开',
                onPressed: () =>
                    onOpenWeb(state.asData?.value.url ?? address.webUri),
                icon: const Icon(Icons.open_in_new_outlined),
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: state == null
              ? const StateView.empty(message: '专栏地址无效')
              : state.when(
                  skipLoadingOnReload: false,
                  skipLoadingOnRefresh: false,
                  data: (document) => _ArticleBody(
                    storageKey: PageStorageKey(address.location),
                    document: document,
                    onOpenUser: onOpenUser,
                    onOpenLink: onOpenLink,
                  ),
                  loading: () => const StateView.loading(message: '正在加载专栏…'),
                  error: (error, _) => StateView.error(
                    message: error is AppFailure
                        ? error.message
                        : '专栏加载失败，请稍后再试',
                    onAction: () => ref.invalidate(provider),
                  ),
                ),
        ),
      ],
    );
  }
}

final class _ArticleBody extends StatelessWidget {
  const _ArticleBody({
    required this.storageKey,
    required this.document,
    required this.onOpenUser,
    required this.onOpenLink,
  });

  final PageStorageKey<String> storageKey;
  final ArticleDocument document;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<Uri> onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = document.blocks;
    final images = <Uri>[];
    final imageIndexes = <int, int>{};
    for (var index = 0; index < blocks.length; index++) {
      if (blocks[index].image case final image?) {
        imageIndexes[index] = images.length;
        images.add(image);
      }
    }
    final date = document.publishedAt;
    final authorId = document.authorId;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: SelectionArea(
          child: CustomScrollView(
            key: storageKey,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                sliver: SliverList.builder(
                  itemCount: blocks.length + 1,
                  itemBuilder: (context, index) {
                    if (index > 0) {
                      final block = blocks[index - 1];
                      final photo = imageIndexes[index - 1];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: photo == null
                            ? _TextBlock(block: block, onOpenLink: onOpenLink)
                            : _ArticleImage(
                                block: block,
                                images: images,
                                index: photo,
                              ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (document.title.isNotEmpty)
                          Semantics(
                            header: true,
                            child: Text(
                              document.title,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        if (document.author.isNotEmpty || date != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                if (document.author.isNotEmpty)
                                  if (authorId != null)
                                    TextButton.icon(
                                      onPressed: () => onOpenUser(authorId),
                                      icon: NetworkAvatar(
                                        url: document.authorAvatar,
                                        name: document.author,
                                        radius: 14,
                                      ),
                                      label: Text(document.author),
                                    )
                                  else
                                    Text(
                                      document.author,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                if (date != null)
                                  Text(
                                    MaterialLocalizations.of(context)
                                        .formatCompactDate(date.toLocal()),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (document.accessMessage case final message?)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              message,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        if (document.title.isNotEmpty)
                          const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ArticleImage extends StatelessWidget {
  const _ArticleImage({
    required this.block,
    required this.images,
    required this.index,
  });

  final ArticleBlock block;
  final List<Uri> images;
  final int index;

  @override
  Widget build(BuildContext context) {
    final image = images[index];
    final preview = publicImageThumbnail(image, width: 1280);
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        label: '查看图片 ${index + 1}',
        child: InkWell(
          onTap: () => showImageViewer(context, images, index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 960),
            child: AspectRatio(
              aspectRatio: (block.aspectRatio ?? 1.6).clamp(0.25, 8),
              child: AppNetworkImage(
                url: preview.toString(),
                viewerOriginal: image,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _TextBlock extends StatefulWidget {
  const _TextBlock({required this.block, required this.onOpenLink});

  final ArticleBlock block;
  final ValueChanged<Uri> onOpenLink;

  @override
  State<_TextBlock> createState() => _TextBlockState();
}

final class _TextBlockState extends State<_TextBlock> {
  final _recognizers = <Uri, TapGestureRecognizer>{};

  @override
  void didUpdateWidget(_TextBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block) _disposeRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(height: 1.55);
    if (block.kind == ArticleBlockKind.divider) return const Divider();
    if (block.kind == ArticleBlockKind.code) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            block.text.map((run) => run.text).join(),
            style: style?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      );
    }
    final rich = Text.rich(
      TextSpan(
        children: [
          for (final run in block.text)
            TextSpan(
              text: run.text,
              style: TextStyle(
                fontWeight: run.bold ? FontWeight.bold : null,
                fontStyle: run.italic ? FontStyle.italic : null,
                color: run.link != null ? theme.colorScheme.primary : null,
                decoration: TextDecoration.combine([
                  if (run.strike) TextDecoration.lineThrough,
                  if (run.link != null) TextDecoration.underline,
                ]),
              ),
              recognizer: switch (run.link) {
                final target? => _recognizers.putIfAbsent(target, () {
                  return TapGestureRecognizer()
                    ..onTap = () => widget.onOpenLink(target);
                }),
                _ => null,
              },
            ),
        ],
      ),
      style: block.kind == ArticleBlockKind.heading
          ? theme.textTheme.titleLarge
          : style,
    );
    return switch (block.kind) {
      ArticleBlockKind.heading => Semantics(header: true, child: rich),
      ArticleBlockKind.quote => DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            start: BorderSide(
              color: theme.colorScheme.outlineVariant,
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: rich,
        ),
      ),
      _ => rich,
    };
  }
}

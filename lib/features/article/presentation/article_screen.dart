import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/public_image_variant.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/article_address.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/dynamic_post_menu.dart';
import '../../../shared/ui/image_viewer.dart';
import '../../../shared/ui/measured_list_view.dart';
import '../../../shared/ui/post_author_header.dart';
import '../../../shared/ui/post_card_surface.dart';
import '../../../shared/ui/state_view.dart';
import '../../dynamic/application/dynamic_management_controller.dart';
import '../application/article_provider.dart';
import '../domain/article_document.dart';
import 'article_page_frame.dart';
import 'article_reader_layout.dart';

final class ArticleScreen extends ConsumerWidget {
  const ArticleScreen({
    super.key,
    required this.address,
    required this.onOpenUser,
    required this.onOpenLink,
    required this.onOpenWeb,
    required this.onLogin,
    this.onBack,
    this.focusComments = false,
  });

  final ArticleAddress address;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<Uri> onOpenLink, onOpenWeb;
  final VoidCallback onLogin;
  final VoidCallback? onBack;
  final bool focusComments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = articleProvider(address);
    final state = address.isValid ? ref.watch(provider) : null;
    final document = state?.asData?.value;
    final url = document?.url ?? address.webUri;
    final post = document?.actionPost(document.stats);
    final canMessage =
        post != null &&
        post.authorId != null &&
        post.commentTarget?.type.value == 12;
    final messageBusy =
        canMessage &&
        ref.watch(
          dynamicManagementProvider(post.id).select((state) => state.busy),
        );
    final resolved = ArticleAddress.fromWebUri(url);
    final saving =
        resolved != null &&
        ref.watch(
          articleFavoriteProvider(resolved).select((state) => state.busy),
        );
    void refresh() {
      if (resolved != null &&
          ref.read(articleFavoriteProvider(resolved)).busy) {
        return;
      }
      if (document?.statsCvId case final cvId?) {
        ref.invalidate(articleInfoProvider(cvId));
      }
      if (resolved != null) ref.invalidate(articleFavoriteProvider(resolved));
      ref.invalidate(provider);
    }

    final actions = <Widget>[
      if (state != null) ...[
        IconButton(
          tooltip: '在浏览器打开',
          onPressed: () => onOpenWeb(url),
          icon: const Icon(Icons.open_in_new_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (value) async {
            switch (value) {
              case 'copy':
                try {
                  await Clipboard.setData(ClipboardData(text: url.toString()));
                  if (context.mounted) showAppNotice(context, '专栏链接已复制');
                } on PlatformException {
                  if (context.mounted) showAppNotice(context, '复制失败，请重试');
                }
              case 'message':
                if (post != null) {
                  await sharePostToMessage(
                    context,
                    ref,
                    post,
                    onLogin: onLogin,
                  );
                }
              case 'refresh':
                refresh();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'copy', child: Text('复制链接')),
            if (canMessage)
              PopupMenuItem(
                value: 'message',
                enabled: !messageBusy,
                child: const Text('分享至消息'),
              ),
            PopupMenuItem(
              value: 'refresh',
              enabled: !saving,
              child: const Text('刷新'),
            ),
          ],
        ),
      ],
    ];
    Widget frame(Widget body) => ArticlePageFrame(
      title: '专栏',
      actions: actions,
      onBack: onBack,
      body: body,
    );
    if (state == null) return frame(const StateView.empty(message: '专栏地址无效'));
    return state.when(
      skipLoadingOnReload: false,
      skipLoadingOnRefresh: false,
      data: (document) => ArticleReaderLayout(
        key: PageStorageKey(address.location),
        document: document,
        actions: actions,
        onLogin: onLogin,
        onOpenUser: onOpenUser,
        onBack: onBack,
        focusComments: focusComments,
        sliver: _ArticleContent(
          document: document,
          onOpenUser: onOpenUser,
          onOpenLink: onOpenLink,
        ),
      ),
      loading: () => frame(const StateView.loading(message: '正在加载专栏…')),
      error: (error, _) => frame(
        StateView.error(
          message: error is AppFailure ? error.message : '专栏加载失败，请稍后再试',
          onAction: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}

final class _ArticleContent extends StatelessWidget {
  const _ArticleContent({
    required this.document,
    required this.onOpenUser,
    required this.onOpenLink,
  });
  final ArticleDocument document;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<Uri> onOpenLink;

  @override
  Widget build(BuildContext context) {
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
    final hasAuthor = document.author.isNotEmpty || date != null;
    final hasTitle = document.title.isNotEmpty;
    final accessMessage = document.accessMessage;
    Widget row(BuildContext context, int index, {bool measure = false}) {
      final block = blocks[index];
      final photo = imageIndexes[index];
      final child = photo == null
          ? _TextBlock(block: block, onOpenLink: measure ? null : onOpenLink)
          : _ArticleImage(
              block: block,
              images: images,
              index: photo,
              measure: measure,
            );
      return Padding(padding: const EdgeInsets.only(bottom: 12), child: child);
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasAuthor)
          Material(
            type: MaterialType.transparency,
            child: PostAuthorHeader(
              name: document.author,
              avatarUrl: document.authorAvatar,
              subtitle: date == null
                  ? ''
                  : MaterialLocalizations.of(context)
                        .formatCompactDate(date.toLocal()),
              onOpenAuthor: document.author.isEmpty || authorId == null
                  ? null
                  : () => onOpenUser(authorId),
            ),
          ),
        if (hasTitle) ...[
          if (hasAuthor) const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              document.title,
              style: PostCardSurface.titleStyleOf(context, inDetail: true),
            ),
          ),
        ],
        if (document.collection case final book?
            when accessMessage == null) ...[
          const SizedBox(height: 12),
          SelectionContainer.disabled(
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(book.name.isEmpty ? '查看文集' : book.name),
                subtitle: Text(
                  ['收录于文集', if (book.count.isNotEmpty) book.count].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenLink(book.id.webUri),
              ),
            ),
          ),
        ],
        if (accessMessage != null) ...[
          if (hasAuthor || hasTitle) const SizedBox(height: 12),
          Text(accessMessage, style: PostCardSurface.bodyStyleOf(context)),
        ],
        if (blocks.isNotEmpty &&
            (hasAuthor || hasTitle || accessMessage != null))
          const SizedBox(height: 12),
      ],
    );
    return PostCardSurface.sliver(
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: header),
          MeasuredListView.sliver(
            identities: blocks,
            itemBuilder: (context, index) => row(context, index),
            layoutBuilder: (context, index) =>
                row(context, index, measure: true),
          ),
        ],
      ),
    );
  }
}

final class _ArticleImage extends StatelessWidget {
  const _ArticleImage({
    required this.block,
    required this.images,
    required this.index,
    required this.measure,
  });

  final ArticleBlock block;
  final List<Uri> images;
  final int index;
  final bool measure;

  @override
  Widget build(BuildContext context) {
    final image = images[index];
    final bounds = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 960),
      child: AspectRatio(
        aspectRatio: (block.aspectRatio ?? 1.6).clamp(0.25, 8),
        child: measure
            ? null
            : AppNetworkImage(
                url: publicImageThumbnail(image, width: 1280).toString(),
                viewerOriginal: image,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
      ),
    );
    if (measure) return bounds;
    return SelectionContainer.disabled(
      child: Semantics(
        button: true,
        label: '查看图片 ${index + 1}',
        child: InkWell(
          onTap: () => showImageViewer(context, images, index),
          child: bounds,
        ),
      ),
    );
  }
}

final class _TextBlock extends StatefulWidget {
  const _TextBlock({required this.block, required this.onOpenLink});

  final ArticleBlock block;
  final ValueChanged<Uri>? onOpenLink;

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
    final style = PostCardSurface.bodyStyleOf(context);
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
                final target? when widget.onOpenLink != null =>
                  _recognizers.putIfAbsent(target, () {
                    return TapGestureRecognizer()
                      ..onTap = () => widget.onOpenLink?.call(target);
                  }),
                _ => null,
              },
            ),
        ],
      ),
      style: block.kind == ArticleBlockKind.heading
          ? style?.copyWith(fontWeight: FontWeight.w600)
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

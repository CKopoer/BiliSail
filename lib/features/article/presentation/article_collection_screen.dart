import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/public_image_variant.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/article_address.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/app_network_image.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart' show compactCount;
import '../application/article_provider.dart';
import '../domain/article_document.dart';
import 'article_page_frame.dart';

final class ArticleCollectionScreen extends ConsumerStatefulWidget {
  const ArticleCollectionScreen({
    super.key,
    required this.id,
    required this.onOpenUser,
    required this.onOpenArticle,
    required this.onOpenWeb,
  });
  final ArticleCollectionId id;
  final ValueChanged<UserId> onOpenUser;
  final ValueChanged<ArticleAddress> onOpenArticle;
  final ValueChanged<Uri> onOpenWeb;
  @override
  ConsumerState<ArticleCollectionScreen> createState() =>
      _ArticleCollectionScreenState();
}

class _ArticleCollectionScreenState
    extends ConsumerState<ArticleCollectionScreen> {
  bool _reverse = false;

  @override
  Widget build(BuildContext context) {
    final provider = articleCollectionProvider(widget.id);
    final state = widget.id.isValid ? ref.watch(provider) : null;
    return ArticlePageFrame(
      title: '文集',
      actions: [
        if (state?.asData?.value.entries.isNotEmpty == true)
          IconButton(
            tooltip: _reverse ? '切换为正序' : '切换为倒序',
            icon: Icon(_reverse ? Icons.arrow_upward : Icons.arrow_downward),
            onPressed: () => setState(() => _reverse = !_reverse),
          ),
        if (state != null)
          IconButton(
            tooltip: '在浏览器打开',
            icon: const Icon(Icons.open_in_new_outlined),
            onPressed: () => widget.onOpenWeb(widget.id.webUri),
          ),
      ],
      body: state == null
          ? const StateView.empty(message: '文集地址无效')
          : state.when(
              skipLoadingOnReload: false,
              data: (book) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                    key: PageStorageKey(widget.id.location),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: book.entries.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _header(context, book);
                      }
                      final entry =
                          book.entries[_reverse
                              ? book.entries.length - index
                              : index - 1];
                      final info = [
                        if (entry.summary.isNotEmpty) entry.summary,
                        if (entry.views case final views?)
                          '${compactCount(views)} 阅读',
                      ].join('\n');
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 0,
                        ),
                        leading: entry.cover == null
                            ? null
                            : _cover(entry.cover!, width: 84, height: 52),
                        title: Text(
                          entry.title.isEmpty
                              ? '专栏 ${entry.address.id}'
                              : entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: info.isEmpty
                            ? null
                            : Text(
                                info,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onOpenArticle(entry.address),
                      );
                    },
                  ),
                ),
              ),
              loading: () => const StateView.loading(message: '正在加载文集…'),
              error: (e, _) => StateView.error(
                message: e is AppFailure ? e.message : '文集加载失败',
                onAction: () => ref.invalidate(provider),
              ),
            ),
    );
  }

  Widget _header(BuildContext context, ArticleCollection book) {
    final meta = [
      '${book.entries.length} 篇专栏',
      if (book.words case final words?) '${compactCount(words)} 字',
      if (book.views case final views?) '${compactCount(views)} 阅读',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book.cover case final image?) ...[
              _cover(image, width: 70, height: 92),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.name.isEmpty ? '文集 ${widget.id.value}' : book.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (book.author.isNotEmpty)
                    TextButton(
                      onPressed: book.authorId == null
                          ? null
                          : () => widget.onOpenUser(book.authorId!),
                      child: Text(book.author),
                    ),
                  Text(meta, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        if (book.entries.isEmpty) const StateView.empty(message: '文集暂无专栏'),
      ],
    );
  }

  Widget _cover(Uri uri, {required double width, required double height}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: width,
          height: height,
          child: AppNetworkImage(
            url: publicImageThumbnail(uri, width: 320).toString(),
            fit: BoxFit.cover,
          ),
        ),
      );
}

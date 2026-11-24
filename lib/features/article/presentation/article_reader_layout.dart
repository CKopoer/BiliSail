import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/presentation/motion_preferences.dart';
import '../../../core/presentation/page_back_scope.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/content_link.dart';
import '../../../domain/responsive_layout_settings.dart';
import '../../../domain/user.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/comments_panel.dart';
import '../../../shared/ui/content_link_scope.dart';
import '../../settings/application/settings_controller.dart';
import '../domain/article_document.dart';
import 'article_action_bar.dart';
import 'article_page_frame.dart';

class ArticleReaderLayout extends ConsumerStatefulWidget {
  const ArticleReaderLayout({
    super.key,
    required this.document,
    required this.sliver,
    required this.actions,
    required this.onLogin,
    required this.onOpenUser,
    this.onBack,
    this.focusComments = false,
  });
  final ArticleDocument document;
  final Widget sliver;
  final List<Widget> actions;
  final VoidCallback onLogin;
  final ValueChanged<UserId> onOpenUser;
  final VoidCallback? onBack;
  final bool focusComments;

  @override
  ConsumerState<ArticleReaderLayout> createState() =>
      _ArticleReaderLayoutState();
}

class _ArticleReaderLayoutState extends ConsumerState<ArticleReaderLayout> {
  final _reading = ScrollController();
  final _showBar = ValueNotifier(true);
  final _commentBack = PageBackController();
  bool _commentsSelected = false, _mountedComments = false;
  int _scrollCommentsToTop = 0;
  double? _articleFractionDraft;
  ContentLink? _link;

  @override
  void initState() {
    super.initState();
    _commentsSelected = widget.focusComments;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = ContentLinkScope.of(context);
    if (_link != link && link.comment != null) _commentsSelected = true;
    _link = link;
  }

  @override
  void dispose() {
    _reading.dispose();
    _showBar.dispose();
    _commentBack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _layout(
    ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.value?.responsiveLayout.articleWidthFraction,
      ),
    ),
  );

  Widget _layout(double? savedArticleFraction) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth.clamp(0.0, 1440.0);
      final wide =
          widget.document.accessMessage == null &&
          width >= 900 &&
          width / MediaQuery.textScalerOf(context).scale(14) >= 50;
      final available =
          widget.document.commentTarget != null &&
          !widget.document.commentForbidden &&
          widget.document.accessMessage == null;
      final commentsOnly =
          !wide && widget.document.accessMessage == null && _commentsSelected;
      final showComments = wide || commentsOnly;
      if (showComments) _mountedComments = true;
      final articleFraction =
          _articleFractionDraft ??
          savedArticleFraction ??
          (wide
              ? (700 / width).clamp(
                  ResponsiveLayoutSettings.minArticleWidthFraction,
                  .54,
                )
              : .54);
      final articleWidth = wide ? width * articleFraction : width;

      bool back() {
        if (showComments && _commentBack.goBack()) return true;
        if (!commentsOnly) return false;
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _commentsSelected = false);
        return true;
      }

      void openComments() => setState(() {
        if (wide) {
          _scrollCommentsToTop++;
        } else {
          _commentsSelected = true;
        }
      });
      final body = Center(
        child: SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Visibility(
                visible: !commentsOnly,
                maintainState: true,
                child: SizedBox(
                  width: articleWidth,
                  child: _reader(
                    articleWidth,
                    !wide || available ? openComments : null,
                  ),
                ),
              ),
              if (_mountedComments)
                Visibility(
                  visible: showComments,
                  maintainState: true,
                  child: SizedBox(
                    width: wide ? width - articleWidth : width,
                    child: WorkspaceActivity(
                      active:
                          showComments && WorkspaceActivity.isActive(context),
                      previewing:
                          showComments && WorkspaceActivity.isVisible(context),
                      child: PageBackScope(
                        controller: _commentBack,
                        route: ModalRoute.of(context),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: wide
                                ? Border(
                                    left: BorderSide(
                                      color: Theme.of(context).dividerColor,
                                    ),
                                  )
                                : null,
                          ),
                          child: _comments(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      return ListenableBuilder(
        listenable: _commentBack,
        child: body,
        builder: (context, body) {
          final localBack =
              commentsOnly || (showComments && _commentBack.canGoBack);
          return PageBackHandler(
            enabled: localBack,
            onBack: back,
            child: ArticlePageFrame(
              title: commentsOnly ? '专栏评论' : '专栏',
              actions: [
                if (wide) _ratioControl(articleFraction),
                if (!commentsOnly) ...widget.actions,
              ],
              onBack: localBack ? back : widget.onBack,
              body: body!,
            ),
          );
        },
      );
    },
  );

  Future<void> _saveArticleFraction(double fraction) async {
    if (_articleFractionDraft == null) return;
    setState(() => _articleFractionDraft = null);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setArticleWidthFraction(fraction);
    } catch (_) {
      if (mounted) showAppNotice(context, '分栏比例保存失败，请重试');
    }
  }

  Widget _ratioControl(double fraction) {
    String label(double value) {
      final percent = (value * 100).round();
      return '专栏 $percent% · 评论 ${100 - percent}%';
    }

    return MenuAnchor(
      consumeOutsideTap: true,
      onClose: () {
        if (_articleFractionDraft == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _articleFractionDraft = null);
        });
      },
      style: const MenuStyle(alignment: AlignmentDirectional.bottomEnd),
      builder: (context, controller, _) => IconButton(
        tooltip: '调节专栏与评论宽度',
        icon: const Icon(Icons.vertical_split_outlined),
        onPressed: controller.isOpen ? controller.close : controller.open,
      ),
      menuChildren: [
        SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label(fraction)),
              Slider(
                min: ResponsiveLayoutSettings.minArticleWidthFraction,
                max: ResponsiveLayoutSettings.maxArticleWidthFraction,
                value: fraction,
                semanticFormatterCallback: label,
                onChanged: (value) =>
                    setState(() => _articleFractionDraft = value),
                onChangeEnd: _saveArticleFraction,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _comments() {
    final target = widget.document.commentTarget;
    if (target == null || widget.document.commentForbidden) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            widget.document.commentForbidden
                ? '该专栏已关闭评论'
                : '该专栏暂不支持评论，请在官方页面查看',
          ),
        ),
      );
    }
    return CommentsPanel(
      target: target,
      replyCount: widget.document.commentCount,
      onLogin: widget.onLogin,
      onOpenUser: widget.onOpenUser,
      scrollToTopRequest: _scrollCommentsToTop,
    );
  }

  Widget _reader(double width, VoidCallback? onComments) => Scaffold(
    backgroundColor: Colors.transparent,
    extendBody: true,
    resizeToAvoidBottomInset: false,
    // Keep the track and the trailing space constant throughout a thumb drag.
    // Scaffold supplies the footer's natural height through the body padding.
    bottomNavigationBar: widget.document.accessMessage == null
        ? ValueListenableBuilder<bool>(
            valueListenable: _showBar,
            child: ArticleActionBar(
              document: widget.document,
              onLogin: widget.onLogin,
              onComments: onComments,
            ),
            builder: (context, visible, child) => IgnorePointer(
              ignoring: !visible,
              child: ExcludeFocus(
                excluding: !visible,
                child: ExcludeSemantics(
                  excluding: !visible,
                  child: ClipRect(
                    child: AnimatedSlide(
                      duration: shouldReduceMotion(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      offset: visible ? Offset.zero : const Offset(0, 1),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          )
        : null,
    body: Builder(
      builder: (context) {
        final bottom = MediaQuery.paddingOf(context).bottom;
        final side = ((width - 800) / 2).clamp(12.0, double.infinity);
        return NotificationListener<ScrollUpdateNotification>(
          onNotification: (notice) {
            final delta = notice.scrollDelta;
            if (notice.depth == 0 &&
                notice.metrics.axis == Axis.vertical &&
                !notice.metrics.outOfRange &&
                delta != null &&
                delta != 0) {
              _showBar.value = delta < 0;
            }
            return false;
          },
          child: Scrollbar(
            controller: _reading,
            thumbVisibility: true,
            interactive: true,
            scrollbarOrientation: ScrollbarOrientation.right,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: SelectionArea(
                child: CustomScrollView(
                  key: const PageStorageKey('article-reading'),
                  controller: _reading,
                  primary: false,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 12, side, bottom + 12),
                      sliver: widget.sliver,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

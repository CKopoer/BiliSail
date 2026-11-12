import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_dialog.dart';
import '../../core/platform/external_links.dart';
import '../../core/presentation/workspace_activity.dart';
import '../../core/presentation/page_back_scope.dart';
import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/user.dart';
import '../../domain/comment_target.dart';
import 'app_network_image.dart';
import 'app_notice.dart';
import 'emoticon_picker_dialog.dart';
import 'scroll_collapsing_header.dart';
import 'bili_icons.dart';
import 'comment_rich_content.dart';
import 'comment_badge.dart';
import 'comment_text_styles.dart';
import 'comment_actions.dart';
import 'comment_mention_dialog.dart';
import '../../features/comments/domain/comment_composer.dart';
import '../../features/comments/application/comments_controller.dart';
import '../../features/comments/application/comment_link_resolver.dart';
import '../../features/comments/domain/comments_repository.dart';

class CommentsPanel extends ConsumerStatefulWidget {
  const CommentsPanel({
    super.key,
    required this.target,
    this.replyCount,
    this.onSeek,
    this.onLogin,
    this.onOpenUser,
    this.playbackPosition,
    this.composerOnly = false,
    this.onSent,
  });
  final CommentTarget target;
  final int? replyCount;
  final ValueChanged<Duration>? onSeek;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;
  final Duration? Function()? playbackPosition;
  final bool composerOnly;
  final VoidCallback? onSent;
  @override
  ConsumerState<CommentsPanel> createState() => _CommentsPanelState();
}

class _CommentsPanelState extends ConsumerState<CommentsPanel> {
  NotifierProvider<CommentsController, CommentsState> get _provider =>
      commentsProviderFor(widget.target);
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _composerFocus = FocusNode(skipTraversal: true);
  final _emotePickerOpen = ValueNotifier(false);
  final _draftVersion = ValueNotifier(0);
  final _images = <CommentLocalImage>[];
  final _mentions = <String, UserId>{};
  bool _syncToDynamic = false, _pickingImages = false;
  int _draftGeneration = 0;
  final _topScroll = HeaderScrollController();
  // Detail always opens at the top; do not retain a PageStorage entry per root.
  final _replyScroll = HeaderScrollController(
    keepScrollOffset: false,
    coordinateWithHeader: true,
  );
  var _replyStorage = PageStorageBucket();
  double _topOffset = 0;
  String? _shownRoot;
  bool _loadMoreScheduled = false;
  RequestCancellation? _linkCancellation;
  @override
  void initState() {
    super.initState();
    _topScroll.addListener(() => _topOffset = _topScroll.offset);
  }

  @override
  void didUpdateWidget(covariant CommentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target) {
      _linkCancellation?.cancel();
      _resetDraft();
      _topOffset = 0;
      _shownRoot = null;
      final target = widget.target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.target == target && _topScroll.hasClients) {
          _topScroll.jumpTo(0);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!WorkspaceActivity.isActive(context)) _linkCancellation?.cancel();
  }

  @override
  void dispose() {
    _linkCancellation?.cancel();
    _text.dispose();
    _focus.dispose();
    _composerFocus.dispose();
    _emotePickerOpen.dispose();
    _draftVersion.dispose();
    _topScroll.dispose();
    _replyScroll.dispose();
    super.dispose();
  }

  void _login() {
    final action = widget.onLogin;
    if (action != null) {
      action();
    } else {
      showAppNotice(context, '请先登录后操作');
    }
  }

  Future<void> _openLink(Uri uri) async {
    _linkCancellation?.cancel();
    final cancellation = RequestCancellation();
    _linkCancellation = cancellation;
    final target = widget.target;
    final controller = ref.read(_provider.notifier);
    final state = ref.read(_provider);
    bool isCurrent() =>
        mounted &&
        !cancellation.isCancelled &&
        widget.target == target &&
        WorkspaceActivity.isActive(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        controller.isCurrentAccount(state.accountScope, state.sessionEpoch);
    var opened = false;
    try {
      final navigate = ref.read(commentVideoNavigatorProvider);
      if (navigate != null) {
        final video = await ref
            .read(commentLinkResolverProvider)
            .resolve(uri, cancellation);
        if (!mounted || !isCurrent()) return;
        if (video != null) {
          if (ModalRoute.of(context) is PopupRoute) Navigator.of(context).pop();
          navigate(video);
          return;
        }
      }
      if (!isCurrent()) return;
      opened = await ref.read(webLinkOpenerProvider)(uri);
    } on AppFailure catch (error) {
      if (mounted && isCurrent() && error.kind != AppFailureKind.cancelled) {
        showAppNotice(context, error.message);
      }
      return;
    } on PlatformException {
      opened = false;
    } finally {
      if (identical(_linkCancellation, cancellation)) _linkCancellation = null;
    }
    if (mounted && isCurrent() && !opened) {
      showAppNotice(context, '无法打开浏览器，请稍后重试');
    }
  }

  void _handleOpenLink(Uri uri) => unawaited(_openLink(uri));

  void _resetDraft() {
    ++_draftGeneration;
    _text.clear();
    _images.clear();
    _mentions.clear();
    _syncToDynamic = false;
    _pickingImages = false;
    _emotePickerOpen.value = false;
    _draftVersion.value++;
  }

  Future<void> _pickImages() async {
    if (_pickingImages) return;
    final generation = _draftGeneration;
    final target = widget.target;
    final provider = _provider;
    final controller = ref.read(provider.notifier);
    final state = ref.read(provider);
    _pickingImages = true;
    _emotePickerOpen.value = true;
    _draftVersion.value++;
    try {
      final images = await ref.read(commentImagePickerProvider)(
        CommentLocalImage.maxCount - _images.length,
      );
      if (!mounted ||
          generation != _draftGeneration ||
          widget.target != target ||
          !controller.isCurrentAccount(
            state.accountScope,
            state.sessionEpoch,
          )) {
        return;
      }
      _images.addAll(images.take(CommentLocalImage.maxCount - _images.length));
      _draftVersion.value++;
    } catch (error) {
      if (mounted &&
          generation == _draftGeneration &&
          controller.isCurrentAccount(state.accountScope, state.sessionEpoch)) {
        showAppNotice(
          context,
          error is AppFailure ? error.message : '无法读取图片，请重新选择 JPG、PNG 或 GIF 图片',
        );
      }
    } finally {
      if (mounted && generation == _draftGeneration) {
        _pickingImages = false;
        _emotePickerOpen.value = false;
        _draftVersion.value++;
        _focus.requestFocus();
      }
    }
  }

  Future<void> _mention() async {
    final generation = _draftGeneration;
    final target = widget.target;
    final controller = ref.read(_provider.notifier);
    final state = ref.read(_provider);
    _emotePickerOpen.value = true;
    CommentMention? user;
    try {
      user = await showAppDialog<CommentMention>(
        context: context,
        builder: (_) => CommentMentionDialog(search: controller.searchMentions),
      );
    } finally {
      if (mounted) _emotePickerOpen.value = false;
    }
    if (!mounted ||
        generation != _draftGeneration ||
        target != widget.target ||
        !controller.isCurrentAccount(state.accountScope, state.sessionEpoch)) {
      return;
    }
    if (user != null) {
      _mentions[user.name] = user.id;
      _text.value = insertCommentEmote(_text.value, '@${user.name} ');
    }
    _focus.requestFocus();
  }

  void _insertPosition() {
    final position = widget.playbackPosition?.call();
    if (position == null) {
      showAppNotice(context, '播放器尚未就绪');
      return;
    }
    final seconds = position.inSeconds;
    final time = seconds >= 3600
        ? '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    _text.value = insertCommentEmote(_text.value, '$time ');
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final state = ref.read(_provider);
    if (widget.composerOnly && state.replyTarget == null) return;
    if (!state.signedIn) {
      _login();
      return;
    }
    final text = _text.text, target = widget.target;
    final root = state.openRoot?.id;
    final version = _draftVersion.value;
    final generation = _draftGeneration;
    final ok = await ref
        .read(_provider.notifier)
        .send(
          text,
          images: List.of(_images),
          mentions: Map.of(_mentions),
          syncToDynamic: _syncToDynamic,
        );
    if (ok &&
        mounted &&
        target == widget.target &&
        generation == _draftGeneration &&
        version == _draftVersion.value &&
        text == _text.text) {
      final current = ref.read(_provider);
      if (current.openRoot?.id == root && current.replyTarget == null) {
        _resetDraft();
      }
      widget.onSent?.call();
    }
  }

  Future<void> _emotes() async {
    final target = widget.target;
    final provider = _provider;
    final controller = ref.read(provider.notifier);
    final snapshot = ref.read(provider);
    final scope = snapshot.accountScope, epoch = snapshot.sessionEpoch;
    final container = ProviderScope.containerOf(context);
    unawaited(controller.loadEmotes());
    _emotePickerOpen.value = true;
    CommentEmote? emote;
    try {
      emote = await showAppDialog<CommentEmote>(
        context: context,
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: _CommentEmoteDialog(target: target),
        ),
      );
    } finally {
      if (mounted) _emotePickerOpen.value = false;
    }
    if (!mounted ||
        widget.target != target ||
        !controller.isCurrentAccount(scope, epoch) ||
        !ref.read(provider).signedIn) {
      return;
    }
    if (emote != null) {
      _text.value = insertCommentEmote(_text.value, emote.text);
    }
    _focus.requestFocus();
  }

  List<CommentEntry>? _indexedComments;
  Map<String, int> _commentIndices = const {};

  bool _closeDetail() {
    if (ref.read(_provider).openRoot == null) return false;
    ref.read(_provider.notifier).closeReplies();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.target.oid.isEmpty) {
      return const Center(child: Text('暂无评论信息'));
    }
    final rootId = ref.watch(_provider.select((state) => state.openRoot?.id));
    ref.listen(
      _provider.select((value) => (value.accountScope, value.sessionEpoch)),
      (_, _) {
        _linkCancellation?.cancel();
        _resetDraft();
        _topOffset = 0;
        _shownRoot = null;
      },
    );
    if (widget.composerOnly) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Consumer(
            builder: (context, ref, _) {
              final message = ref.watch(
                _provider.select((state) => state.message),
              );
              return message == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(message),
                    );
            },
          ),
          Flexible(child: _composer()),
        ],
      );
    }
    if (_shownRoot != rootId) {
      _shownRoot = rootId;
      _replyStorage = PageStorageBucket();
      final offset = rootId == null ? _topOffset : 0.0;
      final scroll = rootId == null ? _topScroll : _replyScroll;
      final target = widget.target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            widget.target == target &&
            _shownRoot == rootId &&
            scroll.hasClients) {
          final targetOffset = offset.clamp(
            0.0,
            scroll.position.maxScrollExtent,
          );
          // A nested jump also moves the player. A newly opened reply list is
          // already at zero, so leave the current player height alone.
          if (scroll.offset != targetOffset) scroll.jumpTo(targetOffset);
        }
      });
    }
    return PageBackHandler(
      enabled: rootId != null,
      onBack: _closeDetail,
      child: CustomMultiChildLayout(
        delegate: _CommentsLayoutDelegate(),
        children: [
          LayoutId(
            id: _CommentsSlot.header,
            child: ClipRect(
              child: OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                fit: OverflowBoxFit.deferToChild,
                alignment: Alignment.topCenter,
                child: _header(),
              ),
            ),
          ),
          LayoutId(id: _CommentsSlot.list, child: _list()),
          LayoutId(id: _CommentsSlot.composer, child: _composer()),
        ],
      ),
    );
  }

  Widget _header() => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.sort,
            state.totalCount,
            state.busy,
            state.message,
            state.openRoot?.id,
          ),
        ),
      );
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      final theme = Theme.of(context);
      final styles = CommentTextStyles(theme);
      final root = state.openRoot;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (root == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 8, 2),
              child: Row(
                children: [
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => controller.load(sort: CommentSort.hot),
                    child: Text(
                      '最热',
                      style: styles.sort.copyWith(
                        color: state.sort == CommentSort.hot
                            ? styles.sort.color
                            : styles.metadata.color,
                      ),
                    ),
                  ),
                  Text('|', style: theme.textTheme.bodySmall),
                  TextButton(
                    onPressed: state.busy
                        ? null
                        : () => controller.load(sort: CommentSort.latest),
                    child: Text(
                      '最新',
                      style: styles.sort.copyWith(
                        color: state.sort == CommentSort.latest
                            ? styles.sort.color
                            : styles.metadata.color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (state.totalCount != null)
                    Text('${state.totalCount} 条', style: styles.metadata),
                  IconButton(
                    tooltip: '刷新评论',
                    onPressed: state.busy
                        ? null
                        : () => controller.load(refresh: true),
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '返回评论',
                      onPressed: _closeDetail,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(child: Text('评论详情', style: styles.detailTitle)),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          if (state.message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(state.message!, style: theme.textTheme.bodySmall),
            ),
        ],
      );
    },
  );

  Widget _composer() => Focus(
    focusNode: _composerFocus,
    child: TextFieldTapRegion(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _composerFocus,
          _emotePickerOpen,
          _draftVersion,
          _text,
        ]),
        builder: (context, _) => _composerContent(
          expanded:
              widget.composerOnly ||
              _composerFocus.hasFocus ||
              _emotePickerOpen.value,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 200),
        ),
      ),
    ),
  );

  Widget _composerContent({
    required bool expanded,
    required Duration duration,
  }) => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.busy,
            state.loading,
            state.replyLoading,
            state.signedIn,
            state.uncertain.contains('send'),
            state.replyTarget,
            state.openRoot?.id,
          ),
        ),
      );
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      final theme = Theme.of(context);
      final root = state.openRoot;
      final styles = CommentTextStyles(theme);
      final iconStyle = IconButton.styleFrom(
        minimumSize: const Size.square(32),
        padding: const EdgeInsets.all(6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.uncertain.contains('send'))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton(
                  onPressed: controller.acknowledgeSend,
                  child: const Text('我已核对结果，允许再次发送'),
                ),
              ),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: .3),
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (state.replyTarget != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '回复 @${state.replyTarget!.author}',
                            style: styles.metadata,
                          ),
                        ),
                        if (!widget.composerOnly)
                          IconButton(
                            tooltip: '取消回复',
                            style: iconStyle,
                            onPressed: state.busy
                                ? null
                                : controller.cancelTarget,
                            icon: const Icon(Icons.close, size: 16),
                          ),
                      ],
                    ),
                  AnimatedSize(
                    duration: duration,
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      // Keep native Enter behavior stable while collapsed.
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: styles.input,
                      readOnly: !state.signedIn,
                      onTap: state.signedIn ? null : _login,
                      onTapOutside: (_) => _composerFocus.unfocus(),
                      minLines: 1,
                      maxLines: expanded ? 4 : 1,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintStyle: state.signedIn
                            ? styles.inputHint
                            : styles.disabledInput,
                        hintText: state.signedIn
                            ? root == null
                                  ? '发一条友善的评论'
                                  : '发一条友善的回复'
                            : '登录后参与评论',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => SizedBox.square(
                          dimension: 76,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  _images[index].bytes,
                                  fit: BoxFit.cover,
                                  cacheWidth: 160,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton.filledTonal(
                                  tooltip: '移除图片 ${index + 1}',
                                  style: iconStyle,
                                  onPressed: state.busy
                                      ? null
                                      : () {
                                          _images.removeAt(index);
                                          _draftVersion.value++;
                                        },
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (state.openRoot != null || state.replyTarget != null)
                      Text(
                        '图片仅支持主评论，请取消回复后发布',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                  ],
                  ExcludeFocus(
                    excluding: !expanded,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        ),
                        child: expanded
                            ? _composerToolbar(state, iconStyle)
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _composerToolbar(CommentsState state, ButtonStyle iconStyle) {
    final theme = Theme.of(context);
    final styles = CommentTextStyles(theme);
    final toolStyle = iconStyle.copyWith(
      minimumSize: const WidgetStatePropertyAll(Size.square(40)),
    );
    final canEdit = state.signedIn && !state.busy && !_pickingImages;
    final replying = state.openRoot != null || state.replyTarget != null;
    final length = _text.text.runes.length;
    final canSend =
        canEdit &&
        (!widget.composerOnly || state.replyTarget != null) &&
        !state.loading &&
        !state.replyLoading &&
        !state.uncertain.contains('send') &&
        length <= 1000 &&
        (_text.text.trim().isNotEmpty || _images.isNotEmpty) &&
        !(replying && _images.isNotEmpty);
    final tools = Wrap(
      spacing: 2,
      children: [
        IconButton(
          tooltip: '选择表情',
          style: toolStyle,
          iconSize: 18,
          onPressed: canEdit ? _emotes : null,
          icon: const Icon(BiliIcons.emoji),
        ),
        if (!replying)
          IconButton(
            tooltip: '添加图片（最多9张，每张10MB）',
            style: toolStyle,
            iconSize: 18,
            onPressed: canEdit && _images.length < CommentLocalImage.maxCount
                ? _pickImages
                : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        IconButton(
          tooltip: '@用户',
          style: toolStyle,
          iconSize: 18,
          onPressed: canEdit ? _mention : null,
          icon: const Icon(Icons.alternate_email),
        ),
        if (widget.playbackPosition != null)
          IconButton(
            tooltip: '插入当前播放时间',
            style: toolStyle,
            iconSize: 18,
            onPressed: canEdit ? _insertPosition : null,
            icon: const Icon(Icons.schedule_outlined),
          ),
        IconButton(
          tooltip: '同步到动态',
          style: toolStyle,
          iconSize: 18,
          isSelected: _syncToDynamic,
          onPressed: canEdit
              ? () {
                  _syncToDynamic = !_syncToDynamic;
                  _draftVersion.value++;
                }
              : null,
          icon: const Icon(Icons.repeat),
          selectedIcon: Icon(Icons.repeat, color: theme.colorScheme.primary),
        ),
      ],
    );
    final submit = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '$length/1000',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.counter.copyWith(
              color: length > 1000
                  ? theme.colorScheme.error
                  : styles.counter.color,
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(56, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            textStyle: styles.submit,
            foregroundColor: Colors.white,
            disabledForegroundColor: styles.metadata.color,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: canSend ? _send : null,
          child: state.busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发布'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_syncToDynamic)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '发布时同步到动态',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 380 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tools,
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerRight, child: submit),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: tools),
                        const SizedBox(width: 8),
                        submit,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _entry(
    CommentEntry comment, {
    required bool preview,
    bool root = false,
  }) => _CommentTile(
    key: ValueKey((root ? 'comment-root' : 'comment', comment.id)),
    provider: _provider,
    comment: comment,
    preview: preview,
    onOpenUser: widget.onOpenUser,
    onOpenLink: _handleOpenLink,
    onSeek: widget.onSeek,
    onLogin: _login,
    onReplyFocus: _focus.requestFocus,
  );

  void _scheduleLoadMore(BuildContext context) {
    if (_loadMoreScheduled) return;
    _loadMoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMoreScheduled = false;
      if (!mounted ||
          !context.mounted ||
          widget.composerOnly ||
          widget.target.oid.isEmpty ||
          !WorkspaceActivity.isActive(context)) {
        return;
      }
      // Read the current branch after layout: a target/account/detail switch
      // may have replaced the list since the notification was dispatched.
      final state = ref.read(_provider);
      final replies = state.openRoot != null;
      if (state.busy ||
          (replies ? state.replyLoading : state.loading) ||
          (replies ? state.replyLoadFailed : state.loadFailed) ||
          !(replies ? state.replyHasMore : state.hasMore) ||
          (replies ? state.replyPage : state.page) == 0) {
        return;
      }
      final scroll = replies ? _replyScroll : _topScroll;
      if (!scroll.hasClients ||
          !scroll.position.hasContentDimensions ||
          scroll.position.extentAfter > 240) {
        return;
      }
      final controller = ref.read(_provider.notifier);
      unawaited(replies ? controller.loadReplies() : controller.load());
    });
    // Metrics can arrive after layout. Request one check, without polling.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _list() => Consumer(
    builder: (context, ref, _) {
      ref.watch(
        _provider.select(
          (state) => (
            state.openRoot == null ? state.items : state.replyItems,
            state.openRoot,
            state.openRoot == null ? state.sort : null,
            state.openRoot == null ? state.loading : state.replyLoading,
            state.openRoot == null ? state.hasMore : state.replyHasMore,
            state.openRoot == null ? state.loadFailed : state.replyLoadFailed,
            state.message,
            state.openRoot == null ? state.totalCount : null,
          ),
        ),
      );
      final state = ref.read(_provider);
      final root = state.openRoot;
      ref.listen(_provider.select((state) => state.busy), (previous, busy) {
        if (previous == true && !busy) _scheduleLoadMore(context);
      });
      final active = WorkspaceActivity.isActive(context);
      _topScroll.configure(context, active: active && root == null);
      _replyScroll.configure(context, active: active && root != null);
      _scheduleLoadMore(context);
      final comments = root == null ? state.items : state.replyItems;
      final loading = root == null ? state.loading : state.replyLoading;
      final more = root == null ? state.hasMore : state.replyHasMore;
      final prefix = root == null ? 0 : 2;
      if (!identical(_indexedComments, comments)) {
        _indexedComments = comments;
        _commentIndices = {
          for (var index = 0; index < comments.length; index++)
            comments[index].id: index,
        };
      }
      final list = ListView.builder(
        controller: root == null ? _topScroll : _replyScroll,
        key: PageStorageKey(
          'comments:${widget.target.type.name}:${widget.target.oid}:${root?.id ?? state.sort.name}',
        ),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: prefix + comments.length + 1,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<(String, String)>) return null;
          if (key.value.$1 == 'comment-root') {
            return root?.id == key.value.$2 ? 0 : null;
          }
          final index = _commentIndices[key.value.$2];
          return index == null ? null : prefix + index;
        },
        itemBuilder: (context, index) {
          if (root != null && index < prefix) {
            return index == 0
                ? _entry(root, preview: false, root: true)
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '全部回复 ${root.replyCount}',
                      style: CommentTextStyles(Theme.of(context)).sectionTitle,
                    ),
                  );
          }
          final commentIndex = index - prefix;
          if (commentIndex < comments.length) {
            return _entry(comments[commentIndex], preview: root == null);
          }
          if (loading) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (comments.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(
                    state.message != null
                        ? '暂时无法加载评论'
                        : (root?.replyCount ?? state.totalCount ?? 0) > 0 ||
                              (root == null && (widget.replyCount ?? 0) > 0)
                        ? '当前会话未返回可展示的评论'
                        : '还没有评论，来聊聊吧',
                    style: CommentTextStyles(Theme.of(context)).empty,
                  ),
                  if (more) _loadMore(root),
                ],
              ),
            );
          }
          if (more) return _loadMore(root);
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                comments.length >= 500 ? '已显示 500 条评论' : '没有更多了',
                style: CommentTextStyles(Theme.of(context)).footer,
              ),
            ),
          );
        },
      );
      // NestedScrollView creates positions with persistence enabled itself.
      // Bound reply storage to this one detail visit despite that default.
      return NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            _scheduleLoadMore(context);
          }
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0 &&
                notification.metrics.axis == Axis.vertical &&
                switch (notification) {
                  ScrollUpdateNotification(:final scrollDelta) =>
                    (scrollDelta ?? 0) > 0,
                  OverscrollNotification(:final overscroll) => overscroll > 0,
                  _ => false,
                }) {
              _scheduleLoadMore(context);
            }
            return false;
          },
          child: root == null
              ? list
              : PageStorage(bucket: _replyStorage, child: list),
        ),
      );
    },
  );

  Widget _loadMore(CommentEntry? root) => Consumer(
    builder: (context, ref, _) {
      final busy = ref.watch(_provider.select((state) => state.busy));
      final state = ref.read(_provider);
      final controller = ref.read(_provider.notifier);
      return Center(
        child: TextButton(
          onPressed: busy
              ? null
              : () =>
                    root == null ? controller.load() : controller.loadReplies(),
          child: Text(
            (root == null ? state.loadFailed : state.replyLoadFailed)
                ? '重试加载'
                : '加载更多',
            style: CommentTextStyles(Theme.of(context)).footer,
          ),
        ),
      );
    },
  );
}

final class _CommentEmoteDialog extends ConsumerWidget {
  const _CommentEmoteDialog({required this.target});
  final CommentTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = target.type == CommentTargetType.video
        ? videoCommentsControllerProvider(target.oid)
        : commentsControllerProvider(target);
    final state = ref.watch(provider);
    return EmoticonPickerDialog(
      title: '评论表情包',
      loading: state.emotesLoading,
      message: state.emotesMessage,
      emptyMessage: '暂无可用表情',
      onRetry: ref.read(provider.notifier).loadEmotes,
      packageNames: [for (final package in state.emotePackages) package.name],
      packageBuilder: (context, packageIndex) {
        final package = state.emotePackages[packageIndex];
        return GridView.builder(
          key: PageStorageKey('comment-emoticon-package-$packageIndex'),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 72,
            mainAxisExtent: 56,
          ),
          itemCount: package.items.length,
          itemBuilder: (context, index) {
            final emote = package.items[index];
            return Tooltip(
              message: emote.text,
              child: TextButton(
                onPressed: !state.signedIn || state.busy
                    ? null
                    : () => Navigator.pop(context, emote),
                child: emote.imageUrl == null
                    ? Text(
                        emote.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : AppNetworkImage(
                        url: emote.imageUrl.toString(),
                        width: 32,
                        height: 32,
                        fit: BoxFit.contain,
                        cacheWidth: 96,
                        cacheHeight: 96,
                        errorBuilder: (_, _, _) => Text(
                          emote.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CommentTile extends ConsumerStatefulWidget {
  const _CommentTile({
    super.key,
    required this.provider,
    required this.comment,
    required this.onLogin,
    required this.onReplyFocus,
    this.preview = true,
    this.onOpenUser,
    required this.onOpenLink,
    this.onSeek,
  });
  final NotifierProvider<CommentsController, CommentsState> provider;
  final CommentEntry comment;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<Uri> onOpenLink;
  final ValueChanged<Duration>? onSeek;
  final bool preview;
  final VoidCallback onLogin, onReplyFocus;

  @override
  ConsumerState<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<_CommentTile> {
  Widget? _content;

  @override
  void didUpdateWidget(covariant _CommentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider ||
        !identical(oldWidget.comment, widget.comment) ||
        oldWidget.preview != widget.preview ||
        oldWidget.onOpenUser != widget.onOpenUser ||
        oldWidget.onOpenLink != widget.onOpenLink ||
        oldWidget.onSeek != widget.onSeek) {
      _content = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _content = null;
  }

  bool _busy(WidgetRef ref) => ref.watch(
    widget.provider.select(
      (state) =>
          state.busy ||
          state.loading ||
          state.replyLoading ||
          state.uncertain.contains('like:${widget.comment.id}'),
    ),
  );

  void _like() {
    if (ref.read(widget.provider).signedIn) {
      unawaited(ref.read(widget.provider.notifier).toggleLike(widget.comment));
    } else {
      widget.onLogin();
    }
  }

  void _reply() {
    if (!ref.read(widget.provider).signedIn) {
      widget.onLogin();
      return;
    }
    ref.read(widget.provider.notifier).target(widget.comment);
    widget.onReplyFocus();
  }

  void _open() =>
      unawaited(ref.read(widget.provider.notifier).openReplies(widget.comment));

  @override
  Widget build(BuildContext context) => _content ??= _buildContent(context);

  // Only mounted rows retain content. Busy/loading changes rebuild controls,
  // while pagination can reuse the rich text, images and author header.
  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context), c = widget.comment;
    final onOpenUser = widget.onOpenUser;
    final onOpenLink = widget.onOpenLink;
    final onSeek = widget.onSeek;
    final styles = CommentTextStyles(theme);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentAuthorHeader(comment: c, onOpenUser: onOpenUser),
          Padding(
            padding: const EdgeInsets.only(
              left: CommentAuthorHeader.contentIndent,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                CommentRichContent(
                  comment: c,
                  onOpenUser: onOpenUser,
                  onOpenLink: onOpenLink,
                  onSeek: onSeek,
                ),
                if (c.visibility == CommentVisibility.restricted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('暂未公开', style: styles.metadata),
                  ),
                Consumer(
                  builder: (context, ref, _) {
                    final busy = _busy(ref);
                    return CommentActions(
                      comment: c,
                      busy: busy,
                      onLike: _like,
                      onReply: _reply,
                    );
                  },
                ),
                if (widget.preview &&
                    (c.replyCount > 0 || c.replies.isNotEmpty))
                  Consumer(
                    builder: (context, ref, child) => InkWell(
                      onTap: _busy(ref) ? null : _open,
                      borderRadius: BorderRadius.circular(5),
                      child: child,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...c.replies
                              .take(2)
                              .map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 3,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          InkWell(
                                            onTap:
                                                r.authorId?.isValid == true &&
                                                    onOpenUser != null
                                                ? () => onOpenUser(r.authorId!)
                                                : null,
                                            child: Text(
                                              r.isUpAuthor
                                                  ? r.author
                                                  : '${r.author}：',
                                              style: styles.previewAuthor
                                                  .copyWith(
                                                    color:
                                                        r.nicknameColor != null
                                                        ? Color(
                                                            0xFF000000 |
                                                                r.nicknameColor!,
                                                          )
                                                        : null,
                                                  ),
                                            ),
                                          ),
                                          if (r.isUpAuthor)
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const CommentBadge(label: 'UP'),
                                                Text(
                                                  '：',
                                                  style: styles.previewAuthor
                                                      .copyWith(
                                                        color:
                                                            r.nicknameColor !=
                                                                null
                                                            ? Color(
                                                                0xFF000000 |
                                                                    r.nicknameColor!,
                                                              )
                                                            : null,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          if (r.isPinned)
                                            const CommentBadge(
                                              label: '置顶',
                                              outlined: true,
                                            ),
                                        ],
                                      ),
                                      CommentRichContent(
                                        comment: r,
                                        onOpenUser: onOpenUser,
                                        compact: true,
                                        onOpenLink: onOpenLink,
                                        onSeek: onSeek,
                                      ),
                                      if (r.visibility ==
                                          CommentVisibility.restricted)
                                        Text('暂未公开', style: styles.metadata),
                                    ],
                                  ),
                                ),
                              ),
                          Text(
                            '共 ${c.replyCount} 条回复 ›',
                            style: styles.link.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _CommentsSlot { header, list, composer }

/// Reserve the draft before the header/list. A landscape keyboard may leave
/// room only for editing; the reading controls must yield that space first.
class _CommentsLayoutDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final composer = layoutChild(
      _CommentsSlot.composer,
      BoxConstraints.tightFor(width: size.width)
          .copyWith(maxHeight: size.height),
    );
    final available = (size.height - composer.height).clamp(0.0, size.height);
    final header = layoutChild(
      _CommentsSlot.header,
      BoxConstraints.tightFor(width: size.width).copyWith(maxHeight: available),
    );
    positionChild(_CommentsSlot.header, Offset.zero);
    final listHeight = (available - header.height).clamp(0.0, available);
    layoutChild(
      _CommentsSlot.list,
      BoxConstraints.tight(Size(size.width, listHeight)),
    );
    positionChild(_CommentsSlot.list, Offset(0, header.height));
    positionChild(
      _CommentsSlot.composer,
      Offset(0, size.height - composer.height),
    );
  }

  @override
  bool shouldRelayout(_CommentsLayoutDelegate oldDelegate) => false;
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/user.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/user_follow_button.dart';
import '../application/profile_controller.dart';
import '../domain/profile_repository.dart';

final class FollowingDialogLifetime extends ChangeNotifier {
  bool isCancelled = false;
  @override
  void dispose() {
    isCancelled = true;
    notifyListeners();
    super.dispose();
  }
}

/// Dialogs belong to the originating page and account, including confirmation
/// drafts. They cannot outlive a closed workspace page or an account reset.
Future<T?> showFollowingDialog<T>({
  required BuildContext context,
  required UserId id,
  required int generation,
  required FollowingDialogLifetime lifetime,
  required WidgetBuilder builder,
}) => showAppDialog<T>(
  context: context,
  builder: (context) => _DialogLifetime(
    id: id,
    generation: generation,
    lifetime: lifetime,
    builder: builder,
  ),
);

class _DialogLifetime extends ConsumerStatefulWidget {
  const _DialogLifetime({
    required this.id,
    required this.generation,
    required this.lifetime,
    required this.builder,
  });
  final UserId id;
  final int generation;
  final FollowingDialogLifetime lifetime;
  final WidgetBuilder builder;
  @override
  ConsumerState<_DialogLifetime> createState() => _DialogLifetimeState();
}

class _DialogLifetimeState extends ConsumerState<_DialogLifetime> {
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.lifetime.addListener(_close);
  }

  @override
  void dispose() {
    widget.lifetime.removeListener(_close);
    super.dispose();
  }

  void _close() {
    if (!mounted || _closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final generation = ref.watch(
      profileControllerProvider(widget.id)
          .select((state) => state.sessionGeneration),
    );
    if (generation != widget.generation || widget.lifetime.isCancelled) {
      _close();
      return const SizedBox.shrink();
    }
    return widget.builder(context);
  }
}

class ProfileFollowingTools extends ConsumerStatefulWidget {
  const ProfileFollowingTools({super.key, required this.id});
  final UserId id;
  @override
  ConsumerState<ProfileFollowingTools> createState() =>
      _ProfileFollowingToolsState();
}

class _ProfileFollowingToolsState extends ConsumerState<ProfileFollowingTools> {
  late final TextEditingController _search;
  final _lifetime = FollowingDialogLifetime();

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(profileControllerProvider(widget.id)).followingKeyword,
    );
  }

  @override
  void dispose() {
    _lifetime.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) {
    final generation = ref
        .read(profileControllerProvider(widget.id))
        .sessionGeneration;
    return showFollowingDialog<T>(
      context: context,
      id: widget.id,
      generation: generation,
      lifetime: _lifetime,
      builder: builder,
    );
  }

  Future<void> _action(String action) async {
    final provider = profileControllerProvider(widget.id);
    final before = ref.read(provider);
    final controller = ref.read(provider.notifier);
    final selected = before.followGroups
        ?.where((group) => group.id == before.followingGroupId)
        .firstOrNull;
    bool current() =>
        mounted &&
        ref.read(provider).sessionGeneration == before.sessionGeneration;
    switch (action) {
      case 'blacklist':
        controller.showFollowingBlacklist(true);
      case 'create':
      case 'rename':
        if (action == 'rename' && selected?.isEditable != true) return;
        final name = await _dialog<String>(
          (_) => _TextDialog(
            title: action == 'create' ? '新建分组' : '重命名分组',
            label: '分组名称',
            initial: action == 'create' ? '' : selected!.name,
            maxLength: 16,
          ),
        );
        if (name != null && current()) {
          await controller.editFollowGroup(
            action == 'create'
                ? FollowGroupEdit.create
                : FollowGroupEdit.rename,
            groupId: selected?.id,
            name: name,
          );
        }
      case 'delete':
        if (selected?.isEditable != true) return;
        final confirmed = await _dialog<bool>(
          (context) => AlertDialog(
            title: const Text('删除分组'),
            content: Text('删除“${selected!.name}”？分组中的关注关系会保留。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed == true && current()) {
          await controller.editFollowGroup(
            FollowGroupEdit.delete,
            groupId: selected!.id,
          );
        }
      case 'sort':
        final groups =
            before.followGroups?.where((group) => group.isEditable).toList() ??
            [];
        if (groups.length < 2) return;
        final ids = await _dialog<List<String>>(
          (_) => _SortDialog(groups: groups),
        );
        if (ids != null && current()) await controller.sortFollowGroups(ids);
      case 'addBlocked':
        final value = await _dialog<String>(
          (_) => const _TextDialog(
            title: '加入黑名单',
            label: '用户 UID',
            numeric: true,
            maxLength: 20,
          ),
        );
        if (value != null && current()) {
          await controller.setFollowingBlocked(UserId(value), true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final (
      available,
      keyword,
      order,
      blacklist,
      busy,
      uncertain,
      message,
      selectedId,
      groups,
    ) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.followingManagementAvailable,
          state.followingKeyword,
          state.followingOrder,
          state.showBlacklist,
          state.followingBusy,
          state.followingUncertain,
          state.followingMessage,
          state.followingGroupId,
          state.followGroups,
        ),
      ),
    );
    if (!available) return const SizedBox.shrink();
    final controller = ref.read(profileControllerProvider(widget.id).notifier);
    final editable =
        groups?.any((group) => group.id == selectedId && group.isEditable) ==
        true;
    ref.listen(
      profileControllerProvider(widget.id)
          .select((state) => state.followingKeyword),
      (_, value) {
        if (_search.text != value) _search.text = value;
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (blacklist) ...[
              IconButton(
                tooltip: '返回关注',
                onPressed: () => controller.showFollowingBlacklist(false),
                icon: const Icon(Icons.arrow_back),
              ),
              const Expanded(child: Text('黑名单管理')),
            ] else
              Expanded(
                child: TextField(
                  key: const ValueKey('profile-following-search'),
                  controller: _search,
                  maxLength: 100,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: '搜索全部关注',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      tooltip: keyword.isEmpty ? '搜索关注' : '清除搜索',
                      onPressed: () {
                        if (keyword.isNotEmpty) _search.clear();
                        controller.searchFollowing(_search.text);
                      },
                      icon: Icon(
                        keyword.isEmpty ? Icons.arrow_forward : Icons.close,
                        size: 18,
                      ),
                    ),
                  ),
                  onSubmitted: controller.searchFollowing,
                ),
              ),
            const SizedBox(width: 4),
            if (!blacklist)
              PopupMenuButton<String>(
                tooltip: '关注排序',
                icon: const Icon(Icons.sort),
                initialValue: order,
                onSelected: controller.orderFollowing,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: '', child: Text('最近关注')),
                  PopupMenuItem(value: 'attention', child: Text('最常访问')),
                ],
              ),
            PopupMenuButton<String>(
              tooltip: '关注管理',
              enabled: !busy && !uncertain,
              onSelected: _action,
              itemBuilder: (_) => [
                if (blacklist)
                  const PopupMenuItem(value: 'addBlocked', child: Text('加入黑名单'))
                else ...[
                  const PopupMenuItem(value: 'create', child: Text('新建分组')),
                  PopupMenuItem(
                    value: 'rename',
                    enabled: editable,
                    child: const Text('重命名分组'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: editable,
                    child: const Text('删除分组'),
                  ),
                  PopupMenuItem(
                    value: 'sort',
                    enabled:
                        (groups?.where((group) => group.isEditable).length ??
                            0) >
                        1,
                    child: const Text('分组排序'),
                  ),
                  const PopupMenuItem(value: 'blacklist', child: Text('黑名单管理')),
                ],
              ],
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (keyword.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('全部关注的搜索结果'),
          ),
        if (message != null || uncertain)
          TextButton.icon(
            onPressed: busy ? null : controller.refreshFollowingManagement,
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(message ?? '刷新关注管理状态'),
          ),
      ],
    );
  }
}

Future<void> manageProfileUser({
  required BuildContext context,
  required WidgetRef ref,
  required UserId owner,
  required ProfileEntry entry,
  required FollowingDialogLifetime lifetime,
}) async {
  final target = entry.userId;
  if (target == null || !target.isValid) return;
  final provider = profileControllerProvider(owner);
  final before = ref.read(provider);
  if (before.followingBusy || before.followingUncertain) return;
  final action = await showFollowingDialog<String>(
    context: context,
    id: owner,
    generation: before.sessionGeneration,
    lifetime: lifetime,
    builder: (context) => SimpleDialog(
      title: Text(entry.title),
      children: [
        if (!before.showBlacklist)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'follow'),
            child: const Text('关注与分组设置'),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'block'),
          child: Text(before.showBlacklist ? '移出黑名单' : '加入黑名单'),
        ),
      ],
    ),
  );
  bool current() =>
      context.mounted &&
      !lifetime.isCancelled &&
      ref.read(provider).sessionGeneration == before.sessionGeneration;
  if (!context.mounted || action == null || !current()) return;
  if (action == 'follow') {
    await showFollowingDialog<void>(
      context: context,
      id: owner,
      generation: before.sessionGeneration,
      lifetime: lifetime,
      builder: (context) => AlertDialog(
        title: Text(entry.title),
        content: UserFollowButton(
          id: target,
          openGroupsDialog: (builder) async {
            await showFollowingDialog<void>(
              context: context,
              id: owner,
              generation: before.sessionGeneration,
              lifetime: lifetime,
              builder: builder,
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    if (current()) {
      await ref.read(provider.notifier).refreshFollowingManagement();
    }
  } else {
    final confirmed = await showFollowingDialog<bool>(
      context: context,
      id: owner,
      generation: before.sessionGeneration,
      lifetime: lifetime,
      builder: (context) => AlertDialog(
        title: Text(before.showBlacklist ? '移出黑名单' : '加入黑名单'),
        content: Text('确认${before.showBlacklist ? '将该用户移出' : '将该用户加入'}黑名单？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true && current()) {
      await ref
          .read(provider.notifier)
          .setFollowingBlocked(target, !before.showBlacklist);
    }
  }
}

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.maxLength,
    this.initial = '',
    this.numeric = false,
  });
  final String title, label, initial;
  final int maxLength;
  final bool numeric;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();
  void _submit() {
    if (_form.currentState?.validate() == true) {
      Navigator.pop(context, _text.text.trim());
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _text,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(labelText: widget.label),
        keyboardType: widget.numeric
            ? TextInputType.number
            : TextInputType.text,
        validator: (value) => value == null || value.trim().isEmpty
            ? '请输入${widget.label}'
            : value.trim().runes.length > widget.maxLength
            ? '最多 ${widget.maxLength} 个字符'
            : widget.numeric && !RegExp(r'^[1-9]\d*$').hasMatch(value.trim())
            ? '请输入有效 UID'
            : null,
        onFieldSubmitted: (_) => _submit(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确认')),
    ],
  );
}

class _SortDialog extends StatefulWidget {
  const _SortDialog({required this.groups});
  final List<ProfileFollowGroup> groups;
  @override
  State<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<_SortDialog> {
  late final _groups = [...widget.groups];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('分组排序'),
    content: SizedBox(
      width: 320,
      height: 300,
      child: ReorderableListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, index) => ListTile(
          key: ValueKey(_groups[index].id),
          title: Text(_groups[index].name),
        ),
        onReorderItem: (oldIndex, newIndex) => setState(() {
          final group = _groups.removeAt(oldIndex);
          _groups.insert(newIndex, group);
        }),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, _groups.map((group) => group.id).toList()),
        child: const Text('保存'),
      ),
    ],
  );
}

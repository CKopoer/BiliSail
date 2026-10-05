import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/favorite_folder_controller.dart';
import '../domain/favorite_folder_repository.dart';

final class FavoriteFolderEditDialog extends ConsumerStatefulWidget {
  const FavoriteFolderEditDialog({super.key, required this.target});
  final FavoriteFolderTarget target;
  @override
  ConsumerState<FavoriteFolderEditDialog> createState() =>
      _FavoriteFolderEditDialogState();
}

final class _FavoriteFolderEditDialogState
    extends ConsumerState<FavoriteFolderEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _intro = TextEditingController();
  FavoriteFolderInfo? _loaded;
  bool _isPrivate = false;

  @override
  void dispose() {
    _title.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final saved = await ref
        .read(favoriteFolderControllerProvider(widget.target).notifier)
        .save(
          FavoriteFolderEdit(
            title: _title.text,
            intro: _intro.text,
            isPrivate: _isPrivate,
          ),
        );
    if (mounted && saved) Navigator.of(context).pop(true);
  }

  Future<void> _refresh() async {
    final confirmed = await ref
        .read(favoriteFolderControllerProvider(widget.target).notifier)
        .refresh();
    if (!mounted) return;
    if (confirmed) {
      Navigator.of(context).pop(true);
    } else {
      final state = ref.read(favoriteFolderControllerProvider(widget.target));
      if (state.active && !state.uncertain && state.info != null) {
        // A repository may reuse an unchanged immutable snapshot. An explicit
        // reconciliation still replaces the draft with the server values.
        setState(() => _loaded = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(favoriteFolderControllerProvider(widget.target));
    if (!identical(_loaded, state.info)) {
      _loaded = state.info;
      _title.text = state.info?.title ?? '';
      _intro.text = state.info?.intro ?? '';
      _isPrivate = state.info?.isPrivate ?? false;
    }
    final enabled =
        state.active &&
        state.info != null &&
        !state.loading &&
        !state.busy &&
        !state.uncertain;
    return PopScope(
      canPop: !state.busy,
      child: AlertDialog(
        title: const Text('编辑收藏夹'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.loading) const LinearProgressIndicator(),
                if (state.info != null) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _title,
                    enabled: enabled,
                    decoration: const InputDecoration(labelText: '收藏夹名称'),
                    validator: (value) =>
                        value?.trim().isNotEmpty == true ? null : '请输入收藏夹名称',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _intro,
                    enabled: enabled,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '简介（可选）'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('私密收藏夹'),
                    subtitle: Text(_isPrivate ? '仅自己可见' : '公开，所有人可见'),
                    value: _isPrivate,
                    onChanged: enabled
                        ? (value) => setState(() => _isPrivate = value)
                        : null,
                  ),
                ],
                if (state.message case final message?) ...[
                  const SizedBox(height: 12),
                  Text(message),
                ],
                if (state.active &&
                    !state.loading &&
                    !state.busy &&
                    (state.info == null || state.uncertain))
                  TextButton(onPressed: _refresh, child: const Text('重新读取')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: state.busy
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: enabled ? _save : null,
            child: Text(state.busy ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../features/comments/domain/comment_composer.dart';
import 'network_avatar.dart';

class CommentMentionDialog extends StatefulWidget {
  const CommentMentionDialog({super.key, required this.search});
  final Future<List<CommentMention>> Function(String, RequestCancellation)
  search;

  @override
  State<CommentMentionDialog> createState() => _CommentMentionDialogState();
}

class _CommentMentionDialogState extends State<CommentMentionDialog> {
  final _text = TextEditingController();
  Timer? _timer;
  RequestCancellation? _request;
  List<CommentMention> _users = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _request?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _timer?.cancel();
    _request?.cancel();
    setState(() {
      _loading = true;
      _users = const [];
      _error = null;
    });
    _timer = Timer(const Duration(milliseconds: 300), _search);
  }

  Future<void> _search() async {
    _request?.cancel();
    final request = _request = RequestCancellation();
    try {
      final users = await widget.search(_text.text, request);
      if (!mounted || request.isCancelled) return;
      setState(() {
        _users = users;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || request.isCancelled) return;
      setState(() {
        _loading = false;
        _error = error is AppFailure ? error.message : '暂时无法搜索用户';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '@用户',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭用户选择',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            TextField(
              controller: _text,
              autofocus: true,
              maxLength: 50,
              onChanged: _changed,
              decoration: const InputDecoration(
                hintText: '搜索用户名',
                prefixIcon: Icon(Icons.search),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() => _loading = true);
                          unawaited(_search());
                        },
                        child: Text('$_error，点击重试'),
                      ),
                    )
                  : _users.isEmpty
                  ? const Center(child: Text('没有找到用户，试试搜索用户名'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return ListTile(
                          leading: NetworkAvatar(
                            url: user.avatarUrl,
                            name: user.name,
                            radius: 18,
                          ),
                          title: Text(user.name),
                          onTap: () => Navigator.pop(context, user),
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

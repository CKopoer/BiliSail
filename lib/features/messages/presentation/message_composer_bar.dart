import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/emoticon_picker_dialog.dart';
import '../../auth/application/auth_controller.dart';
import '../application/message_image_picker.dart';
import '../application/messages_controller.dart';
import '../domain/message_composer.dart';
import 'private_message_image.dart';

class MessageComposerBar extends ConsumerStatefulWidget {
  const MessageComposerBar({
    super.key,
    required this.text,
    required this.onChanged,
    required this.onSend,
    required this.busy,
    this.image,
    required this.onImageChanged,
    required this.onSendImage,
  });
  final TextEditingController text;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSend;
  final bool busy;
  final MessageLocalImage? image;
  final ValueChanged<MessageLocalImage?> onImageChanged;
  final Future<bool> Function(MessageLocalImage) onSendImage;

  @override
  ConsumerState<MessageComposerBar> createState() => _MessageComposerBarState();
}

class _MessageComposerBarState extends ConsumerState<MessageComposerBar> {
  bool _picking = false;

  (String?, String, int, String?) _account() {
    final repository = ref.read(messageRepositoryProvider);
    return (
      ref.read(authControllerProvider).mid,
      repository.accountScope,
      repository.sessionEpoch,
      ref.read(messagesControllerProvider).selected?.id,
    );
  }

  bool _current((String?, String, int, String?) account) =>
      mounted && _account() == account;

  Future<void> _pickImage() async {
    if (_picking || widget.busy) return;
    final account = _account();
    setState(() => _picking = true);
    try {
      final image = await ref.read(messageImagePickerProvider)();
      if (_current(account) && image != null) widget.onImageChanged(image);
    } catch (error) {
      if (mounted && _current(account)) {
        showAppNotice(
          context,
          error is AppFailure ? error.message : '无法读取图片，请重新选择',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _emotes() async {
    final account = _account();
    unawaited(ref.read(messagesControllerProvider.notifier).loadEmotes());
    final emote = await showAppDialog<MessageEmote>(
      context: context,
      builder: (_) => const _MessageEmoteDialog(),
    );
    if (!mounted || emote == null || !_current(account)) return;
    final value = widget.text.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, emote.text);
    if (text.runes.length > 1000) {
      showAppNotice(context, '私信最多输入 1000 个字符');
      return;
    }
    widget.text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + emote.text.length),
    );
    widget.onChanged(text);
  }

  Future<void> _sendImage() async {
    final image = widget.image;
    if (image == null || widget.busy) return;
    final account = _account();
    final sent = await widget.onSendImage(image);
    if (sent && _current(account) && identical(image, widget.image)) {
      widget.onImageChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rich = ref.watch(
      messagesControllerProvider.select(
        (state) => state.supportsRichComposition,
      ),
    );
    final busy = widget.busy || _picking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rich)
            Row(
              children: [
                IconButton(
                  tooltip: '私信表情',
                  onPressed: busy ? null : _emotes,
                  icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                ),
                IconButton(
                  tooltip: '选择私信图片',
                  onPressed: busy ? null : _pickImage,
                  icon: const Icon(Icons.image_outlined),
                ),
                if (_picking)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          if (widget.image case final image?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _ImageDraft(image: image),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '图片将单独发送',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => widget.onImageChanged(null),
                              child: const Text('移除图片'),
                            ),
                            FilledButton(
                              onPressed: busy ? null : _sendImage,
                              child: const Text('发送图片'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 1000,
                  onChanged: widget.onChanged,
                  decoration: const InputDecoration(
                    hintText: '输入私信消息',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : widget.onSend,
                child: Text(widget.busy ? '发送中' : '发送'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImageDraft extends StatefulWidget {
  const _ImageDraft({required this.image});
  final MessageLocalImage image;
  @override
  State<_ImageDraft> createState() => _ImageDraftState();
}

class _ImageDraftState extends State<_ImageDraft> {
  late ImageProvider<Object> _provider = ResizeImage(
    MemoryImage(widget.image.bytes),
    width: 240,
    height: 240,
    policy: ResizeImagePolicy.fit,
  );
  @override
  void didUpdateWidget(_ImageDraft oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) {
      _provider.evict();
      _provider = ResizeImage(
        MemoryImage(widget.image.bytes),
        width: 240,
        height: 240,
        policy: ResizeImagePolicy.fit,
      );
    }
  }

  @override
  void dispose() {
    _provider.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image(
      image: _provider,
      width: 84,
      height: 76,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const SizedBox(
        width: 84,
        height: 76,
        child: Center(child: Text('无法预览')),
      ),
    ),
  );
}

class _MessageEmoteDialog extends ConsumerWidget {
  const _MessageEmoteDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      messagesControllerProvider.select(
        (state) => (
          state.emotePackages,
          state.emotesLoading,
          state.emotesMessage,
          state.sending,
        ),
      ),
    );
    return EmoticonPickerDialog(
      title: '私信表情',
      loading: state.$2,
      message: state.$3,
      emptyMessage: '暂无可用私信表情',
      onRetry: ref.read(messagesControllerProvider.notifier).loadEmotes,
      packageNames: [for (final package in state.$1) package.name],
      packageBuilder: (context, packageIndex) {
        final items = state.$1[packageIndex].items;
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 72,
            mainAxisExtent: 60,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final emote = items[index];
            return Tooltip(
              message: emote.text,
              child: TextButton(
                onPressed: state.$4
                    ? null
                    : () => Navigator.pop(context, emote),
                child: emote.imageUrl == null
                    ? Text(emote.text)
                    : PrivateMessageImage(
                        url: emote.imageUrl!,
                        compact: true,
                        preview: false,
                        fallbackText: emote.text,
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/user_follow_button.dart';

/// Credits come from video detail; relationships use the shared account scope.
final class VideoStaffPanel extends StatefulWidget {
  const VideoStaffPanel({
    super.key,
    required this.members,
    this.onLogin,
    this.onOpenUser,
  });

  final List<VideoStaffMember> members;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;

  @override
  State<VideoStaffPanel> createState() => _VideoStaffPanelState();
}

final class _VideoStaffPanelState extends State<VideoStaffPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.members.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final minWidth = math.max(
          64.0,
          MediaQuery.textScalerOf(context).scale(48) + 16,
        );
        final columns = math.max(
          1,
          ((constraints.maxWidth + gap) / (minWidth + gap)).floor(),
        );
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        final canExpand = widget.members.length > columns;
        final visible = _expanded
            ? widget.members
            : widget.members.take(columns);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: const ValueKey('video-staff-toggle'),
              onTap: canExpand
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text('创作团队', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.members.length}人',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (canExpand)
                      Tooltip(
                        message: _expanded ? '收起创作团队' : '展开创作团队',
                        child: Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: gap,
              runSpacing: 10,
              children: [
                for (final (index, member) in visible.indexed)
                  SizedBox(
                    key: ValueKey(
                      'video-staff-$index-${member.id?.value ?? ''}',
                    ),
                    width: width,
                    child: _StaffMember(
                      member: member,
                      onLogin: widget.onLogin,
                      onOpenUser: widget.onOpenUser,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

final class _StaffMember extends StatelessWidget {
  const _StaffMember({required this.member, this.onLogin, this.onOpenUser});

  final VideoStaffMember member;
  final VoidCallback? onLogin;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context) {
    final id = member.id;
    final theme = Theme.of(context);
    final color =
        _nicknameColor(member.nicknameColor) ?? theme.colorScheme.onSurface;
    final onOpen = id?.isValid == true && onOpenUser != null
        ? () => onOpenUser!(id!)
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: 5,
                child: InkWell(
                  onTap: onOpen,
                  customBorder: const CircleBorder(),
                  child: NetworkAvatar(
                    url: member.avatarUrl,
                    name: member.name,
                    radius: 22,
                  ),
                ),
              ),
              if (member.title.isNotEmpty)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Tooltip(
                      message: member.title,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: member.highlightedRole
                              ? const Color(0xffffe0a3)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          member.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: member.highlightedRole
                                ? const Color(0xff805200)
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (id?.isValid == true)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: UserFollowButton(
                    id: id!,
                    onLogin: onLogin,
                    compact: true,
                    iconOnly: true,
                    showMessage: false,
                  ),
                ),
            ],
          ),
        ),
        Tooltip(
          message: member.name,
          child: InkWell(
            onTap: onOpen,
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ),
      ],
    );
  }

  static Color? _nicknameColor(String? value) {
    if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    final rgb = int.tryParse(value.substring(1), radix: 16);
    return rgb == null || rgb == 0 ? null : Color(0xff000000 | rgb);
  }
}

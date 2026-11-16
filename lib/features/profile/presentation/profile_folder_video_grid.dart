import 'package:material_ui/material_ui.dart';

import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/video_card.dart';
import '../domain/profile_repository.dart';

/// Folder contents share the regular video cards and their natural row heights.
final class ProfileFolderVideoGrid extends StatefulWidget {
  const ProfileFolderVideoGrid({
    super.key,
    required this.entries,
    this.onOpenVideo,
    this.onOpenUser,
  });

  final List<ProfileEntry> entries;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<UserId>? onOpenUser;

  @override
  State<ProfileFolderVideoGrid> createState() => _ProfileFolderVideoGridState();
}

final class _ProfileFolderVideoGridState extends State<ProfileFolderVideoGrid> {
  Widget? _grid;

  @override
  void didUpdateWidget(ProfileFolderVideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.entries, widget.entries) ||
        oldWidget.onOpenVideo != widget.onOpenVideo ||
        oldWidget.onOpenUser != widget.onOpenUser) {
      _grid = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pagination/profile status does not change the cards. Reuse the sliver so
    // those updates cannot replace its row delegate. Its own layout builder
    // handles width and text scaling, without an outer per-scroll builder.
    return _grid ??= SliverResponsiveCardGrid(
      itemCount: widget.entries.length,
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        if (entry.video case final video?) {
          return VideoCard(
            key: ValueKey(entry.id),
            video: video,
            onTap: () => widget.onOpenVideo?.call(video),
            onOpenUser: widget.onOpenUser,
          );
        }
        return Card(
          key: ValueKey(entry.id),
          child: ListTile(
            leading: const Icon(Icons.play_disabled),
            title: Text(entry.title),
            subtitle: Text(
              entry.subtitle.isEmpty ? '该收藏内容不可播放' : entry.subtitle,
            ),
          ),
        );
      },
    );
  }
}

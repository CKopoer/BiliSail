import 'package:material_ui/material_ui.dart';

import 'network_avatar.dart';
import 'workspace_link.dart';

class PostAuthorHeader extends StatelessWidget {
  const PostAuthorHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.fallbackName,
    this.avatarUrl,
    this.pendantUrl,
    this.avatarRadius = 20,
    this.onOpenAuthor,
  });

  final String name, subtitle;
  final String? fallbackName;
  final Uri? avatarUrl, pendantUrl;
  final double avatarRadius;
  final VoidCallback? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = name.isEmpty ? fallbackName : name;
    return InkWell(
      onTap: onOpenAuthor,
      onTertiaryTapUp: WorkspaceLinkScope.middleClick(context, onOpenAuthor),
      child: Row(
        children: [
          NetworkAvatar(
            url: avatarUrl,
            pendantUrl: pendantUrl,
            name: name,
            radius: avatarRadius,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null)
                  Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(height: 1.25),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

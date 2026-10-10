import 'package:flutter/material.dart';

import '../../domain/video_access.dart';

class VideoAccessBadge extends StatelessWidget {
  const VideoAccessBadge({super.key, required this.access});

  final VideoAccess access;

  @override
  Widget build(BuildContext context) {
    final label = access.label;
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xDD9D4E08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontSize: 11, color: Colors.white, height: 1.2),
      ),
    );
  }
}

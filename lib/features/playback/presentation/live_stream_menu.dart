import 'dart:async';

import 'package:flutter/material.dart';

import '../application/playback_session.dart';
import '../domain/playback_repository.dart';
import 'live_stream_picker.dart';

String liveQualityLabel(PlaybackSession session, PlaybackMedia media) =>
    session.requestedQuality == 0
    ? '自动'
    : media.qualityLabels[media.quality] ?? '${media.quality}';

/// Both inline and fullscreen controls use the same live selection menu.
class LiveStreamMenuButton extends StatelessWidget {
  const LiveStreamMenuButton({
    super.key,
    required this.session,
    required this.media,
    required this.onMenuChanged,
  });

  final PlaybackSession session;
  final PlaybackMedia media;
  final ValueChanged<bool> onMenuChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '直播清晰度与线路',
      child: TextButton(
        onPressed: () => unawaited(
          showLiveStreamPicker(
            context,
            session: session,
            media: media,
            onMenuChanged: onMenuChanged,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Text(
              liveQualityLabel(session, media),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

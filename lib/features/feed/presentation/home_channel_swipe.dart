import 'package:flutter/material.dart';

import '../../../shared/ui/retained_tab_view.dart';
import '../domain/home_channel.dart';

typedef HomeChannelPageBuilder = RetainedTabPageBuilder<HomeChannel>;

/// Native tab paging keeps the outgoing and incoming pages on screen together.
final class HomeChannelSwipe extends StatelessWidget {
  const HomeChannelSwipe({
    super.key,
    required this.channel,
    required this.onChanged,
    required this.pageBuilder,
  });

  final HomeChannel channel;
  final ValueChanged<HomeChannel> onChanged;
  final HomeChannelPageBuilder pageBuilder;

  @override
  Widget build(BuildContext context) => RetainedTabView<HomeChannel>(
    tabs: HomeChannel.values,
    value: channel,
    onChanged: onChanged,
    pageBuilder: pageBuilder,
    viewKey: const ValueKey('home-channel-swipe'),
  );
}

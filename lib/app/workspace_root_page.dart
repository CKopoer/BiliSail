import 'package:flutter/widgets.dart';

import '../core/presentation/workspace_activity.dart';
import '../shared/ui/retained_page_layout.dart';

enum WorkspaceRootSection {
  feed('/'),
  account('/me'),
  history('/history'),
  messages('/messages'),
  downloads('/downloads'),
  settings('/settings');

  const WorkspaceRootSection(this.path);
  final String path;

  static WorkspaceRootSection fromLocation(Uri location) => values.firstWhere(
    (section) => section.path == location.path,
    orElse: () => feed,
  );
}

typedef WorkspaceRootBuilder = Widget Function(
  BuildContext context,
  Uri location,
);

/// Primary navigation changes selection while each visited root keeps its tree.
class WorkspaceRootPage extends StatefulWidget {
  const WorkspaceRootPage({
    super.key,
    required this.location,
    required this.feedBuilder,
    required this.accountBuilder,
    required this.historyBuilder,
    required this.messagesBuilder,
    required this.downloadsBuilder,
    required this.settingsBuilder,
  });

  final Uri location;
  final WorkspaceRootBuilder feedBuilder;
  final WorkspaceRootBuilder accountBuilder;
  final WorkspaceRootBuilder historyBuilder;
  final WorkspaceRootBuilder messagesBuilder;
  final WorkspaceRootBuilder downloadsBuilder;
  final WorkspaceRootBuilder settingsBuilder;

  @override
  State<WorkspaceRootPage> createState() => _WorkspaceRootPageState();
}

class _WorkspaceRootPageState extends State<WorkspaceRootPage> {
  final _storage = <WorkspaceRootSection, PageStorageBucket>{};
  final _roots = <WorkspaceRootSection, Widget>{};

  WorkspaceRootSection get _selected =>
      WorkspaceRootSection.fromLocation(widget.location);

  Widget _buildRoot(
    BuildContext context,
    WorkspaceRootSection section,
    Uri location,
  ) => switch (section) {
    WorkspaceRootSection.feed => widget.feedBuilder(context, location),
    WorkspaceRootSection.account => widget.accountBuilder(context, location),
    WorkspaceRootSection.history => widget.historyBuilder(context, location),
    WorkspaceRootSection.messages => widget.messagesBuilder(context, location),
    WorkspaceRootSection.downloads => widget.downloadsBuilder(
      context,
      location,
    ),
    WorkspaceRootSection.settings => widget.settingsBuilder(context, location),
  };

  Widget _retained({
    required Key key,
    required bool selected,
    required PageStorageBucket storage,
    required Widget child,
  }) => Offstage(
    key: key,
    offstage: !selected,
    child: ExcludeFocus(
      excluding: !selected,
      child: WorkspaceActivity(
        active: selected && WorkspaceActivity.isActive(context),
        previewing:
            selected &&
            WorkspaceActivity.isVisible(context) &&
            !WorkspaceActivity.isActive(context),
        child: RetainedPageLayout(
          visible: selected && WorkspaceActivity.isVisible(context),
          child: PageStorage(bucket: storage, child: child),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final location = widget.location;
    // Only the selected branch receives new route/configuration callbacks.
    // Other branches still react to inherited state and account providers, but
    // unrelated navigation does not rebuild all their feature trees.
    _roots[selected] = Builder(
      builder: (context) => _buildRoot(context, selected, location),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final section in WorkspaceRootSection.values)
          if (_roots[section] case final root?)
            _retained(
              key: ValueKey('workspace-root-${section.name}'),
              selected: _selected == section,
              storage: _storage.putIfAbsent(section, PageStorageBucket.new),
              child: root,
            ),
      ],
    );
  }
}

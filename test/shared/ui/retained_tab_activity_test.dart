import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/retained_tab_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('activity gates a retained page without rebuilding its content', (
    tester,
  ) async {
    final activity = ValueNotifier(true);
    addTearDown(activity.dispose);
    var contentBuilds = 0;
    var pageBuilds = 0;
    final visible = <bool>[];
    final pager = RetainedTabView<int>(
      tabs: const [0, 1],
      value: 0,
      onChanged: (_) {},
      pageBuilder: (context, tab, active) {
        pageBuilds++;
        return Column(
          children: [
            Builder(
              builder: (context) {
                contentBuilds++;
                return const Text('retained content');
              },
            ),
            Builder(
              builder: (context) {
                visible.add(WorkspaceActivity.isActive(context));
                return const TextField();
              },
            ),
          ],
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: activity,
          child: pager,
          builder: (context, active, child) => WorkspaceActivity(
            active: active,
            child: ExcludeFocus(
              excluding: !active,
              child: Scaffold(body: child),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留草稿');
    await tester.pumpAndSettle();
    final element = tester.element(find.text('retained content'));
    final pagesBefore = pageBuilds;
    final contentBefore = contentBuilds;
    activity.value = false;
    await tester.pumpAndSettle();
    expect(visible.last, isFalse);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    activity.value = true;
    await tester.pumpAndSettle();
    expect(visible.last, isTrue);
    expect(pageBuilds, pagesBefore);
    expect(contentBuilds, contentBefore);
    expect(tester.element(find.text('retained content')), same(element));
    expect(find.text('保留草稿'), findsOneWidget);
  });

  testWidgets('parent configuration and inherited data still update content', (
    tester,
  ) async {
    final host = GlobalKey<_HostState>();
    await tester.pumpWidget(MaterialApp(home: _Host(key: host)));
    await tester.pumpAndSettle();
    expect(find.text('0:0:true:1.0'), findsOneWidget);
    host.currentState!.update(label: 1);
    await tester.pumpAndSettle();
    expect(find.text('1:0:true:1.0'), findsOneWidget);
    host.currentState!.update(scale: 2);
    await tester.pumpAndSettle();
    expect(find.text('1:0:true:2.0'), findsOneWidget);
    host.currentState!.update(selection: 1);
    await tester.pumpAndSettle();
    expect(find.text('1:1:true:2.0'), findsOneWidget);
    host.currentState!.update(selection: 0);
    await tester.pumpAndSettle();
    expect(find.text('1:0:true:2.0'), findsOneWidget);
  });
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int _label = 0;
  int _selection = 0;
  double _scale = 1;
  void update({int? label, int? selection, double? scale}) => setState(() {
    _label = label ?? _label;
    _selection = selection ?? _selection;
    _scale = scale ?? _scale;
  });
  // This tear-off stays equal even when its captured State configuration changes.
  Widget _page(BuildContext context, int tab, bool active) =>
      Text('$_label:$tab:$active:${MediaQuery.textScalerOf(context).scale(1)}');
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(_scale)),
    child: Scaffold(
      body: RetainedTabView<int>(
        tabs: const [0, 1],
        value: _selection,
        pageBuilder: _page,
        onChanged: (selection) => update(selection: selection),
      ),
    ),
  );
}

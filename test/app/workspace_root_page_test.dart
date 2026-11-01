import 'package:bilisail/app/workspace_root_page.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _revision = NotifierProvider<_Revision, int>(_Revision.new);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

void main() {
  final locations = {
    WorkspaceRootSection.feed: Uri.parse('/?channel=popular&section=每周必看'),
    WorkspaceRootSection.account: Uri.parse('/me?section=favorites'),
    WorkspaceRootSection.history: Uri.parse('/history'),
    WorkspaceRootSection.messages: Uri.parse('/messages?talker=2'),
    WorkspaceRootSection.downloads: Uri.parse('/downloads'),
    WorkspaceRootSection.settings: Uri.parse('/settings?section=playback'),
  };
  for (final initial in WorkspaceRootSection.values) {
    testWidgets('root lazily retains six branches when starting at $initial', (
      tester,
    ) async {
      final selection = ValueNotifier(locations[initial]!);
      final visible = ValueNotifier(true);
      final builds = <WorkspaceRootSection, int>{};
      addTearDown(selection.dispose);
      addTearDown(visible.dispose);
      Widget probe(WorkspaceRootSection section, Uri location) {
        builds.update(section, (value) => value + 1, ifAbsent: () => 1);
        return _Probe(key: ValueKey(section), uri: location);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: visible,
            builder: (context, active, _) => WorkspaceActivity(
              active: active,
              child: ValueListenableBuilder(
                valueListenable: selection,
                builder: (context, location, _) => WorkspaceRootPage(
                  location: location,
                  feedBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.feed, uri),
                  accountBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.account, uri),
                  historyBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.history, uri),
                  messagesBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.messages, uri),
                  downloadsBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.downloads, uri),
                  settingsBuilder: (_, uri) =>
                      probe(WorkspaceRootSection.settings, uri),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(_Probe, skipOffstage: false), findsOneWidget);
      final states = <WorkspaceRootSection, _ProbeState>{
        initial: tester.state<_ProbeState>(find.byType(_Probe)),
      };
      final buckets = <WorkspaceRootSection, PageStorageBucket>{};
      for (final section in [
        ...WorkspaceRootSection.values,
        ...WorkspaceRootSection.values.reversed,
      ]) {
        final previousBuilds = Map.of(builds);
        selection.value = locations[section]!;
        await tester.pump();
        final state = tester.state<_ProbeState>(find.byType(_Probe));
        if (states[section] case final old?) {
          expect(state, same(old));
        } else {
          states[section] = state;
        }
        if (buckets[section] case final old?) {
          expect(PageStorage.of(state.context), same(old));
        } else {
          buckets[section] = PageStorage.of(state.context);
        }
        state.value = section.index + 7;
        for (final entry in states.entries) {
          if (entry.key != section) {
            expect(builds[entry.key], previousBuilds[entry.key]);
          }
          expect(
            WorkspaceActivity.isActive(entry.value.context),
            entry.key == section,
          );
          expect(entry.value.widget.uri, locations[entry.key]);
        }
      }
      expect(
        find.byType(_Probe, skipOffstage: false),
        findsNWidgets(WorkspaceRootSection.values.length),
      );
      expect(
        buckets.values.toSet(),
        hasLength(WorkspaceRootSection.values.length),
      );
      visible.value = false;
      await tester.pump();
      for (final state in states.values) {
        expect(WorkspaceActivity.isActive(state.context), isFalse);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('hidden branches still receive provider updates', (tester) async {
    final location = ValueNotifier(Uri(path: '/'));
    addTearDown(location.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: location,
            builder: (context, uri, _) => WorkspaceRootPage(
              location: uri,
              feedBuilder: (_, _) => Consumer(
                builder: (_, ref, _) =>
                    Text('account epoch ${ref.watch(_revision)}'),
              ),
              accountBuilder: (_, _) => const Text('account'),
              historyBuilder: (_, _) => const SizedBox(),
              messagesBuilder: (_, _) => const SizedBox(),
              downloadsBuilder: (_, _) => const SizedBox(),
              settingsBuilder: (_, _) => const SizedBox(),
            ),
          ),
        ),
      ),
    );
    location.value = Uri(path: '/me');
    await tester.pump();
    ProviderScope.containerOf(tester.element(find.byType(WorkspaceRootPage)))
        .read(_revision.notifier)
        .increment();
    await tester.pump();
    expect(find.text('account epoch 1', skipOffstage: false), findsOneWidget);
    location.value = Uri(path: '/');
    await tester.pump();
    expect(find.text('account epoch 1'), findsOneWidget);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.uri});
  final Uri uri;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int value = 0;

  @override
  Widget build(BuildContext context) =>
      Text('${widget.uri}: ${WorkspaceActivity.isActive(context)}');
}

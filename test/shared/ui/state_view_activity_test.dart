import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/shared/ui/state_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _revision = NotifierProvider<_Revision, int>(_Revision.new);

class _Revision extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state++;
}

void main() {
  testWidgets(
    'hidden loading stops animating while provider updates continue',
    (tester) async {
      final activity = ValueNotifier((active: true, previewing: false));
      addTearDown(activity.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ValueListenableBuilder(
              valueListenable: activity,
              builder: (_, value, child) => WorkspaceActivity(
                active: value.active,
                previewing: value.previewing,
                child: child!,
              ),
              child: Consumer(
                builder: (_, ref, _) => Column(
                  children: [
                    const StateView.loading(),
                    Text('account epoch ${ref.watch(_revision)}'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      final indicator = tester.element(find.byType(CircularProgressIndicator));
      activity.value = (active: false, previewing: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, 0);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StateView)),
      );
      container.read(_revision.notifier).increment();
      await tester.pump();
      expect(find.text('account epoch 1'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
      activity.value = (active: false, previewing: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      activity.value = (active: true, previewing: false);
      await tester.pump();
      expect(
        tester.element(find.byType(CircularProgressIndicator)),
        same(indicator),
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

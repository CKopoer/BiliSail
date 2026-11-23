import 'package:bilisail/features/settings/presentation/pgc_resolver_settings_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolver settings validate, save and choose a region', (
    tester,
  ) async {
    var enabled = false;
    var defaultRegion = '';
    final servers = <String, String>{'hk': '', 'tw': '', 'sea': '', 'cn': ''};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: PgcResolverSettingsSection(
                enabled: enabled,
                servers: servers,
                defaultRegion: defaultRegion,
                onEnabledChanged: (value) async =>
                    setState(() => enabled = value),
                onServerChanged: (region, value) async =>
                    setState(() => servers[region] = value),
                onDefaultRegionChanged: (value) async =>
                    setState(() => defaultRegion = value),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('pgc-resolver-hk')), findsNothing);
    await tester.tap(find.text('番剧地区解锁'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pgc-resolver-hk')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pgc-resolver-hk')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not a url');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入有效的 HTTP/HTTPS 服务器地址'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'https://hk.example.com/',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(servers['hk'], 'https://hk.example.com/');

    await tester.tap(find.byKey(const ValueKey('pgc-resolver-default-region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('东南亚').last);
    await tester.pumpAndSettle();
    expect(defaultRegion, 'sea');
  });
}

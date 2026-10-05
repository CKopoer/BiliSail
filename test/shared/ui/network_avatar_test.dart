import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'avatar fallback uses first complete character and stable dimensions',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: NetworkAvatar(name: '👩‍💻开发者', radius: 19)),
        ),
      );
      expect(find.text('👩‍💻'), findsOneWidget);
      expect(tester.getSize(find.byType(NetworkAvatar)), const Size(38, 38));
    },
  );
  testWidgets(
    'avatar image failure shows name and never receives account credentials',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkAvatar(
            url: Uri.parse('http://i0.hdslb.com/fail.jpg'),
            name: '作者',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('作'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      final provider =
          (image.image as ResizeImage).imageProvider as NetworkImage;
      expect(provider.url, 'https://i0.hdslb.com/fail.jpg');
      expect(
        provider.headers?.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unsupported image scheme uses person fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: NetworkAvatar(url: Uri.parse('file:///private.jpg'))),
    );
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

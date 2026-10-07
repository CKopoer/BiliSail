import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'logical punctuation aliases, unknown fallback and alternate layouts',
    () {
      final normalizer = InputNormalizer();
      for (final logical in [
        LogicalKeyboardKey.quote,
        LogicalKeyboardKey.quoteSingle,
      ]) {
        expect(
          normalizer
              .key(
                KeyDownEvent(
                  physicalKey: PhysicalKeyboardKey.quote,
                  logicalKey: logical,
                  timeStamp: Duration.zero,
                ),
              )
              .chord
              ?.key,
          'Quote',
        );
      }
      final fallback = normalizer.key(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.semicolon,
          logicalKey: LogicalKeyboardKey(0x200000001),
          timeStamp: Duration.zero,
        ),
      );
      expect(fallback.chord?.key, 'Semicolon');
      expect(fallback.physicalFallback, isTrue);
      final layout = normalizer.key(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.quote,
          logicalKey: LogicalKeyboardKey.keyK,
          timeStamp: Duration.zero,
        ),
      );
      expect(layout.chord?.key, 'K');
      expect(layout.physicalFallback, isFalse);
      expect(
        ShortcutChord.parse('ctrl+quoteSingle'),
        ShortcutChord.parse('Ctrl+Quote'),
      );
    },
  );
  test('side-button edges include combinations, move changes, release and ambiguity', () {
    final input = InputNormalizer();
    expect(
      input.pointer(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryMouseButton,
        ),
      ),
      isEmpty,
    );
    final pressed = input.pointer(
      const PointerMoveEvent(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton | kBackMouseButton,
      ),
    );
    expect(pressed.single.chord?.key, 'MouseBack');
    expect(
      input.pointer(
        const PointerMoveEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton | kPrimaryMouseButton,
        ),
      ),
      isEmpty,
    );
    expect(
      input
          .pointer(const PointerUpEvent(kind: PointerDeviceKind.mouse))
          .single
          .phase,
      InputPhase.up,
    );
    expect(
      input.pointer(
        const PointerDownEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton | kForwardMouseButton,
        ),
      ),
      isEmpty,
    );
    input.resetMouse();
    expect(
      input.pointer(
        const PointerMoveEvent(
          kind: PointerDeviceKind.mouse,
          buttons: kBackMouseButton,
        ),
      ),
      isEmpty,
    );
    expect(
      input
          .pointer(const PointerCancelEvent(kind: PointerDeviceKind.mouse))
          .single
          .phase,
      InputPhase.cancel,
    );
    expect(
      input
          .pointer(
            const PointerDownEvent(
              kind: PointerDeviceKind.mouse,
              buttons: kForwardMouseButton,
            ),
          )
          .single
          .chord
          ?.key,
      'MouseForward',
    );
    expect(
      input.pointer(const PointerDownEvent(buttons: kBackMouseButton)),
      isEmpty,
    );
  });
}

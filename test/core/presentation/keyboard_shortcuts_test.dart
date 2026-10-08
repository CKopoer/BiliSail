import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Windows tracks both sides of every modifier independently', () {
    final input = InputNormalizer(platform: TargetPlatform.windows);
    for (final (left, leftPhysical, right, rightPhysical, mask) in [
      (
        LogicalKeyboardKey.controlLeft,
        PhysicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight,
        PhysicalKeyboardKey.controlRight,
        ShortcutChord.control,
      ),
      (
        LogicalKeyboardKey.altLeft,
        PhysicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight,
        PhysicalKeyboardKey.altRight,
        ShortcutChord.alt,
      ),
      (
        LogicalKeyboardKey.shiftLeft,
        PhysicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight,
        PhysicalKeyboardKey.shiftRight,
        ShortcutChord.shift,
      ),
      (
        LogicalKeyboardKey.metaLeft,
        PhysicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight,
        PhysicalKeyboardKey.metaRight,
        ShortcutChord.meta,
      ),
    ]) {
      input.key(
        KeyDownEvent(
          physicalKey: leftPhysical,
          logicalKey: left,
          timeStamp: Duration.zero,
        ),
      );
      input.key(
        KeyDownEvent(
          physicalKey: rightPhysical,
          logicalKey: right,
          timeStamp: Duration.zero,
        ),
      );
      expect(input.modifiers, mask);
      input.key(
        KeyUpEvent(
          physicalKey: leftPhysical,
          logicalKey: left,
          timeStamp: Duration.zero,
        ),
      );
      expect(input.modifiers, mask);
      input.key(
        KeyUpEvent(
          physicalKey: rightPhysical,
          logicalKey: right,
          timeStamp: Duration.zero,
        ),
      );
      expect(input.modifiers, 0);
    }
  });
  test(
    'Windows modifier reset and synthesized reconciliation share mouse state',
    () {
      final input = InputNormalizer(platform: TargetPlatform.windows);
      input.key(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.altLeft,
          logicalKey: LogicalKeyboardKey.altLeft,
          timeStamp: Duration.zero,
        ),
      );
      expect(
        input
            .pointer(
              const PointerDownEvent(
                kind: PointerDeviceKind.mouse,
                buttons: kBackMouseButton,
              ),
            )
            .single
            .chord,
        ShortcutChord.parse('Alt+MouseBack'),
      );
      input.resetKeyboard();
      input.resetMouse();
      expect(input.modifiers, 0);
      expect(
        input
            .pointer(
              const PointerDownEvent(
                kind: PointerDeviceKind.mouse,
                buttons: kBackMouseButton,
              ),
            )
            .single
            .chord,
        ShortcutChord.parse('MouseBack'),
      );
      final synthesized = input.key(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
      expect(synthesized.synthesized, isTrue);
      expect(input.modifiers, ShortcutChord.control);
      expect(
        input
            .key(
              const KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.keyW,
                logicalKey: LogicalKeyboardKey.keyW,
                timeStamp: Duration.zero,
              ),
            )
            .chord,
        ShortcutChord.parse('Ctrl+W'),
      );
      input.key(
        const KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
          synthesized: true,
        ),
      );
      expect(input.modifiers, 0);
    },
  );
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

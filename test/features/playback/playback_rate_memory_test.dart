import 'package:bilisail/features/playback/application/playback_rate_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabling clears memory and ignores choices until enabled again', () {
    final memory = PlaybackRateMemory();
    memory.remember(2, revision: memory.beginChange());
    expect(memory.rateFor(1.25), 2);
    memory.configure(enabled: false);
    expect(memory.rateFor(1.25), 1.25);
    memory.remember(3, revision: memory.beginChange());
    expect(memory.rateFor(1.5), 1.5);
    memory.configure(enabled: true);
    expect(memory.rateFor(1.25), 1.25);
    final revision = memory.beginChange();
    memory.configure(enabled: true);
    memory.remember(1.5, revision: revision);
    expect(memory.rateFor(1.25), 1.5);
  });

  test('commands from before a toggle cannot restore old memory', () {
    final memory = PlaybackRateMemory();
    final previous = memory.beginChange();
    memory.configure(enabled: false);
    final disabled = memory.beginChange();
    memory.configure(enabled: true);
    memory.remember(2, revision: previous);
    memory.remember(3, revision: disabled);
    expect(memory.rateFor(1.25), 1.25);
    memory.remember(1.5, revision: memory.beginChange());
    memory.remember(2, revision: previous);
    expect(memory.rateFor(1.25), 1.5);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/offline_availability.dart';

void main() {
  test('completed metadata does not imply local readability', () {
    final result = evaluateOfflineAvailability(
      metadataCompleted: true,
      probe: () => false,
    );
    expect(result.metadataCompleted, isTrue);
    expect(result.localReadable, isFalse);
    expect(result.readyForOfflineUse, isFalse);
    expect(result.localState, OfflineAvailabilityState.missing);
  });

  test('only a successful local probe makes item available', () {
    final result = evaluateOfflineAvailability(
      metadataCompleted: false,
      probe: () => true,
    );
    expect(result.localReadable, isTrue);
    expect(result.readyForOfflineUse, isTrue);
  });

  test('probe errors become invalid instead of claiming availability', () {
    final result = evaluateOfflineAvailability(
      metadataCompleted: true,
      probe: () => throw StateError('unreadable'),
    );
    expect(result.localState, OfflineAvailabilityState.invalid);
    expect(result.localReadable, isFalse);
  });
}

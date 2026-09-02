/// Local availability is deliberately separate from persisted download status.
///
/// WebDAV and older metadata can report a completed download even when the
/// cache was cleared or moved. Consumers that need to open/export an image
/// should use [OfflineAvailability.localReadable], never metadata alone.
enum OfflineAvailabilityState { unknown, available, missing, invalid }

class OfflineAvailability {
  const OfflineAvailability({
    required this.metadataCompleted,
    required this.localState,
  });

  final bool metadataCompleted;
  final OfflineAvailabilityState localState;

  bool get localReadable => localState == OfflineAvailabilityState.available;

  /// Metadata is informational; it must not upgrade a missing local file.
  bool get readyForOfflineUse => localReadable;

  OfflineAvailability copyWith({
    bool? metadataCompleted,
    OfflineAvailabilityState? localState,
  }) => OfflineAvailability(
    metadataCompleted: metadataCompleted ?? this.metadataCompleted,
    localState: localState ?? this.localState,
  );
}

/// Converts a filesystem probe into the small state machine shared by reader
/// and export callers. The probe should verify existence and decodability.
OfflineAvailability evaluateOfflineAvailability({
  required bool metadataCompleted,
  required bool Function() probe,
}) {
  try {
    return OfflineAvailability(
      metadataCompleted: metadataCompleted,
      localState: probe()
          ? OfflineAvailabilityState.available
          : OfflineAvailabilityState.missing,
    );
  } catch (_) {
    return OfflineAvailability(
      metadataCompleted: metadataCompleted,
      localState: OfflineAvailabilityState.invalid,
    );
  }
}

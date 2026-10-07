/// Opt-in switch for codec-level target decoding in the reader.
///
/// The switch is compile-time so a release can be rolled back without
/// changing the on-disk canonical/decrypted cache.  A disabled build keeps
/// the legacy provider behavior; enabled builds still use the exact same
/// Rust path and only change Flutter's bitmap sampling target.
const bool readerTargetDecodeV1 = bool.fromEnvironment(
  'JM_READER_TARGET_DECODE_V1',
  defaultValue: false,
);

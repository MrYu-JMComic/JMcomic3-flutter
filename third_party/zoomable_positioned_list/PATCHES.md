# Pinned upstream and local patch

Source: https://pub.dev/packages/zoomable_positioned_list/versions/1.1.0

Published archive SHA-256:
`f17148ca7be6775131737b11ab738d059b845b7e3988d0095eb5b6e41c9023e4`

The upstream `lib/`, `pubspec.yaml`, and MIT license are retained. The original
Fuchsia/Google BSD license is also retained in `LICENSE.fuchsia`. This is the
same indexed zoom-list implementation used by the Jasmine reference frontend.

Local changes are confined to `lib/src/zoomable_positioned_list.dart`:

- Convert physical pinch/pan deltas to the logical scroll-axis direction when
  `reverse` is true (including double-tap focal-point preservation).
- Clamp programmatic zoom offsets to the actual scroll extents instead of an
  assumed zero minimum; indexed lists may legitimately have negative offsets.

Regression coverage is in `test/reader_regression_test.dart` and is run on both
the Flutter widget harness and Android. Keeping this small patch in a pinned
path dependency avoids editing a user's global Pub cache or depending on an
unpublished upstream change. Unrelated upstream files are not reformatted.

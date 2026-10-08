// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A zoomable, index-addressable scrollable list.
///
/// See [ZoomablePositionedList] for the main widget, [ItemScrollController] for
/// jumping/scrolling to an index, and [ScrollOffsetListener]/[ScrollOffsetController]
/// for observing or performing relative scroll operations.
library zoomable_positioned_list;

export 'src/item_positions_listener.dart';
export 'src/zoomable_positioned_list.dart';
export 'src/scroll_offset_listener.dart';

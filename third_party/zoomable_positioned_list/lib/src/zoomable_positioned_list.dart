// Copyright 2019 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'item_positions_listener.dart';
import 'item_positions_notifier.dart';
import 'positioned_list.dart';
import 'post_mount_callback.dart';
import 'scroll_offset_listener.dart';
import 'scroll_offset_notifier.dart';

/// Number of screens to scroll when scrolling a long distance.
const int _screenScrollCount = 2;

/// A scrollable list of widgets similar to [ListView], except scroll control
/// and position reporting is based on index rather than pixel offset.
///
/// [ZoomablePositionedList] lays out children in the same way as [ListView].
///
/// The list can be displayed with the item at [initialScrollIndex] positioned
/// at a particular [initialAlignment].
///
/// The [itemScrollController] can be used to scroll or jump to particular items
/// in the list.  The [itemPositionsNotifier] can be used to get a list of items
/// currently laid out by the list.
///
/// The [scrollOffsetListener] can be used to get updates about scroll position
/// changes.
///
/// All other parameters are the same as specified in [ListView].
class ZoomablePositionedList extends StatefulWidget {
  /// Create a [ZoomablePositionedList] whose items are provided by
  /// [itemBuilder].
  const ZoomablePositionedList.builder({
    required this.itemCount,
    required this.itemBuilder,
    Key? key,
    this.itemScrollController,
    this.shrinkWrap = false,
    ItemPositionsListener? itemPositionsListener,
    this.scrollOffsetController,
    ScrollOffsetListener? scrollOffsetListener,
    this.initialScrollIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.semanticChildCount,
    this.padding,
    this.addSemanticIndexes = true,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.minCacheExtent,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.initialScale = 1.0,
    this.doubleTapScale = 2.0,
    this.enableDoubleTapZoom = true,
    this.doubleTapAnimationDuration = const Duration(milliseconds: 200),
    this.enableZoom = true,
    this.dragRegionLock = false,
    this.gestureSpeed = 1.0,
  })  : itemPositionsNotifier = itemPositionsListener as ItemPositionsNotifier?,
        scrollOffsetNotifier = scrollOffsetListener as ScrollOffsetNotifier?,
        separatorBuilder = null,
        super(key: key);

  /// Create a [ZoomablePositionedList] whose items are provided by
  /// [itemBuilder] and separators provided by [separatorBuilder].
  const ZoomablePositionedList.separated({
    required this.itemCount,
    required this.itemBuilder,
    required this.separatorBuilder,
    Key? key,
    this.shrinkWrap = false,
    this.itemScrollController,
    ItemPositionsListener? itemPositionsListener,
    this.scrollOffsetController,
    ScrollOffsetListener? scrollOffsetListener,
    this.initialScrollIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.semanticChildCount,
    this.padding,
    this.addSemanticIndexes = true,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.minCacheExtent,
    this.minScale = 1.0,
    this.maxScale = 5.0,
    this.initialScale = 1.0,
    this.doubleTapScale = 2.0,
    this.enableDoubleTapZoom = true,
    this.doubleTapAnimationDuration = const Duration(milliseconds: 200),
    this.enableZoom = true,
    this.dragRegionLock = false,
    this.gestureSpeed = 1.0,
  })  : itemPositionsNotifier = itemPositionsListener as ItemPositionsNotifier?,
        scrollOffsetNotifier = scrollOffsetListener as ScrollOffsetNotifier?,
        super(key: key);

  /// Number of items the [itemBuilder] can produce.
  final int itemCount;

  /// Called to build children for the list with
  /// 0 <= index < itemCount.
  final IndexedWidgetBuilder itemBuilder;

  /// Called to build separators for between each item in the list.
  /// Called with 0 <= index < itemCount - 1.
  final IndexedWidgetBuilder? separatorBuilder;

  /// Controller for jumping or scrolling to an item.
  final ItemScrollController? itemScrollController;

  /// Notifier that reports the items laid out in the list after each frame.
  final ItemPositionsNotifier? itemPositionsNotifier;

  final ScrollOffsetController? scrollOffsetController;

  /// Notifier that reports the changes to the scroll offset.
  final ScrollOffsetNotifier? scrollOffsetNotifier;

  /// Index of an item to initially align within the viewport.
  final int initialScrollIndex;

  /// Determines where the leading edge of the item at [initialScrollIndex]
  /// should be placed.
  ///
  /// See [ItemScrollController.jumpTo] for an explanation of alignment.
  final double initialAlignment;

  /// The axis along which the scroll view scrolls.
  ///
  /// Defaults to [Axis.vertical].
  final Axis scrollDirection;

  /// Whether the view scrolls in the reading direction.
  ///
  /// Defaults to false.
  ///
  /// See [ScrollView.reverse].
  final bool reverse;

  /// {@macro flutter.widgets.scroll_view.shrinkWrap}
  /// Whether the extent of the scroll view in the [scrollDirection] should be
  /// determined by the contents being viewed.
  ///
  ///  Defaults to false.
  ///
  /// See [ScrollView.shrinkWrap].
  final bool shrinkWrap;

  /// How the scroll view should respond to user input.
  ///
  /// For example, determines how the scroll view continues to animate after the
  /// user stops dragging the scroll view.
  ///
  /// See [ScrollView.physics].
  final ScrollPhysics? physics;

  /// The number of children that will contribute semantic information.
  ///
  /// See [ScrollView.semanticChildCount] for more information.
  final int? semanticChildCount;

  /// The amount of space by which to inset the children.
  final EdgeInsets? padding;

  /// Whether to wrap each child in an [IndexedSemantics].
  ///
  /// See [SliverChildBuilderDelegate.addSemanticIndexes].
  final bool addSemanticIndexes;

  /// Whether to wrap each child in an [AutomaticKeepAlive].
  ///
  /// See [SliverChildBuilderDelegate.addAutomaticKeepAlives].
  final bool addAutomaticKeepAlives;

  /// Whether to wrap each child in a [RepaintBoundary].
  ///
  /// See [SliverChildBuilderDelegate.addRepaintBoundaries].
  final bool addRepaintBoundaries;

  /// The minimum cache extent used by the underlying scroll lists.
  /// See [ScrollView.cacheExtent].
  ///
  /// Note that the [ZoomablePositionedList] uses two lists to simulate long
  /// scrolls, so using the [ScrollController.scrollTo] method may result
  /// in builds of widgets that would otherwise already be built in the
  /// cache extent.
  final double? minCacheExtent;

  final double minScale;
  final double maxScale;
  final double initialScale;
  final double doubleTapScale;
  final bool enableDoubleTapZoom;
  final Duration doubleTapAnimationDuration;
  final bool enableZoom;
  final bool dragRegionLock;
  final double gestureSpeed;

  @override
  State<StatefulWidget> createState() => _ZoomablePositionedListState();
}

/// Controller to jump or scroll to a particular position in a
/// [ZoomablePositionedList].
class ItemScrollController {
  /// Creates an [ItemScrollController].
  ItemScrollController();

  /// Whether any ZoomablePositionedList objects are attached this object.
  ///
  /// If `false`, then [jumpTo] and [scrollTo] must not be called.
  bool get isAttached => _scrollableListState != null;

  _ZoomablePositionedListState? _scrollableListState;

  /// Immediately, without animation, reconfigure the list so that the item at
  /// [index]'s leading edge is at the given [alignment].
  ///
  /// The [alignment] specifies the desired position for the leading edge of the
  /// item.  The [alignment] is expected to be a value in the range \[0.0, 1.0\]
  /// and represents a proportion along the main axis of the viewport.
  ///
  /// For a vertically scrolling view that is not reversed:
  /// * 0 aligns the top edge of the item with the top edge of the view.
  /// * 1 aligns the top edge of the item with the bottom of the view.
  /// * 0.5 aligns the top edge of the item with the center of the view.
  ///
  /// For a horizontally scrolling view that is not reversed:
  /// * 0 aligns the left edge of the item with the left edge of the view
  /// * 1 aligns the left edge of the item with the right edge of the view.
  /// * 0.5 aligns the left edge of the item with the center of the view.
  void jumpTo({required int index, double alignment = 0}) {
    _scrollableListState!._jumpTo(index: index, alignment: alignment);
  }

  /// Animate the list over [duration] using the given [curve] such that the
  /// item at [index] ends up with its leading edge at the given [alignment].
  /// See [jumpTo] for an explanation of alignment.
  ///
  /// The [duration] must be greater than 0; otherwise, use [jumpTo].
  ///
  /// When item position is not available, because it's too far, the scroll
  /// is composed into three phases:
  ///
  ///  1. The currently displayed list view starts scrolling.
  ///  2. Another list view, which scrolls with the same speed, fades over the
  ///     first one and shows items that are close to the scroll target.
  ///  3. The second list view scrolls and stops on the target.
  ///
  /// The [opacityAnimationWeights] can be used to apply custom weights to these
  /// three stages of this animation. The default weights, `[40, 20, 40]`, are
  /// good with default [Curves.linear].  Different weights might be better for
  /// other cases.  For example, if you use [Curves.easeOut], consider setting
  /// [opacityAnimationWeights] to `[20, 20, 60]`.
  ///
  /// See [TweenSequenceItem.weight] for more info.
  Future<void> scrollTo({
    required int index,
    double alignment = 0,
    required Duration duration,
    Curve curve = Curves.linear,
    List<double> opacityAnimationWeights = const [40, 20, 40],
  }) {
    assert(_scrollableListState != null);
    assert(opacityAnimationWeights.length == 3);
    assert(duration > Duration.zero);
    return _scrollableListState!._scrollTo(
      index: index,
      alignment: alignment,
      duration: duration,
      curve: curve,
      opacityAnimationWeights: opacityAnimationWeights,
    );
  }

  void _attach(_ZoomablePositionedListState scrollableListState) {
    assert(_scrollableListState == null);
    _scrollableListState = scrollableListState;
  }

  void _detach() {
    _scrollableListState = null;
  }
}

/// Controller to scroll a certain number of pixels relative to the current
/// scroll offset.
///
/// Scrolls [offset] pixels relative to the current scroll offset. [offset] can
/// be positive or negative.
///
/// This is an experimental API and is subject to change.
/// Behavior may be ill-defined in some cases.  Please file bugs.
class ScrollOffsetController {
  /// Creates a [ScrollOffsetController].
  ScrollOffsetController();

  /// Animate the scroll position by a relative pixel [offset].
  ///
  /// Positive values scroll forward (down/right depending on axis), negative
  /// values scroll backward (up/left). This controller must be attached to a
  /// [ZoomablePositionedList] via `scrollOffsetController`.
  Future<void> animateScroll(
      {required double offset,
      required Duration duration,
      Curve curve = Curves.linear}) async {
    final currentPosition =
        _scrollableListState!.primary.scrollController.offset;
    final newPosition = currentPosition + offset;
    await _scrollableListState!.primary.scrollController.animateTo(
      newPosition,
      duration: duration,
      curve: curve,
    );
  }

  double get offset => _scrollableListState!.primary.scrollController.offset;

  /// The current maximum scroll extent of the attached list.
  double get maxScrollExtent =>
      _scrollableListState!.primary.scrollController.position.maxScrollExtent;

  _ZoomablePositionedListState? _scrollableListState;

  void _attach(_ZoomablePositionedListState scrollableListState) {
    assert(_scrollableListState == null);
    _scrollableListState = scrollableListState;
  }

  void _detach() {
    _scrollableListState = null;
  }
}

class _ZoomablePositionedListState extends State<ZoomablePositionedList>
    with TickerProviderStateMixin {
  /// Details for the primary (active) [ListView].
  var primary = _ListDisplayDetails(const ValueKey('Ping'));

  /// Details for the secondary (transitional) [ListView] that is temporarily
  /// shown when scrolling a long distance.
  var secondary = _ListDisplayDetails(const ValueKey('Pong'));

  final opacity = ProxyAnimation(const AlwaysStoppedAnimation<double>(0));

  void Function() startAnimationCallback = () {};

  bool _isTransitioning = false;

  var _animationController;
  AnimationController? _zoomAnimationController;
  Animation<double>? _zoomScaleAnimation;
  Animation<double>? _zoomPanAnimation;
  Animation<double>? _zoomScrollAnimation;

  double previousOffset = 0;

  double _scale = 1.0;
  double _panOffset = 0.0;
  double _baseScale = 1.0;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    _scale = widget.initialScale;

    final ItemPosition? initialPosition =
        PageStorage.maybeOf(context)?.readState(context) as ItemPosition?;
    primary.target = initialPosition?.index ?? widget.initialScrollIndex;
    primary.alignment =
        initialPosition?.itemLeadingEdge ?? widget.initialAlignment;
    if (widget.itemCount > 0 && primary.target > widget.itemCount - 1) {
      primary.target = widget.itemCount - 1;
    }
    widget.itemScrollController?._attach(this);
    widget.scrollOffsetController?._attach(this);
    primary.itemPositionsNotifier.itemPositions.addListener(_updatePositions);
    secondary.itemPositionsNotifier.itemPositions.addListener(_updatePositions);
    _zoomAnimationController = AnimationController(vsync: this);
    _zoomAnimationController!.addListener(() {
      setState(() {
        if (_zoomScaleAnimation != null) _scale = _zoomScaleAnimation!.value;
        if (_zoomPanAnimation != null) _panOffset = _zoomPanAnimation!.value;
        if (_zoomScrollAnimation != null &&
            primary.scrollController.hasClients) {
          primary.scrollController.jumpTo(_zoomScrollAnimation!.value);
        }
      });
    });
    primary.scrollController.addListener(() {
      final currentOffset = primary.scrollController.offset;
      final offsetChange = currentOffset - previousOffset;
      previousOffset = currentOffset;
      if (!_isTransitioning |
          (widget.scrollOffsetNotifier?.recordProgrammaticScrolls ?? false)) {
        widget.scrollOffsetNotifier?.changeController.add(offsetChange);
      }
    });
  }

  @override
  void activate() {
    super.activate();
    widget.itemScrollController?._attach(this);
    widget.scrollOffsetController?._attach(this);
  }

  @override
  void deactivate() {
    widget.itemScrollController?._detach();
    widget.scrollOffsetController?._detach();
    super.deactivate();
  }

  @override
  void dispose() {
    primary.itemPositionsNotifier.itemPositions
        .removeListener(_updatePositions);
    secondary.itemPositionsNotifier.itemPositions
        .removeListener(_updatePositions);
    _animationController?.dispose();
    _zoomAnimationController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ZoomablePositionedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemScrollController?._scrollableListState == this) {
      oldWidget.itemScrollController?._detach();
    }
    if (widget.itemScrollController?._scrollableListState != this) {
      widget.itemScrollController?._detach();
      widget.itemScrollController?._attach(this);
    }

    if (widget.itemCount == 0) {
      setState(() {
        primary.target = 0;
        secondary.target = 0;
      });
    } else {
      if (primary.target > widget.itemCount - 1) {
        setState(() {
          primary.target = widget.itemCount - 1;
        });
      }
      if (secondary.target > widget.itemCount - 1) {
        setState(() {
          secondary.target = widget.itemCount - 1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheExtent = _cacheExtent(constraints);
        // Pointer deltas are physical; ScrollPosition offsets follow the
        // logical axis. Reverse readers therefore need the opposite sign.
        final mainAxisSign = widget.reverse ? -1.0 : 1.0;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onDoubleTapDown: !widget.enableDoubleTapZoom || !widget.enableZoom
              ? null
              : (details) {
                  _zoomAnimationController?.stop();
                  double targetScale;
                  double targetPan;
                  double targetScroll = 0.0;
                  double currentScroll = primary.scrollController.hasClients
                      ? primary.scrollController.offset
                      : 0.0;

                  if (_scale != widget.initialScale || _panOffset.abs() > 0.1) {
                    targetScale = widget.initialScale;
                    targetPan = 0.0;
                    if (widget.scrollDirection == Axis.vertical) {
                      double screenHeight = constraints.maxHeight;
                      double tapY = details.localPosition.dy;
                      targetScroll = currentScroll +
                          mainAxisSign * (tapY - screenHeight / 2) *
                              (1 / _scale - 1 / targetScale);
                    } else {
                      double screenWidth = constraints.maxWidth;
                      double tapX = details.localPosition.dx;
                      targetScroll = currentScroll +
                          mainAxisSign * (tapX - screenWidth / 2) *
                              (1 / _scale - 1 / targetScale);
                    }
                  } else {
                    targetScale = widget.doubleTapScale;
                    double k = targetScale / _scale;
                    if (widget.scrollDirection == Axis.vertical) {
                      double screenWidth = constraints.maxWidth;
                      double screenHeight = constraints.maxHeight;
                      double tapX = details.localPosition.dx;
                      double tapY = details.localPosition.dy;

                      // Pan: (F - C)(1-k) + k*Pan
                      // here Pan is likely 0 if zooming in from 1.0, but general formula works
                      targetPan = (tapX - screenWidth / 2) * (1 - k) +
                          k * _panOffset;

                      double minPan = screenWidth / 3 -
                          screenWidth * targetScale -
                          (screenWidth / 2) * (1 - targetScale);
                      double maxPan = screenWidth * 2 / 3 -
                          (screenWidth / 2) * (1 - targetScale);
                      if (widget.dragRegionLock) {
                        if (targetScale <= 1.0) {
                          minPan = 0;
                          maxPan = 0;
                        } else {
                          minPan = -(screenWidth / 2) * (targetScale - 1);
                          maxPan = (screenWidth / 2) * (targetScale - 1);
                        }
                      }
                      targetPan = targetPan.clamp(minPan, maxPan);

                      targetScroll = currentScroll +
                          mainAxisSign * (tapY - screenHeight / 2) *
                              (1.0 - 1.0 / widget.doubleTapScale);
                    } else {
                      double screenWidth = constraints.maxWidth;
                      double screenHeight = constraints.maxHeight;
                      double tapX = details.localPosition.dx;
                      double tapY = details.localPosition.dy;

                      targetPan = (tapY - screenHeight / 2) * (1 - k) +
                          k * _panOffset;

                      double minPan = screenHeight / 3 -
                          screenHeight * targetScale -
                          (screenHeight / 2) * (1 - targetScale);
                      double maxPan = screenHeight * 2 / 3 -
                          (screenHeight / 2) * (1 - targetScale);
                      if (widget.dragRegionLock) {
                        if (targetScale <= 1.0) {
                          minPan = 0;
                          maxPan = 0;
                        } else {
                          minPan = -(screenHeight / 2) * (targetScale - 1);
                          maxPan = (screenHeight / 2) * (targetScale - 1);
                        }
                      }
                      targetPan = targetPan.clamp(minPan, maxPan);

                      targetScroll = currentScroll +
                          mainAxisSign * (tapX - screenWidth / 2) *
                              (1.0 - 1.0 / widget.doubleTapScale);
                    }
                  }

                  // Clamp targetScroll? ScrollController usually handles clamping but
                  // we might want to ensure we don't animate to negative if lists don't support it.
                  if (primary.scrollController.hasClients) {
                    final position = primary.scrollController.position;
                    targetScroll = targetScroll.clamp(
                        position.minScrollExtent, position.maxScrollExtent);
                  }

                  if (widget.doubleTapAnimationDuration == Duration.zero) {
                    setState(() {
                      _scale = targetScale;
                      _panOffset = targetPan;
                      if (primary.scrollController.hasClients) {
                        primary.scrollController.jumpTo(targetScroll);
                      }
                    });
                  } else {
                    _zoomAnimationController!.duration =
                        widget.doubleTapAnimationDuration;
                    _zoomScaleAnimation =
                        Tween<double>(begin: _scale, end: targetScale).animate(
                            CurvedAnimation(
                                parent: _zoomAnimationController!,
                                curve: Curves.easeInOut));
                    _zoomPanAnimation =
                        Tween<double>(begin: _panOffset, end: targetPan)
                            .animate(CurvedAnimation(
                                parent: _zoomAnimationController!,
                                curve: Curves.easeInOut));
                    _zoomScrollAnimation = Tween<double>(
                            begin: currentScroll, end: targetScroll)
                        .animate(CurvedAnimation(
                            parent: _zoomAnimationController!,
                            curve: Curves.easeInOut));

                    _zoomAnimationController!.reset();
                    _zoomAnimationController!.forward();
                  }
                },
          onScaleStart: !widget.enableZoom
              ? null
              : (details) {
                  _zoomAnimationController?.stop();
                  _baseScale = _scale;
                  _stopScroll(canceled: true);
                },
          onScaleUpdate: !widget.enableZoom
              ? null
              : (details) {
                  if (details.pointerCount == 2 &&
                _scale == widget.minScale &&
                (details.scale - 1).abs() < 0.02) {
              return;
            }
            setState(() {
              double effectiveScaleInput =
                  pow(details.scale, widget.gestureSpeed).toDouble();
              double newScale = (_baseScale * effectiveScaleInput)
                  .clamp(widget.minScale, widget.maxScale);
              double scaleDelta = newScale / _scale;

              if (widget.scrollDirection == Axis.vertical) {
                // Text is scrolling vertically (Y). Panning horizontally (X).
                // Alignment.center logic:
                // VisualY = s*(y_loc - Scroll) + Cy*(1-s)
                // VisualX = s * x_loc + Pan + Cx*(1-s) (Assuming x_loc relative to 0)

                double screenWidth = constraints.maxWidth;
                double screenHeight = constraints.maxHeight;
                double centerX = screenWidth / 2;
                double centerY = screenHeight / 2;

                // 1. Calculate new Scroll Offset (Main Axis - Y)
                double currentScroll = primary.scrollController.hasClients
                    ? primary.scrollController.offset
                    : 0.0;
                double distY = details.localFocalPoint.dy - centerY;
                // Scroll_new = Scroll_old + (Fy - Cy)(1/s - 1/s') - delta/s'
                // Use _scale (old scale) for delta to be precise with frame timing?
                // Actually mathematically derived is s_new for absolute positioning.
                // Keeping s_new as it matches derivation Y_abs invariant.
                double scrollChange = mainAxisSign * (distY * (1 / _scale - 1 / newScale) -
                    (details.focalPointDelta.dy * widget.gestureSpeed) /
                        newScale);
                double newScroll = currentScroll + scrollChange;

                // 2. Calculate new Pan Offset (Cross Axis - X)
                // Pan' = (Fx - Cx)(1-k) + deltaX + k*Pan
                double distX = details.localFocalPoint.dx - centerX;
                double newPan = distX * (1 - scaleDelta) +
                    (details.focalPointDelta.dx * widget.gestureSpeed) +
                    scaleDelta * _panOffset;

                // 3. Clamp Pan Offset
                double minPan = screenWidth / 3 -
                    screenWidth * newScale -
                    centerX * (1 - newScale);
                double maxPan =
                    screenWidth * 2 / 3 - centerX * (1 - newScale);
                if (widget.dragRegionLock) {
                  if (newScale <= 1.0) {
                    minPan = 0;
                    maxPan = 0;
                  } else {
                    minPan = -centerX * (newScale - 1);
                    maxPan = centerX * (newScale - 1);
                  }
                }
                newPan = newPan.clamp(minPan, maxPan);

                // 4. Apply
                _scale = newScale;
                _panOffset = newPan;
                if (primary.scrollController.hasClients) {
                  primary.scrollController.jumpTo(newScroll);
                }
              } else {
                // Text is scrolling horizontally (X). Panning vertically (Y).

                double screenWidth = constraints.maxWidth;
                double screenHeight = constraints.maxHeight;
                double centerX = screenWidth / 2;
                double centerY = screenHeight / 2;

                // 1. Calculate new Scroll Offset (Main Axis - X)
                double currentScroll = primary.scrollController.hasClients
                    ? primary.scrollController.offset
                    : 0.0;
                double distX = details.localFocalPoint.dx - centerX;
                double scrollChange = mainAxisSign * (distX * (1 / _scale - 1 / newScale) -
                    (details.focalPointDelta.dx * widget.gestureSpeed) /
                        newScale);
                double newScroll = currentScroll + scrollChange;

                // 2. Calculate new Pan Offset (Cross Axis - Y)
                double distY = details.localFocalPoint.dy - centerY;
                double newPan = distY * (1 - scaleDelta) +
                    (details.focalPointDelta.dy * widget.gestureSpeed) +
                    scaleDelta * _panOffset;

                // 3. Clamp Pan Offset
                double minPan = screenHeight / 3 -
                    screenHeight * newScale -
                    centerY * (1 - newScale);
                double maxPan =
                    screenHeight * 2 / 3 - centerY * (1 - newScale);
                if (widget.dragRegionLock) {
                  if (newScale <= 1.0) {
                    minPan = 0;
                    maxPan = 0;
                  } else {
                    minPan = -centerY * (newScale - 1);
                    maxPan = centerY * (newScale - 1);
                  }
                }
                newPan = newPan.clamp(minPan, maxPan);

                // 4. Apply
                _scale = newScale;
                _panOffset = newPan;
                if (primary.scrollController.hasClients) {
                  primary.scrollController.jumpTo(newScroll);
                }
              }
            });
          },
          child: Listener(
            onPointerDown: (_) {
              _stopScroll(canceled: true);
              setState(() {
                _pointers++;
              });
            },
            onPointerUp: (_) {
              setState(() {
                _pointers--;
              });
            },
            onPointerCancel: (_) {
              setState(() {
                _pointers = 0;
              });
            },
            child: Transform(
              transform: widget.scrollDirection == Axis.vertical
                  ? (Matrix4.identity()
                    ..translate(
                        _panOffset + constraints.maxWidth / 2 * (1 - _scale),
                        constraints.maxHeight / 2 * (1 - _scale))
                    ..scale(_scale))
                  : (Matrix4.identity()
                    ..translate(
                        constraints.maxWidth / 2 * (1 - _scale),
                        _panOffset + constraints.maxHeight / 2 * (1 - _scale))
                    ..scale(_scale)),
              alignment: Alignment.topLeft,
              child: Stack(
                children: <Widget>[
              PostMountCallback(
                key: primary.key,
                callback: startAnimationCallback,
                child: FadeTransition(
                  opacity: ReverseAnimation(opacity),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) => _isTransitioning,
                    child: PositionedList(
                      itemBuilder: widget.itemBuilder,
                      separatorBuilder: widget.separatorBuilder,
                      itemCount: widget.itemCount,
                      positionedIndex: primary.target,
                      controller: primary.scrollController,
                      itemPositionsNotifier: primary.itemPositionsNotifier,
                      scrollDirection: widget.scrollDirection,
                      reverse: widget.reverse,
                      cacheExtent: cacheExtent,
                      alignment: primary.alignment,
                      physics: _scale > 1.0 || _pointers >= 2
                          ? const NeverScrollableScrollPhysics()
                          : (widget.gestureSpeed == 1.0
                              ? widget.physics
                              : _SpeedMultiplierPhysics(
                                  speed: widget.gestureSpeed,
                                  parent: widget.physics)),
                      shrinkWrap: widget.shrinkWrap,
                      addSemanticIndexes: widget.addSemanticIndexes,
                      semanticChildCount: widget.semanticChildCount,
                      padding: widget.padding,
                      addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
                      addRepaintBoundaries: widget.addRepaintBoundaries,
                    ),
                  ),
                ),
              ),
              if (_isTransitioning)
                PostMountCallback(
                  key: secondary.key,
                  callback: startAnimationCallback,
                  child: FadeTransition(
                    opacity: opacity,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (_) => false,
                      child: PositionedList(
                        itemBuilder: widget.itemBuilder,
                        separatorBuilder: widget.separatorBuilder,
                        itemCount: widget.itemCount,
                        itemPositionsNotifier: secondary.itemPositionsNotifier,
                        positionedIndex: secondary.target,
                        controller: secondary.scrollController,
                        scrollDirection: widget.scrollDirection,
                        reverse: widget.reverse,
                        cacheExtent: cacheExtent,
                        alignment: secondary.alignment,
                        physics: _scale > 1.0 || _pointers >= 2
                            ? const NeverScrollableScrollPhysics()
                            : (widget.gestureSpeed == 1.0
                                ? widget.physics
                                : _SpeedMultiplierPhysics(
                                    speed: widget.gestureSpeed,
                                    parent: widget.physics)),
                        shrinkWrap: widget.shrinkWrap,
                        addSemanticIndexes: widget.addSemanticIndexes,
                        semanticChildCount: widget.semanticChildCount,
                        padding: widget.padding,
                        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
                        addRepaintBoundaries: widget.addRepaintBoundaries,
                      ),
                    ),
                  ),
                ),
            ],
          ),
            ),
          ),
        );
      },
    );
  }

  double _cacheExtent(BoxConstraints constraints) => max(
        (widget.scrollDirection == Axis.vertical
                ? constraints.maxHeight
                : constraints.maxWidth) *
            _screenScrollCount,
        widget.minCacheExtent ?? 0,
      );

  void _jumpTo({required int index, required double alignment}) {
    _stopScroll(canceled: true);
    if (index > widget.itemCount - 1) {
      index = widget.itemCount - 1;
    }
    setState(() {
      primary.scrollController.jumpTo(0);
      primary.target = index;
      primary.alignment = alignment;
    });
  }

  Future<void> _scrollTo({
    required int index,
    required double alignment,
    required Duration duration,
    Curve curve = Curves.linear,
    required List<double> opacityAnimationWeights,
  }) async {
    if (index > widget.itemCount - 1) {
      index = widget.itemCount - 1;
    }
    if (_isTransitioning) {
      final scrollCompleter = Completer<void>();
      _stopScroll(canceled: true);
      SchedulerBinding.instance.addPostFrameCallback((_) async {
        await _startScroll(
          index: index,
          alignment: alignment,
          duration: duration,
          curve: curve,
          opacityAnimationWeights: opacityAnimationWeights,
        );
        scrollCompleter.complete();
      });
      await scrollCompleter.future;
    } else {
      await _startScroll(
        index: index,
        alignment: alignment,
        duration: duration,
        curve: curve,
        opacityAnimationWeights: opacityAnimationWeights,
      );
    }
  }

  Future<void> _startScroll({
    required int index,
    required double alignment,
    required Duration duration,
    Curve curve = Curves.linear,
    required List<double> opacityAnimationWeights,
  }) async {
    final direction = index > primary.target ? 1 : -1;
    final itemPosition = primary.itemPositionsNotifier.itemPositions.value
        .firstWhereOrNull(
            (ItemPosition itemPosition) => itemPosition.index == index);
    if (itemPosition != null) {
      // Scroll directly.
      final localScrollAmount = itemPosition.itemLeadingEdge *
          primary.scrollController.position.viewportDimension;
      await primary.scrollController.animateTo(
          primary.scrollController.offset +
              localScrollAmount -
              alignment * primary.scrollController.position.viewportDimension,
          duration: duration,
          curve: curve);
    } else {
      final scrollAmount = _screenScrollCount *
          primary.scrollController.position.viewportDimension;
      final startCompleter = Completer<void>();
      final endCompleter = Completer<void>();
      startAnimationCallback = () {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          startAnimationCallback = () {};
          _animationController?.dispose();
          _animationController =
              AnimationController(vsync: this, duration: duration)..forward();
          opacity.parent = _opacityAnimation(opacityAnimationWeights)
              .animate(_animationController);
          secondary.scrollController.jumpTo(-direction *
              (_screenScrollCount *
                      primary.scrollController.position.viewportDimension -
                  alignment *
                      secondary.scrollController.position.viewportDimension));

          startCompleter.complete(primary.scrollController.animateTo(
              primary.scrollController.offset + direction * scrollAmount,
              duration: duration,
              curve: curve));
          endCompleter.complete(secondary.scrollController
              .animateTo(0, duration: duration, curve: curve));
        });
      };
      setState(() {
        // TODO: _startScroll can be re-entrant, which invalidates this assert.
        // assert(!_isTransitioning);
        secondary.target = index;
        secondary.alignment = alignment;
        _isTransitioning = true;
      });
      await Future.wait<void>([startCompleter.future, endCompleter.future]);
      _stopScroll();
    }
  }

  void _stopScroll({bool canceled = false}) {
    if (!_isTransitioning) {
      return;
    }

    if (canceled) {
      if (primary.scrollController.hasClients) {
        primary.scrollController.jumpTo(primary.scrollController.offset);
      }
      if (secondary.scrollController.hasClients) {
        secondary.scrollController.jumpTo(secondary.scrollController.offset);
      }
    }

    if (mounted) {
      setState(() {
        if (opacity.value >= 0.5) {
          // Secondary [ListView] is more visible than the primary; make it the
          // new primary.
          var temp = primary;
          primary = secondary;
          secondary = temp;
        }
        _isTransitioning = false;
        opacity.parent = const AlwaysStoppedAnimation<double>(0);
      });
    }
  }

  Animatable<double> _opacityAnimation(List<double> opacityAnimationWeights) {
    final startOpacity = 0.0;
    final endOpacity = 1.0;
    return TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
          tween: ConstantTween<double>(startOpacity),
          weight: opacityAnimationWeights[0]),
      TweenSequenceItem<double>(
          tween: Tween<double>(begin: startOpacity, end: endOpacity),
          weight: opacityAnimationWeights[1]),
      TweenSequenceItem<double>(
          tween: ConstantTween<double>(endOpacity),
          weight: opacityAnimationWeights[2]),
    ]);
  }

  void _updatePositions() {
    final itemPositions = primary.itemPositionsNotifier.itemPositions.value
        .where((ItemPosition position) =>
            position.itemLeadingEdge < 1 && position.itemTrailingEdge > 0);
    if (itemPositions.isNotEmpty) {
      PageStorage.maybeOf(context)?.writeState(
        context,
        itemPositions.reduce((value, element) =>
            value.itemLeadingEdge < element.itemLeadingEdge ? value : element),
      );
    }
    widget.itemPositionsNotifier?.itemPositions.value = itemPositions;
  }
}

class _ListDisplayDetails {
  _ListDisplayDetails(this.key);

  final itemPositionsNotifier = ItemPositionsNotifier();
  final scrollController = ScrollController(keepScrollOffset: false);

  /// The index of the item to scroll to.
  int target = 0;

  /// The desired alignment for [target].
  ///
  /// See [ItemScrollController.jumpTo] for an explanation of alignment.
  double alignment = 0;

  final Key key;
}

class _SpeedMultiplierPhysics extends ScrollPhysics {
  final double speed;

  const _SpeedMultiplierPhysics({required this.speed, ScrollPhysics? parent})
      : super(parent: parent);

  @override
  _SpeedMultiplierPhysics applyTo(ScrollPhysics? ancestor) {
    return _SpeedMultiplierPhysics(speed: speed, parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset) * speed;
  }
}

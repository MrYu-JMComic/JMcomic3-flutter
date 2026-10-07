import 'package:flutter/material.dart';

/// 横向和纵向自由缩放共用的缩放表面，双击明确切换 1 倍和 2 倍。
/// 比例独立于原图长宽比，避免贴合视口的图片双击时没有可切换的缩放状态。
class ReaderZoomSurface extends StatefulWidget {
  final TransformationController controller;
  final Widget child;
  final bool panEnabled;
  final bool allowDoubleTap;
  final double maxScale;

  /// Keeps the child gesture arena intact while still applying the shared
  /// transform. This is used by the vertical reader so a zoomed chapter can
  /// continue scrolling through page boundaries.
  final bool continuousScroll;

  const ReaderZoomSurface({
    required this.controller,
    required this.child,
    required this.panEnabled,
    this.allowDoubleTap = true,
    this.maxScale = 4,
    this.continuousScroll = false,
    super.key,
  });

  @override
  State<ReaderZoomSurface> createState() => _ReaderZoomSurfaceState();
}

class _ReaderZoomSurfaceState extends State<ReaderZoomSurface>
    with SingleTickerProviderStateMixin {
  Offset _doubleTapPosition = Offset.zero;
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    )..addListener(_animateZoom);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(ReaderZoomSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _animateZoom() {
    final fraction = _animation.value;
    widget.controller.value = Matrix4.diagonal3Values(
      1.0 + fraction,
      1.0 + fraction,
      1,
    )..setTranslationRaw(
        -_doubleTapPosition.dx * fraction,
        -_doubleTapPosition.dy * fraction,
        0,
      );
  }

  void _doubleTap() {
    if (_animation.isAnimating) {
      return;
    }
    if (widget.controller.value.getMaxScaleOnAxis() > 1.001) {
      widget.controller.value = Matrix4.identity();
    } else {
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.continuousScroll
        ? ClipRect(
            child: Transform(
              alignment: Alignment.topLeft,
              transform: widget.controller.value,
              child: widget.child,
            ),
          )
        : InteractiveViewer(
            transformationController: widget.controller,
            minScale: 1,
            maxScale: widget.maxScale,
            boundaryMargin: EdgeInsets.zero,
            panEnabled: widget.panEnabled,
            child: widget.child,
          );
    return GestureDetector(
      onDoubleTapDown: widget.allowDoubleTap
          ? (details) => _doubleTapPosition = details.localPosition
          : null,
      onDoubleTap: widget.allowDoubleTap ? _doubleTap : null,
      child: child,
    );
  }
}

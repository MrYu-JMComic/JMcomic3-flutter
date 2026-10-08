part of '../comic_reader_screen.dart';

/// Jasmine-style indexed continuous reader. The list owns both scrolling and
/// pinch/pan gestures; the reader observes layout rather than moving a second
/// InteractiveViewer or inferring a page from total scroll percentage.
class _ContinuousReaderState extends _ComicReaderState {
  final _scroll = zoomable.ItemScrollController();
  final _positions = zoomable.ItemPositionsListener.create();
  final _viewportKey = GlobalKey();
  final Map<int, BuildContext> _pageContexts = {};
  late final List<Size?> _sizes;
  bool _reportQueued = false;
  Timer? _settledTimer;

  bool get _zoomEnabled => widget.readerType == ReaderType.webToonFreeZoom;
  bool get _vertical => widget.readerDirection == ReaderDirection.topToBottom;

  @override
  void initState() {
    super.initState();
    _sizes = [
      for (final page in _pages)
        page.hasDimensions
            ? Size(page.width.toDouble(), page.height.toDouble())
            : null
    ];
    _positions.itemPositions.addListener(_queuePositionReport);
  }

  @override
  void dispose() {
    _settledTimer?.cancel();
    _positions.itemPositions.removeListener(_queuePositionReport);
    _pageContexts.clear();
    super.dispose();
  }

  void _queuePositionReport() {
    if (!mounted || _reportQueued) return;
    _reportQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportQueued = false;
      if (mounted) _onCurrentChange(_visiblePage());
    });
  }

  @override
  int _visiblePage() {
    final positions = _positions.itemPositions.value
        .where((p) =>
            p.index < widget.chapter.images.length &&
            p.itemTrailingEdge > 0 &&
            p.itemLeadingEdge < 1)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is RenderBox && viewport.hasSize) {
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      for (final position in positions) {
        final context = _pageContexts[position.index];
        if (context == null || !context.mounted) continue;
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final rect = MatrixUtils.transformRect(
            box.getTransformTo(null), Offset.zero & box.size);
        if (rect.intersect(bounds).width > .5 &&
            rect.intersect(bounds).height > .5) {
          return position.index;
        }
      }
    }
    return positions.isEmpty ? _current : positions.first.index;
  }

  @override
  Future<void> _moveTo(int page, bool animation) async {
    if (!_scroll.isAttached) return;
    if (animation) {
      await _scroll.scrollTo(
          index: page,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(index: page);
      await WidgetsBinding.instance.endOfFrame;
    }
    _queuePositionReport();
  }

  @override
  Widget _buildViewer() => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final list = zoomable.ZoomablePositionedList.builder(
          key: ValueKey('continuous-${widget.chapter.id}'),
          enableZoom: _zoomEnabled,
          enableDoubleTapZoom: _zoomEnabled && !_doubleTapFullscreen,
          minScale: 1,
          maxScale: 4,
          doubleTapScale: 2,
          dragRegionLock: true,
          doubleTapAnimationDuration: currentNoAnimation()
              ? Duration.zero
              : const Duration(milliseconds: 200),
          initialScrollIndex: _current,
          itemScrollController: _scroll,
          itemPositionsListener: _positions,
          scrollDirection: _vertical ? Axis.vertical : Axis.horizontal,
          reverse: widget.readerDirection == ReaderDirection.rightToLeft,
          minCacheExtent: 0,
          physics: const ClampingScrollPhysics(),
          itemCount: widget.chapter.images.length + 1,
          itemBuilder: (context, index) {
            if (index == widget.chapter.images.length) {
              return SizedBox(
                  width: _vertical ? size.width : 180, child: _buildNextEp());
            }
            final source = _sizes[index];
            final ratio = source == null
                ? (_vertical ? 2.0 : .5)
                : source.width / source.height;
            final extent = _vertical
                ? Size(size.width, size.width / ratio)
                : Size(size.height * ratio, size.height);
            final page = _pageAt(index);
            return Builder(builder: (pageContext) {
              _pageContexts[index] = pageContext;
              return JMPageImage(
                widget.chapter.id,
                page.name,
                key: ValueKey('reader-page-${widget.chapter.id}-$index'),
                pageIndex: page.sourceIndex,
                localPath: page.localAvailable ? page.localPath : null,
                localOnly: page.localPath != null,
                preserveSourceAspectRatio: true,
                width: extent.width,
                height: extent.height,
                onTrueSize: (actual) {
                  if (!mounted ||
                      !actual.width.isFinite ||
                      !actual.height.isFinite ||
                      actual.width <= 0 ||
                      actual.height <= 0 ||
                      _sizes[index] == actual) {
                    return;
                  }
                  _sizes[index] = actual;
                  _repaint();
                  _queuePositionReport();
                },
              );
            });
          },
        );
        return SizedBox.expand(
          key: _viewportKey,
          child: Listener(
            onPointerDown: (_) => _cancelJump(),
            onPointerMove: (_) => _queuePositionReport(),
            onPointerUp: (_) {
              _settledTimer?.cancel();
              _settledTimer = Timer(
                  const Duration(milliseconds: 240), _queuePositionReport);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _handlesSingleTap
                  ? (details) => _handleTap(details, size)
                  : null,
              onDoubleTap: _doubleTapFullscreen ? _toggleFullscreen : null,
              child: list,
            ),
          ),
        );
      });
}

/// One lazy PhotoView gallery owns zoom/pan and page gestures for both single
/// pages and spreads. A spread maps to its first source index; odd tails have
/// an empty partner rather than reading past the end of the chapter.
class _PagedReaderState extends _ComicReaderState {
  late final PageController _pageController;
  final Map<int, PhotoViewController> _zoomControllers = {};
  final Map<int, int> _reloadVersions = {};

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: _current ~/ (_paired ? 2 : 1));
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _zoomControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  int _visiblePage() => _normalizePage(
      ((_pageController.hasClients ? _pageController.page : null) ??
                  _current / (_paired ? 2 : 1))
              .round() *
          (_paired ? 2 : 1));

  @override
  Future<void> _moveTo(int page, bool animation) async {
    if (!_pageController.hasClients) return;
    final slot = page ~/ (_paired ? 2 : 1);
    if (animation) {
      await _pageController.animateToPage(slot,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic);
    } else {
      _pageController.jumpToPage(slot);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _reloadImage(int index) async {
    final provider = _readerPageProvider(index);
    imageCache.evict(provider, includeLive: true);
    final page = _pageAt(index);
    // Retry only this page's path/decode lookup. Never delete downloaded files
    // or clear unrelated caches as a side effect of a reader retry.
    evictPageImageMemoryCache(widget.chapter.id, page.name);
    if (!mounted) return;
    _providers.remove(index);
    setState(() => _reloadVersions[index] = (_reloadVersions[index] ?? 0) + 1);
  }

  Widget _image(int index) => Image(
        key: ValueKey(
            'reader-page-${widget.chapter.id}-$index-${_reloadVersions[index] ?? 0}'),
        image: _readerPageProvider(index),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => LayoutBuilder(
          builder: (context, constraints) => buildError(
              context, constraints.maxWidth, constraints.maxHeight,
              onReload: () =>
                  unawaited(_reloadImage(index).catchError((_) {}))),
        ),
      );

  @override
  Widget _buildViewer() => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final pairs = buildPagePairs(widget.chapter.images.length,
            cover: false,
            rtl: currentTwoPageDirection == TwoPageDirection.rightToLeft);
        return Listener(
            onPointerDown: (_) => _cancelJump(),
            child: Stack(children: [
              PhotoViewGallery.builder(
                pageController: _pageController,
                itemCount:
                    _paired ? pairs.length : widget.chapter.images.length,
                scrollDirection:
                    widget.readerDirection == ReaderDirection.topToBottom
                        ? Axis.vertical
                        : Axis.horizontal,
                reverse: widget.readerDirection == ReaderDirection.rightToLeft,
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                scrollPhysics: const ClampingScrollPhysics(),
                onPageChanged: (slot) {
                  _onCurrentChange(slot * (_paired ? 2 : 1));
                  for (final entry in _zoomControllers.entries) {
                    if (entry.key != slot) {
                      entry.value.scale = 1;
                      entry.value.position = Offset.zero;
                    }
                  }
                },
                builder: (context, slot) {
                  final controller = _zoomControllers.putIfAbsent(
                      slot, () => PhotoViewController(initialScale: 1));
                  final pair = _paired ? pairs[slot] : null;
                  final child = pair == null
                      ? _image(slot)
                      : Row(children: [
                          Expanded(
                              child: pair.left == null
                                  ? const SizedBox.shrink()
                                  : _image(pair.left!)),
                          Expanded(
                              child: pair.right == null
                                  ? const SizedBox.shrink()
                                  : _image(pair.right!)),
                        ]);
                  return PhotoViewGalleryPageOptions.customChild(
                    child: SizedBox.fromSize(size: size, child: child),
                    childSize: size,
                    minScale: 1.0,
                    initialScale: 1.0,
                    maxScale: 4.0,
                    controller: controller,
                    onTapUp: _handlesSingleTap
                        ? (_, details, __) => _handleTap(details, size)
                        : null,
                    scaleStateCycle: (state) {
                      // Leave PhotoView in charge of pinch/pan. This only defines the
                      // double-tap action, including fullscreen control modes.
                      scheduleMicrotask(() {
                        if (!mounted) return;
                        if (_doubleTapFullscreen) {
                          _toggleFullscreen();
                        } else {
                          controller.scale =
                              (controller.scale ?? 1) > 1.01 ? 1 : 2;
                          controller.position = Offset.zero;
                        }
                      });
                      return state;
                    },
                  );
                },
              ),
              if (_current >=
                  (_paired
                      ? (widget.chapter.images.length - 1) ~/ 2 * 2
                      : widget.chapter.images.length - 1))
                Align(
                    alignment: Alignment.bottomRight,
                    child: SizedBox(width: 150, child: _buildNextEp())),
            ]));
      });
}

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:another_xlider/another_xlider.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../configs/ignore_view_log.dart';
import '../configs/no_animation.dart';
import '../configs/volume_key_control.dart';
import '../configs/reader_target_decode.dart';
import 'components/images.dart';
import 'components/right_click_pop.dart';
import '../reader_session.dart';
import '../basic/reader_pages.dart';

class ComicReaderScreen extends StatefulWidget {
  final ComicBasic comic;
  final List<Series> series;
  final int chapterId;
  final int initRank;
  final Future<ChapterResponse> Function(int seriesId) loadChapter;
  final bool fullScreenOnInit;

  const ComicReaderScreen({
    Key? key,
    required this.comic,
    required this.series,
    required this.chapterId,
    required this.initRank,
    required this.loadChapter,
    this.fullScreenOnInit = false,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late ReaderType _readerType;
  late ReaderDirection _readerDirection;
  late Future<ChapterResponse> _chapterFuture;
  bool _navigationInFlight = false;

  /// Record the opening position without allowing a failed auxiliary request
  /// to become an unhandled asynchronous error.  The `ignore_view_log`
  /// compatibility behavior intentionally remains unchanged: when enabled,
  /// the album request still gates the initial view-log write.
  Future<void> _recordInitialViewLog() async {
    final comicId = widget.comic.id;
    final chapterId = widget.chapterId;
    final page = widget.initRank;
    try {
      if (currentIgnoreVewLog()) {
        await methods.album(comicId);
      }
      await methods.updateViewLog(comicId, chapterId, page);
    } catch (error, stackTrace) {
      debugPrient("initial view log failed: $error\n$stackTrace");
    }
  }

  Future<ChapterResponse> _loadChapter(int chapterId) {
    // A custom offline loader may throw before returning a Future. Normalize
    // that case into FutureBuilder's error path instead of failing initState
    // or a setState callback synchronously.
    return Future<ChapterResponse>.sync(
      () => widget.loadChapter(chapterId),
    );
  }

  void _load() {
    if (!mounted) {
      return;
    }
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapterFuture = _loadChapter(widget.chapterId);
    });
  }

  Future<void> _replaceReaderRoute({
    required int chapterId,
    required int initRank,
    required bool fullScreen,
  }) async {
    if (!mounted || _navigationInFlight) {
      return;
    }
    _navigationInFlight = true;
    try {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (BuildContext context) {
          return ComicReaderScreen(
            comic: widget.comic,
            series: widget.series,
            chapterId: chapterId,
            initRank: initRank,
            loadChapter: widget.loadChapter,
            fullScreenOnInit: fullScreen,
          );
        }),
      );
    } catch (error, stackTrace) {
      // A route can disappear while a control callback is waiting. Keep the
      // old reader usable when Navigator rejects the replacement instead of
      // leaving the single-flight guard permanently locked.
      debugPrient("reader navigation failed: $error\n$stackTrace");
    } finally {
      _navigationInFlight = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _readerType = currentReaderType;
    _readerDirection = currentReaderDirection;
    _chapterFuture = _loadChapter(widget.chapterId);
    unawaited(_recordInitialViewLog());
  }

  @override
  void didUpdateWidget(covariant ComicReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterId != widget.chapterId ||
        oldWidget.comic.id != widget.comic.id) {
      // A parent may reuse this State instead of pushing a replacement route.
      // Replace the chapter Future synchronously so FutureBuilder cannot keep
      // rendering the previous chapter after the identity changes.
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapterFuture = _loadChapter(widget.chapterId);
      unawaited(_recordInitialViewLog());
    }
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return FutureBuilder<ChapterResponse>(
      future: _chapterFuture,
      builder: (BuildContext context, AsyncSnapshot<ChapterResponse> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: ContentError(
              onRefresh: () async {
                if (!mounted) {
                  return;
                }
                // 阅读器可能来自在线漫画或本地下载，重试必须沿用注入的章节加载器。
                _load();
              },
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(),
            body: const ContentLoading(),
          );
        }
        final chapter = snapshot.requireData;
        final imageCount = chapter.images.length;
        if (imageCount == 0) {
          // Do not construct any reader implementation for an empty chapter:
          // Gallery/PhotoView controllers may assert on an empty page list,
          // while list readers have no meaningful page to restore.
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.noContentAvailable),
                  TextButton(
                    onPressed: _load,
                    child: Text(context.l10n.tr('重试', en: 'Retry')),
                  ),
                ],
              ),
            ),
          );
        }
        final safeStartIndex = widget.initRank.clamp(0, imageCount - 1).toInt();
        final screen = Scaffold(
          backgroundColor: Colors.black,
          body: _ComicReader(
            comicId: widget.comic.id,
            chapter: chapter,
            startIndex: safeStartIndex,
            key: ValueKey(
              'reader_${widget.comic.id}_${chapter.id}_$_readerType'
              '_${_readerDirection}_${widget.fullScreenOnInit}_$safeStartIndex'
              '_${identityHashCode(chapter)}',
            ),
            reload: (int index, bool fullScreen) => _replaceReaderRoute(
              chapterId: widget.chapterId,
              initRank: index,
              fullScreen: fullScreen,
            ),
            onChangeEp: (int id, bool fullScreen) => _replaceReaderRoute(
              chapterId: id,
              initRank: 0,
              fullScreen: fullScreen,
            ),
            readerType: _readerType,
            readerDirection: _readerDirection,
            fullScreenOnInit: widget.fullScreenOnInit,
          ),
        );
        return readerKeyboardHolder(screen);
      },
    );
  }
}

////////////////////////////////

// Android only.
// Listen to hardware volume keys and map them to reader controls.
// Only the latest listener is active.
// Event values may be DOWN/UP.

var _volumeListenCount = 0;

void _onVolumeEvent(dynamic args) {
  _readerControllerEvent.broadcast(_ReaderControllerEventArgs("$args"));
}

EventChannel volumeButtonChannel = const EventChannel("volume_button");
StreamSubscription? volumeS;

void addVolumeListen() {
  if (!Platform.isAndroid) {
    return;
  }
  _volumeListenCount++;
  if (_volumeListenCount == 1) {
    volumeS =
        volumeButtonChannel.receiveBroadcastStream().listen(_onVolumeEvent);
  }
}

void delVolumeListen() {
  if (!Platform.isAndroid || _volumeListenCount <= 0) {
    return;
  }
  _volumeListenCount--;
  if (_volumeListenCount == 0) {
    final subscription = volumeS;
    volumeS = null;
    subscription?.cancel();
  }
}

Widget readerKeyboardHolder(Widget widget) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return _ReaderKeyboardHolder(child: widget);
  }
  return widget;
}

class _ReaderKeyboardHolder extends StatefulWidget {
  final Widget child;

  const _ReaderKeyboardHolder({required this.child, Key? key})
      : super(key: key);

  @override
  State<_ReaderKeyboardHolder> createState() => _ReaderKeyboardHolderState();
}

class _ReaderKeyboardHolderState extends State<_ReaderKeyboardHolder> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'comic-reader-keyboard');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _focusNode,
      child: widget.child,
      autofocus: true,
      onKey: (event) {
        if (event is RawKeyDownEvent) {
          if (event.isKeyPressed(LogicalKeyboardKey.arrowUp)) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("UP"));
          }
          if (event.isKeyPressed(LogicalKeyboardKey.arrowDown)) {
            _readerControllerEvent
                .broadcast(_ReaderControllerEventArgs("DOWN"));
          }
        }
      },
    );
  }
}

////////////////////////////////

Event<_ReaderControllerEventArgs> _readerControllerEvent =
    Event<_ReaderControllerEventArgs>();

List<Series> _sortReaderSeries(Iterable<Series> source) {
  final indexed = source.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final aSort = int.tryParse(a.value.sort.trim());
    final bSort = int.tryParse(b.value.sort.trim());
    if (aSort != null && bSort != null) {
      final result = aSort.compareTo(bSort);
      if (result != 0) {
        return result;
      }
    } else if (aSort != null) {
      return -1;
    } else if (bSort != null) {
      return 1;
    } else {
      final result = a.value.sort.trim().compareTo(b.value.sort.trim());
      if (result != 0) {
        return result;
      }
    }
    // Keep duplicate/invalid sort values deterministic without changing the
    // server-provided order unnecessarily.
    return a.key.compareTo(b.key);
  });
  return indexed.map((entry) => entry.value).toList(growable: false);
}

class _ReaderControllerEventArgs extends EventArgs {
  final String key;

  _ReaderControllerEventArgs(this.key);
}

class _ComicReader extends StatefulWidget {
  final int comicId;
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) reload;
  final FutureOr Function(int, bool) onChangeEp;
  final int startIndex;
  final ReaderType readerType;
  final ReaderDirection readerDirection;
  final bool fullScreenOnInit;

  const _ComicReader({
    required this.comicId,
    required this.chapter,
    required this.reload,
    required this.onChangeEp,
    required this.startIndex,
    required this.readerType,
    required this.readerDirection,
    required this.fullScreenOnInit,
    Key? key,
  }) : super(key: key);

  @override
  // ignore: no_logic_in_create_state
  State<StatefulWidget> createState() {
    switch (readerType) {
      case ReaderType.webtoon:
        return _ComicReaderWebToonState();
      case ReaderType.gallery:
        return _ComicReaderGalleryState();
      case ReaderType.webToonFreeZoom:
        return readerDirection == ReaderDirection.topToBottom
            ? _ListViewReaderState()
            : _FreeZoomPagedReaderState();
      case ReaderType.twoPageGallery:
        return _TwoPageGalleryReaderState();
    }
  }
}

abstract class _ComicReaderState extends State<_ComicReader> {
  final ReaderSession _readerSession = ReaderSession();
  ReaderGeneration? _readerGeneration;

  /// Source-neutral page metadata; legacy `chapter.images` remains the
  /// rendering source until the repository-backed pipeline is enabled.
  List<PageDescriptor> _pageDescriptors = const <PageDescriptor>[];
  static const int _uiSyncMinIntervalMs = 80;
  bool _sliderDragging = false;
  Widget _buildViewer();

  _needJumpTo(int pageIndex, bool animation);

  /// Resolve a page provider using the current reader layout when the target
  /// decode experiment is enabled.  Keeping this helper in the common state
  /// makes Gallery, free-zoom and two-page prefetch use identical cache-key
  /// semantics while the legacy path remains a one-line rollback.
  PageImageProvider _readerPageProvider(
    int index, {
    double? width,
    double? height,
  }) {
    final imageName = index < _pageDescriptors.length
        ? _pageDescriptors[index].name
        : widget.chapter.images[index];
    final safeWidth =
        width ?? (mounted ? MediaQuery.maybeSizeOf(context)?.width : null);
    return readerPageImageProvider(
      context,
      widget.chapter.id,
      imageName,
      width: safeWidth,
      height: height,
      enabled: readerTargetDecodeV1,
    );
  }

  /// Preloading is opportunistic: a failed neighbour must never turn into a
  /// current-page error or an unhandled Future. Keep the context access behind
  /// a mounted check because several callers are post-frame callbacks.
  void _precacheReaderImage(ImageProvider provider) {
    if (!mounted) {
      return;
    }
    try {
      final generation = _readerGeneration;
      final future = precacheImage(provider, context);
      unawaited(
        future.catchError((Object error, StackTrace _) {
          // Do not log URLs or signed parameters; the type is enough for
          // local diagnostics and keeps prefetch failures low-noise.
          debugPrient("reader prefetch failed: ${error.runtimeType}");
        }),
      );
      // Prefetch is opportunistic; retain the generation capture so future
      // callers can gate publication when this path is adopted by a loader.
      if (generation != null && !_readerSession.isCurrent(generation)) {
        return;
      }
    } catch (error) {
      debugPrient("reader prefetch failed: ${error.runtimeType}");
    }
  }

  late bool _fullScreen;
  late int _current;
  late int _slider;
  List<int> _sortedSeriesIds = const <int>[];
  int? _nextEpId;
  Timer? _viewLogDebounce;
  int? _pendingViewLogPage;
  int _lastUiSyncMs = 0;
  bool _didAddVolumeListen = false;

  void _persistViewLog(int index) {
    methods
        .updateViewLog(
      widget.comicId,
      widget.chapter.id,
      index,
    )
        .catchError((e, st) {
      debugPrient("$e\n$st");
    });
  }

  void _schedulePersistViewLog(int index) {
    _pendingViewLogPage = index;
    _viewLogDebounce?.cancel();
    _viewLogDebounce = Timer(
      const Duration(milliseconds: 220),
      _flushViewLogPersist,
    );
  }

  void _flushViewLogPersist() {
    final page = _pendingViewLogPage;
    if (page == null) {
      return;
    }
    _pendingViewLogPage = null;
    _persistViewLog(page);
  }

  void _rebuildSeriesCache() {
    if (widget.chapter.series.isEmpty) {
      _sortedSeriesIds = const <int>[];
      _nextEpId = null;
      return;
    }
    final entries = _sortReaderSeries(widget.chapter.series);
    _sortedSeriesIds = entries.map((e) => e.id).toList(growable: false);
    final index = _sortedSeriesIds.indexOf(widget.chapter.id);
    if (index >= 0 && index < _sortedSeriesIds.length - 1) {
      _nextEpId = _sortedSeriesIds[index + 1];
    } else {
      _nextEpId = null;
    }
  }

  Future _onFullScreenChange(bool fullScreen) async {
    if (!mounted) {
      return;
    }
    setState(() {
      if (Platform.isAndroid || Platform.isIOS) {
        if (fullScreen) {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [],
          );
        } else {
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.edgeToEdge,
            overlays: SystemUiOverlay.values,
          );
        }
      }
      _fullScreen = fullScreen;
    });
  }

  void _onCurrentChange(int index, {bool forceUiSync = false}) {
    if (!mounted || widget.chapter.images.isEmpty) {
      return;
    }
    final safeIndex = index.clamp(0, widget.chapter.images.length - 1).toInt();
    if (safeIndex == _current) {
      return;
    }
    _current = safeIndex;
    _slider = safeIndex;
    _schedulePersistViewLog(safeIndex);
    final now = DateTime.now().millisecondsSinceEpoch;
    final isEdge =
        safeIndex <= 0 || safeIndex >= widget.chapter.images.length - 1;
    if (forceUiSync || isEdge || now - _lastUiSyncMs >= _uiSyncMinIntervalMs) {
      _lastUiSyncMs = now;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _fullScreen = widget.fullScreenOnInit;
    if (_fullScreen) {
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(
          // Keep the initial state consistent with the interactive toggle:
          // fullscreen must hide system overlays.  The previous
          // edge-to-edge call left status/navigation bars visible on mobile,
          // so a route opened with fullScreenOnInit was not actually full
          // screen.
          SystemUiMode.manual,
          overlays: const <SystemUiOverlay>[],
        );
      }
    }
    final imageCount = widget.chapter.images.length;
    final safeStartIndex = imageCount == 0
        ? 0
        : widget.startIndex.clamp(0, imageCount - 1).toInt();
    _current = safeStartIndex;
    _slider = safeStartIndex;
    _readerControllerEvent.subscribe(_onPageControl);
    if (Platform.isAndroid && currentVolumeKeyControl()) {
      addVolumeListen();
      _didAddVolumeListen = true;
    }
    _rebuildSeriesCache();
    _pageDescriptors = ReaderPageRepository.fromOnline(widget.chapter.images);
    _readerGeneration = _readerSession.openChapter(
      ChapterIdentity(widget.chapter.id.toString()),
    );
  }

  @override
  void didUpdateWidget(covariant _ComicReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chapter, widget.chapter)) {
      _readerGeneration = _readerSession.openChapter(
        ChapterIdentity(widget.chapter.id.toString()),
      );
      _pageDescriptors = ReaderPageRepository.fromOnline(widget.chapter.images);
      _rebuildSeriesCache();
    }
  }

  @override
  void dispose() {
    _viewLogDebounce?.cancel();
    _readerSession.close();
    _flushViewLogPersist();
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (_didAddVolumeListen) {
      delVolumeListen();
      _didAddVolumeListen = false;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  void _onPageControl(_ReaderControllerEventArgs? args) {
    if (!mounted || args == null || widget.chapter.images.isEmpty) {
      return;
    }
    var event = args.key;
    switch (event) {
      case "UP":
        if (_current > 0) {
          _needJumpTo(_current - 1, !currentNoAnimation());
        }
        break;
      case "DOWN":
        if (_current < widget.chapter.images.length - 1) {
          _needJumpTo(_current + 1, !currentNoAnimation());
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (currentReaderControllerType) {
      // controls
      case ReaderControllerType.controller:
        return Stack(
          children: [
            _buildViewer(),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(_buildFullScreenControllerStackItem()),
          ],
        );
      case ReaderControllerType.touchOnce:
        return Stack(
          children: [
            _buildTouchOnceControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.touchDouble:
        return Stack(
          children: [
            _buildTouchDoubleControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.touchDoubleOnceNext:
        return Stack(
          children: [
            _buildTouchDoubleOnceNextControllerAction(_buildViewer()),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(null),
          ],
        );
      case ReaderControllerType.threeArea:
        return Stack(
          children: [
            _buildViewer(),
            if (_sliderDragging) _sliderDraggingText(),
            _buildBar(_buildThreeAreaControllerAction()),
          ],
        );
    }
  }

  Widget _sliderDraggingText() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0x88000000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${_slider + 1} / ${widget.chapter.images.length}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenControllerStackItem() {
    if (currentReaderSliderPosition == ReaderSliderPosition.bottom &&
        !_fullScreen) {
      return Container();
    }
    if (ReaderSliderPosition.right == currentReaderSliderPosition) {
      return SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding:
                  const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
                color: Color(0x88000000),
              ),
              child: GestureDetector(
                onTap: () {
                  _onFullScreenChange(!_fullScreen);
                },
                child: Icon(
                  _fullScreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen_outlined,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SafeArea(
        child: Align(
      alignment: Alignment.bottomLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(10),
              bottomRight: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              _onFullScreenChange(!_fullScreen);
            },
            child: Icon(
              _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen_outlined,
              size: 30,
              color: Colors.white,
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildTouchOnceControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildTouchDoubleControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildTouchDoubleOnceNextControllerAction(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _readerControllerEvent.broadcast(_ReaderControllerEventArgs("DOWN"));
      },
      onDoubleTap: () {
        _onFullScreenChange(!_fullScreen);
      },
      child: child,
    );
  }

  Widget _buildThreeAreaControllerAction() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        var up = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("UP"));
            },
            child: Container(),
          ),
        );
        var down = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _readerControllerEvent
                  .broadcast(_ReaderControllerEventArgs("DOWN"));
            },
            child: Container(),
          ),
        );
        var fullScreen = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _onFullScreenChange(!_fullScreen),
            child: Container(),
          ),
        );
        late Widget child;
        switch (currentReaderDirection) {
          case ReaderDirection.topToBottom:
            child = Column(children: [
              up,
              fullScreen,
              down,
            ]);
            break;
          case ReaderDirection.leftToRight:
            child = Row(children: [
              up,
              fullScreen,
              down,
            ]);
            break;
          case ReaderDirection.rightToLeft:
            child = Row(children: [
              down,
              fullScreen,
              up,
            ]);
            break;
        }
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: child,
        );
      },
    );
  }

  Widget _buildBar(Widget? child) {
    switch (currentReaderSliderPosition) {
      case ReaderSliderPosition.bottom:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(child: child ?? Container()),
            _fullScreen
                ? Container()
                : Container(
                    height: 45,
                    color: const Color(0x88000000),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(width: 15),
                        IconButton(
                          icon: const Icon(Icons.fullscreen),
                          color: Colors.white,
                          onPressed: () {
                            _onFullScreenChange(!_fullScreen);
                          },
                        ),
                        Container(width: 10),
                        Expanded(
                          child: _buildSliderBottom(),
                        ),
                        Container(width: 10),
                        IconButton(
                          icon: const Icon(Icons.skip_next_outlined),
                          color: Colors.white,
                          onPressed: _onNextAction,
                        ),
                        Container(width: 15),
                      ],
                    ),
                  ),
            _fullScreen
                ? Container()
                : Container(
                    color: const Color(0x88000000),
                    child: SafeArea(
                      top: false,
                      child: Container(),
                    ),
                  ),
          ],
        );
      case ReaderSliderPosition.right:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  ...child == null ? [] : [child],
                  _buildSliderRight(),
                ],
              ),
            ),
          ],
        );
      case ReaderSliderPosition.left:
        return Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  ...child == null ? [] : [child],
                  _buildSliderLeft(),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _buildAppBar() => _fullScreen
      ? Container()
      : AppBar(
          title: Text(widget.chapter.name),
          actions: [
            IconButton(
              onPressed: _onChooseEp,
              icon: const Icon(Icons.menu_open),
            ),
            IconButton(
              onPressed: _onMoreSetting,
              icon: const Icon(Icons.more_horiz),
            ),
          ],
        );

  Widget _buildSliderBottom() {
    return Column(
      children: [
        Expanded(child: Container()),
        SizedBox(
          height: 25,
          child: _buildSliderWidget(Axis.horizontal),
        ),
        Expanded(child: Container()),
      ],
    );
  }

  Widget _buildSliderLeft() => _fullScreen
      ? Container()
      : Align(
          alignment: Alignment.centerLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 35,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.only(top: 10, bottom: 10, left: 6, right: 5),
              child: Center(
                child: _buildSliderWidget(Axis.vertical),
              ),
            ),
          ),
        );

  Widget _buildSliderRight() => _fullScreen
      ? Container()
      : Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 35,
              height: 300,
              decoration: const BoxDecoration(
                color: Color(0x66000000),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
              padding:
                  const EdgeInsets.only(top: 10, bottom: 10, left: 5, right: 6),
              child: Center(
                child: _buildSliderWidget(Axis.vertical),
              ),
            ),
          ),
        );

  Widget _buildSliderWidget(Axis axis) {
    final imageCount = widget.chapter.images.length;
    if (imageCount <= 1) {
      return const SizedBox.shrink();
    }
    final maxIndex = imageCount - 1;
    final sliderValue = _slider.clamp(0, maxIndex);

    return FlutterSlider(
      axis: axis,
      values: [sliderValue.toDouble()],
      min: 0,
      max: maxIndex.toDouble(),
      onDragging: (handlerIndex, lowerValue, upperValue) {
        final next = lowerValue.toInt();
        if (next == _slider) {
          return;
        }
        _slider = next;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastUiSyncMs >= 40 && mounted) {
          _lastUiSyncMs = now;
          setState(() {});
        }
      },
      onDragCompleted: (handlerIndex, lowerValue, upperValue) {
        _sliderDragging = false;
        _slider = lowerValue.toInt();
        if (mounted) {
          setState(() {});
        }
        if (_slider != _current) {
          _needJumpTo(_slider, false);
        }
      },
      onDragStarted: (handlerIndex, lowerValue, upperValue) {
        if (!_sliderDragging && mounted) {
          setState(() {
            _sliderDragging = true;
          });
        }
      },
      trackBar: FlutterSliderTrackBar(
        inactiveTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade300,
        ),
        activeTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      step: const FlutterSliderStep(
        step: 1,
        isPercentRange: false,
      ),
      tooltip: FlutterSliderTooltip(disabled: true),
    );
  }

  Future _onChooseEp() async {
    showMaterialModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xAA000000),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * (.45),
          child: _EpChooser(widget.chapter, widget.onChangeEp),
        );
      },
    );
  }

  //
  _onMoreSetting() async {
    await showMaterialModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xAA000000),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height / 2,
          child: _SettingPanel(),
        );
      },
    );
    if (!mounted) {
      return;
    }
    if (widget.readerDirection != currentReaderDirection ||
        widget.readerType != currentReaderType) {
      widget.reload(_current, _fullScreen);
    } else {
      setState(() {});
    }
  }

  //
  double _appBarHeight() {
    return Scaffold.of(context).appBarMaxHeight ?? 0;
  }

  double _bottomBarHeight() {
    return 45;
  }

  bool _fullscreenController() {
    switch (currentReaderControllerType) {
      case ReaderControllerType.touchOnce:
        return false;
      case ReaderControllerType.controller:
        return false;
      case ReaderControllerType.touchDouble:
        return false;
      case ReaderControllerType.touchDoubleOnceNext:
        return false;
      case ReaderControllerType.threeArea:
        return true;
    }
  }

  bool _hasNextEp() {
    return _nextEpId != null;
  }

  void _onNextAction() {
    final nextId = _nextEpId;
    if (nextId == null) {
      defaultToast(
        context,
        context.l10n.tr("已经到头了", en: "You have reached the end"),
      );
      return;
    }
    widget.onChangeEp(nextId, _fullScreen);
  }
}

class _EpChooser extends StatefulWidget {
  final ChapterResponse chapter;
  final FutureOr Function(int, bool) onChangeEp;

  const _EpChooser(this.chapter, this.onChangeEp);

  @override
  State<StatefulWidget> createState() => _EpChooserState();
}

class _EpChooserState extends State<_EpChooser> {
  @override
  Widget build(BuildContext context) {
    if (widget.chapter.series.isEmpty) {
      return Center(
        child: Text(
          context.l10n.tr("无章节可选择", en: "No chapters available"),
          style: const TextStyle(color: Colors.white),
        ),
      );
    }

    var entries = _sortReaderSeries(widget.chapter.series);
    var widgets = [
      Container(height: 20),
      ...entries.map((e) {
        return Container(
          margin: const EdgeInsets.only(left: 15, right: 15, top: 5, bottom: 5),
          decoration: BoxDecoration(
            color:
                widget.chapter.id == e.id ? Colors.grey.withAlpha(100) : null,
            border: Border.all(
              color: const Color(0xff484c60),
              style: BorderStyle.solid,
              width: .5,
            ),
          ),
          child: MaterialButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onChangeEp(e.id, false);
            },
            textColor: Colors.white,
            child: Text(e.sort + (e.name == "" ? "" : (" - ${e.name}"))),
          ),
        );
      })
    ];
    final index = entries.map((e) => e.id).toList().indexOf(widget.chapter.id);
    return ScrollablePositionedList.builder(
      initialScrollIndex: index < 2 ? 0 : index - 2,
      itemCount: widgets.length,
      itemBuilder: (BuildContext context, int index) => widgets[index],
    );
  }
}

class _SettingPanel extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => _SettingPanelState();
}

class _SettingPanelState extends State<_SettingPanel> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Row(
          children: [
            _bottomIcon(
              icon: Icons.crop_sharp,
              title: readerDirectionName(currentReaderDirection, context),
              onPressed: () async {
                await chooseReaderDirection(context);
                setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              title: readerTypeName(currentReaderType, context),
              onPressed: () async {
                await chooseReaderType(context);
                setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.control_camera_outlined,
              title: currentReaderControllerTypeName(context),
              onPressed: () async {
                await chooseReaderControllerType(context);
                setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.straighten_sharp,
              title: currentReaderSliderPositionName(context),
              onPressed: () async {
                await chooseReaderSliderPosition(context);
                setState(() {});
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _bottomIcon({
    required IconData icon,
    required String title,
    required void Function() onPressed,
  }) {
    return Expanded(
      child: Center(
        child: Column(
          children: [
            IconButton(
              iconSize: 55,
              icon: Column(
                children: [
                  Container(height: 3),
                  Icon(
                    icon,
                    size: 25,
                    color: Colors.white,
                  ),
                  Container(height: 3),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                  Container(height: 3),
                ],
              ),
              onPressed: onPressed,
            )
          ],
        ),
      ),
    );
  }
}

class _ComicReaderWebToonState extends _ComicReaderState {
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  late final List<Size?> _trueSizes = [];
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _itemPositionsListener;
  bool _trueSizeRefreshQueued = false;
  int _lastScrollUiSyncMs = 0;

  @override
  void initState() {
    super.initState();
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onListCurrentChange);
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onListCurrentChange);
    super.dispose();
  }

  void _onListCurrentChange() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrollUiSyncMs < 50) {
      return;
    }
    _lastScrollUiSyncMs = now;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return;
    }
    final visible = positions
        .where((item) =>
            item.itemTrailingEdge > 0 &&
            item.index >= 0 &&
            item.index < widget.chapter.images.length)
        .toList();
    if (visible.isEmpty) {
      return;
    }
    visible.sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    super._onCurrentChange(visible.first.index);
  }

  Size _renderSizeFor(BoxConstraints constraints, int index) {
    final trueSize = _trueSizes[index];
    if (trueSize != null) {
      if (widget.readerDirection == ReaderDirection.topToBottom) {
        return Size(
          constraints.maxWidth,
          constraints.maxWidth * trueSize.height / trueSize.width,
        );
      }
      final maxHeight = constraints.maxHeight -
          super._appBarHeight() -
          super._bottomBarHeight() -
          MediaQuery.of(context).padding.bottom;
      return Size(
        maxHeight * trueSize.width / trueSize.height,
        maxHeight,
      );
    }
    if (widget.readerDirection == ReaderDirection.topToBottom) {
      return Size(constraints.maxWidth, constraints.maxWidth / 2);
    }
    return Size(constraints.maxWidth / 2, constraints.maxHeight);
  }

  void _onTrueSize(int index, Size size) {
    if (index < 0 || index >= _trueSizes.length) {
      return;
    }
    final previous = _trueSizes[index];
    if (previous != null &&
        previous.width == size.width &&
        previous.height == size.height) {
      return;
    }
    if (!mounted) {
      return;
    }
    _trueSizes[index] = size;
    _scheduleTrueSizeRefresh();
  }

  void _scheduleTrueSizeRefresh() {
    if (_trueSizeRefreshQueued) {
      return;
    }
    _trueSizeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trueSizeRefreshQueued = false;
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void _needJumpTo(int index, bool animation) {
    if (index < 0 || index >= widget.chapter.images.length) {
      return;
    }
    if (animation) {
      if (DateTime.now().millisecondsSinceEpoch < _controllerTime) {
        return;
      }
      _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
      _itemScrollController.scrollTo(
        index: index, // jump to target index
        duration: const Duration(milliseconds: 400),
      );
    } else {
      _itemScrollController.jumpTo(
        index: index,
      );
    }
    super._onCurrentChange(index, forceUiSync: true);
  }

  @override
  Widget _buildViewer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: _buildList(),
    );
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return ScrollablePositionedList.builder(
          initialScrollIndex: widget.startIndex,
          scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: widget.readerDirection == ReaderDirection.rightToLeft,
          padding: EdgeInsets.only(
            // Keep top spacing in all modes and directions.
            top: super._appBarHeight(),
            bottom: widget.readerDirection == ReaderDirection.topToBottom
                ? 130 // Keep fixed bottom blank area for vertical mode.
                : (super._bottomBarHeight() +
                    MediaQuery.of(context).padding.bottom)
            // Non-fullscreen mode uses bar heights to keep visual balance.
            ,
          ),
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          itemCount: widget.chapter.images.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (widget.chapter.images.length == index) {
              return _buildNextEp();
            }
            final renderSize = _renderSizeFor(constraints, index);
            return RepaintBoundary(
              child: JMPageImage(
                key: ValueKey(
                    "wt_${widget.chapter.id}_${widget.chapter.images[index]}"),
                widget.chapter.id,
                widget.chapter.images[index],
                width: renderSize.width,
                height: renderSize.height,
                onTrueSize: (size) => _onTrueSize(index, size),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(20),
      child: MaterialButton(
        onPressed: () {
          if (super._hasNextEp()) {
            super._onNextAction();
          } else {
            Navigator.of(context).pop();
          }
        },
        textColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.only(top: 40, bottom: 40),
          child: Text(
            super._hasNextEp()
                ? context.l10n.tr('下一章', en: 'Next chapter')
                : context.l10n.tr('结束阅读', en: 'Finish reading'),
          ),
        ),
      ),
    );
  }
}

class _ComicReaderGalleryState extends _ComicReaderState {
  late PageController _pageController;
  final Map<int, int> _reloadKeys = {}; // Track reload count per page.

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.startIndex);
    _preloadJump(widget.startIndex, init: true);
  }

  void _reloadImage(int index) {
    if (mounted && index >= 0 && index < widget.chapter.images.length) {
      // Clear image cache for this page.
      final oldProvider =
          PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
      evictPageImageMemoryCache(
          widget.chapter.id, widget.chapter.images[index]);
      imageCache.evict(oldProvider);
      imageCache.evict(_readerPageProvider(index));
      debugPrient("evict ${widget.chapter.images[index]}");
      setState(() {
        _reloadKeys[index] = (_reloadKeys[index] ?? 0) + 1;
      });
    }
  }

  Widget _buildGallery() {
    return PhotoViewGallery.builder(
      scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: widget.readerDirection == ReaderDirection.rightToLeft,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return buildLoading(
              context, constraints.maxWidth, constraints.maxHeight);
        },
      ),
      pageController: _pageController,
      onPageChanged: _onGalleryPageChange,
      itemCount: widget.chapter.images.length,
      allowImplicitScrolling: true,
      builder: (BuildContext context, int index) {
        final reloadKey = _reloadKeys[index] ?? 0;

        return PhotoViewGalleryPageOptions.customChild(
          disableGestures:
              currentReaderControllerType == ReaderControllerType.touchDouble ||
                  currentReaderControllerType ==
                      ReaderControllerType.touchDoubleOnceNext,
          child: LayoutBuilder(
            key: ValueKey(
                'page_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey'),
            builder: (BuildContext context, BoxConstraints constraints) {
              final imageProvider = _readerPageProvider(
                index,
                // Width-only target preserves the source aspect ratio and
                // leaves zoom gestures free to use the explicit full-size
                // fallback when the experiment is disabled.
                width: constraints.maxWidth,
              );
              return Image(
                key: ValueKey(
                    'image_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey'),
                image: imageProvider,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return buildLoading(
                    context,
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                },
                errorBuilder: (b, e, s) {
                  debugPrient("$e,$s");
                  return buildError(
                    context,
                    constraints.maxWidth,
                    constraints.maxHeight,
                    onReload: () => _reloadImage(index),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget _buildViewer() {
    return Column(
      children: [
        Container(height: _fullScreen ? 0 : super._appBarHeight()),
        Expanded(
          child: Stack(
            children: [
              _buildGallery(),
              _buildNextEpController(),
            ],
          ),
        ),
        Container(height: _fullScreen ? 0 : super._bottomBarHeight()),
      ],
    );
  }

  @override
  _needJumpTo(int pageIndex, bool animation) {
    if (pageIndex < 0 || pageIndex >= widget.chapter.images.length) {
      return;
    }
    if (animation) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    } else {
      _pageController.jumpToPage(pageIndex);
    }
    _preloadJump(pageIndex);
    super._onCurrentChange(pageIndex, forceUiSync: true);
  }

  void _onGalleryPageChange(int to) {
    if (!mounted || to < 0 || to >= widget.chapter.images.length) {
      return;
    }
    var toIndex = to;
    // Preload nearby pages.
    for (var i = toIndex + 1;
        i < toIndex + 3 && i < widget.chapter.images.length;
        i++) {
      final ip = _readerPageProvider(i);
      _precacheReaderImage(ip);
    }
    // Preload nearby pages.
    super._onCurrentChange(to);
  }

  _preloadJump(int index, {bool init = false}) {
    fn() {
      if (!mounted) {
        return;
      }
      for (var i = index - 1; i < index + 3; i++) {
        if (i < 0 || i >= widget.chapter.images.length) continue;
        final ip = _readerPageProvider(i);
        _precacheReaderImage(ip);
      }
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    } else {
      fn();
    }
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController()) {
      return Container();
    }
    if (_current < widget.chapter.images.length - 1) return Container();
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              if (super._hasNextEp()) {
                super._onNextAction();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              super._hasNextEp()
                  ? context.l10n.tr('下一章', en: 'Next chapter')
                  : context.l10n.tr('结束阅读', en: 'Finish reading'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _FreeZoomPagedReaderState extends _ComicReaderState {
  late final PageController _pageController;
  final Map<int, int> _reloadKeys = {};
  final Map<int, PhotoViewController> _photoControllers = {};
  final Map<int, PhotoViewScaleStateController> _scaleControllers = {};
  final Map<int, double> _baseScaleByPage = {};
  StreamSubscription<PhotoViewControllerValue>? _zoomSubscription;
  int _subscribedPage = -1;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.startIndex);
    _bindZoomListener(widget.startIndex);
    _preloadAround(widget.startIndex, init: true);
  }

  @override
  void dispose() {
    _zoomSubscription?.cancel();
    for (final controller in _photoControllers.values) {
      controller.dispose();
    }
    for (final controller in _scaleControllers.values) {
      controller.dispose();
    }
    _photoControllers.clear();
    _scaleControllers.clear();
    _baseScaleByPage.clear();
    _pageController.dispose();
    super.dispose();
  }

  PhotoViewController _photoControllerFor(int index) {
    return _photoControllers.putIfAbsent(index, () => PhotoViewController());
  }

  PhotoViewScaleStateController _scaleControllerFor(int index) {
    return _scaleControllers.putIfAbsent(
      index,
      () => PhotoViewScaleStateController(),
    );
  }

  void _setZoomed(bool value) {
    if (_isZoomed == value || !mounted) {
      return;
    }
    setState(() {
      _isZoomed = value;
    });
  }

  void _bindZoomListener(int index) {
    if (_subscribedPage == index) {
      return;
    }
    _zoomSubscription?.cancel();
    _subscribedPage = index;
    final controller = _photoControllerFor(index);
    _zoomSubscription = controller.outputStateStream.listen((state) {
      final scale = state.scale;
      if (scale == null) {
        _setZoomed(false);
        return;
      }
      final base = _baseScaleByPage.putIfAbsent(index, () => scale);
      _setZoomed(scale > base * 1.01);
    });
    final currentScale = controller.scale;
    if (currentScale == null) {
      _setZoomed(false);
    } else {
      final base = _baseScaleByPage.putIfAbsent(index, () => currentScale);
      _setZoomed(currentScale > base * 1.01);
    }
  }

  void _resetZoomFor(int index) {
    final controller = _photoControllers[index];
    final scaleStateController = _scaleControllers[index];
    if (scaleStateController != null) {
      scaleStateController.scaleState = PhotoViewScaleState.initial;
    }
    if (controller != null) {
      controller.reset();
      controller.position = Offset.zero;
    }
    _setZoomed(false);
  }

  void _reloadImage(int index) {
    if (!mounted || index < 0 || index >= widget.chapter.images.length) {
      return;
    }
    final oldProvider =
        PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
    evictPageImageMemoryCache(widget.chapter.id, widget.chapter.images[index]);
    imageCache.evict(oldProvider);
    imageCache.evict(_readerPageProvider(index));
    setState(() {
      _reloadKeys[index] = (_reloadKeys[index] ?? 0) + 1;
      _resetZoomFor(index);
      _baseScaleByPage.remove(index);
    });
  }

  @override
  void _needJumpTo(int pageIndex, bool animation) {
    if (pageIndex < 0 || pageIndex >= widget.chapter.images.length) {
      return;
    }
    _resetZoomFor(_current);
    _bindZoomListener(pageIndex);
    if (animation && !currentNoAnimation()) {
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    } else {
      _pageController.jumpToPage(pageIndex);
    }
    _preloadAround(pageIndex);
    super._onCurrentChange(pageIndex, forceUiSync: true);
  }

  void _onGalleryPageChange(int to) {
    if (!mounted || to < 0 || to >= widget.chapter.images.length) {
      return;
    }
    _resetZoomFor(_current);
    _bindZoomListener(to);
    _preloadAround(to);
    super._onCurrentChange(to);
  }

  void _preloadAround(int index, {bool init = false}) {
    void run() {
      if (!mounted) {
        return;
      }
      for (var i = index - 1; i < index + 3; i++) {
        if (i < 0 || i >= widget.chapter.images.length) {
          continue;
        }
        final provider = _readerPageProvider(i);
        _precacheReaderImage(provider);
      }
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    } else {
      run();
    }
  }

  Widget _buildGallery() {
    return PhotoViewGallery.builder(
      scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: widget.readerDirection == ReaderDirection.rightToLeft,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (context, event) => LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return buildLoading(
            context,
            constraints.maxWidth,
            constraints.maxHeight,
          );
        },
      ),
      pageController: _pageController,
      onPageChanged: _onGalleryPageChange,
      itemCount: widget.chapter.images.length,
      allowImplicitScrolling: true,
      scrollPhysics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      builder: (BuildContext context, int index) {
        final reloadKey = _reloadKeys[index] ?? 0;
        return PhotoViewGalleryPageOptions.customChild(
          disableGestures:
              currentReaderControllerType == ReaderControllerType.touchDouble ||
                  currentReaderControllerType ==
                      ReaderControllerType.touchDoubleOnceNext,
          controller: _photoControllerFor(index),
          scaleStateController: _scaleControllerFor(index),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.contained * 4.0,
          basePosition: Alignment.center,
          tightMode: true,
          child: LayoutBuilder(
            key: ValueKey(
              'fz_page_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey',
            ),
            builder: (BuildContext context, BoxConstraints constraints) {
              final imageProvider = _readerPageProvider(
                index,
                width: constraints.maxWidth,
              );
              return SizedBox.expand(
                child: Image(
                  key: ValueKey(
                    'fz_image_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey',
                  ),
                  image: imageProvider,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return buildLoading(
                      context,
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                  },
                  errorBuilder: (b, e, s) {
                    debugPrient("$e,$s");
                    return buildError(
                      context,
                      constraints.maxWidth,
                      constraints.maxHeight,
                      onReload: () => _reloadImage(index),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget _buildViewer() {
    return Column(
      children: [
        Container(height: _fullScreen ? 0 : super._appBarHeight()),
        Expanded(
          child: Stack(
            children: [
              _buildGallery(),
              _buildNextEpController(),
            ],
          ),
        ),
        Container(height: _fullScreen ? 0 : super._bottomBarHeight()),
      ],
    );
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController()) {
      return Container();
    }
    if (_current < widget.chapter.images.length - 1) {
      return Container();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              if (super._hasNextEp()) {
                super._onNextAction();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              super._hasNextEp()
                  ? context.l10n.tr('Next chapter', en: 'Next chapter')
                  : context.l10n.tr('Finish reading', en: 'Finish reading'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ListViewReaderState extends _ComicReaderState
    with SingleTickerProviderStateMixin {
  var _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
  var _isZoomed = false;
  var _activePointers = 0;
  final List<Size?> _trueSizes = [];
  final List<GlobalKey> _pageKeys = [];
  bool _trueSizeRefreshQueued = false;
  int _lastScrollUiSyncMs = 0;
  final _transformationController = TransformationController();
  late final ScrollController _scrollController;
  late TapDownDetails _doubleTapDetails;
  late final _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );

  @override
  void initState() {
    super.initState();
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
      _pageKeys.add(GlobalKey());
    }
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);
    _transformationController.addListener(_onTransformChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _needJumpTo(widget.startIndex, false);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.001;
    if (zoomed == _isZoomed || !mounted) {
      return;
    }
    setState(() {
      _isZoomed = zoomed;
    });
  }

  void _onScrollChanged() {
    if (_isZoomed || _activePointers > 1 || !_scrollController.hasClients) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrollUiSyncMs < 50) {
      return;
    }
    _lastScrollUiSyncMs = now;
    final imageCount = widget.chapter.images.length;
    if (imageCount <= 1) {
      super._onCurrentChange(0);
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      super._onCurrentChange(0);
      return;
    }
    final ratio =
        (_scrollController.offset / maxExtent).clamp(0.0, 1.0).toDouble();
    final index = (ratio * (imageCount - 1)).round();
    super._onCurrentChange(index);
  }

  void _onPointerDown(PointerDownEvent event) {
    final hadMultiTouch = _activePointers > 1;
    _activePointers++;
    final hasMultiTouch = _activePointers > 1;
    if (hadMultiTouch != hasMultiTouch && mounted) {
      setState(() {});
    }
  }

  void _onPointerEnd(PointerEvent event) {
    final hadMultiTouch = _activePointers > 1;
    _activePointers = max(0, _activePointers - 1);
    final hasMultiTouch = _activePointers > 1;
    if (hadMultiTouch != hasMultiTouch && mounted) {
      setState(() {});
    }
  }

  @override
  void _needJumpTo(int index, bool animation) {
    if (index < 0 || index >= widget.chapter.images.length) {
      return;
    }
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    }
    final targetContext = _pageKeys[index].currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: animation ? const Duration(milliseconds: 400) : Duration.zero,
        curve: Curves.ease,
      );
      super._onCurrentChange(index, forceUiSync: true);
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return;
    }
    final ratio = widget.chapter.images.length <= 1
        ? 0.0
        : index / (widget.chapter.images.length - 1);
    final target = (maxExtent * ratio).clamp(0.0, maxExtent).toDouble();
    if (animation) {
      if (DateTime.now().millisecondsSinceEpoch < _controllerTime) {
        return;
      }
      _controllerTime = DateTime.now().millisecondsSinceEpoch + 400;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    super._onCurrentChange(index, forceUiSync: true);
  }

  @override
  Widget _buildViewer() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
      ),
      child: _buildList(),
    );
  }

  Size _renderSizeFor(BoxConstraints constraints, int index) {
    final trueSize = _trueSizes[index];
    if (trueSize != null) {
      if (currentReaderDirection == ReaderDirection.topToBottom) {
        return Size(
          constraints.maxWidth,
          constraints.maxWidth * trueSize.height / trueSize.width,
        );
      }
      final maxHeight = constraints.maxHeight -
          super._appBarHeight() -
          (super._fullScreen
              ? super._appBarHeight()
              : super._bottomBarHeight());
      return Size(
        maxHeight * trueSize.width / trueSize.height,
        maxHeight,
      );
    }
    if (currentReaderDirection == ReaderDirection.topToBottom) {
      return Size(constraints.maxWidth, constraints.maxWidth / 2);
    }
    return Size(constraints.maxWidth / 2, constraints.maxHeight);
  }

  void _onTrueSize(int index, Size size) {
    if (index < 0 || index >= _trueSizes.length) {
      return;
    }
    final previous = _trueSizes[index];
    if (previous != null &&
        previous.width == size.width &&
        previous.height == size.height) {
      return;
    }
    if (!mounted) {
      return;
    }
    _trueSizes[index] = size;
    _scheduleTrueSizeRefresh();
  }

  void _scheduleTrueSizeRefresh() {
    if (_trueSizeRefreshQueued) {
      return;
    }
    _trueSizeRefreshQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trueSizeRefreshQueued = false;
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  Widget _buildList() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final giveTouchToViewer = _activePointers > 1;
        var list = ListView.builder(
          controller: _scrollController,
          scrollDirection: currentReaderDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: currentReaderDirection == ReaderDirection.rightToLeft,
          cacheExtent: currentReaderDirection == ReaderDirection.topToBottom
              ? constraints.maxHeight * 2
              : constraints.maxWidth * 2,
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.only(
            // Keep top spacing in all modes and directions.
            top: currentReaderDirection == ReaderDirection.topToBottom
                ? super._appBarHeight()
                : max(super._appBarHeight(), super._bottomBarHeight()),
            bottom: currentReaderDirection == ReaderDirection.topToBottom
                ? 130 // Keep fixed bottom blank area for vertical mode.
                : max(super._appBarHeight(), super._bottomBarHeight()),
          ),
          itemCount: widget.chapter.images.length + 1,
          itemBuilder: (BuildContext context, int index) {
            if (widget.chapter.images.length == index) {
              return _buildNextEp();
            }
            final renderSize = _renderSizeFor(constraints, index);
            return RepaintBoundary(
              child: KeyedSubtree(
                key: _pageKeys[index],
                child: JMPageImage(
                  key: ValueKey(
                      "fz_${widget.chapter.id}_${widget.chapter.images[index]}"),
                  widget.chapter.id,
                  widget.chapter.images[index],
                  width: renderSize.width,
                  height: renderSize.height,
                  onTrueSize: (size) => _onTrueSize(index, size),
                ),
              ),
            );
          },
        );
        var viewer = InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: 2,
          boundaryMargin: EdgeInsets.zero,
          scaleEnabled: true,
          panEnabled: false,
          child: IgnorePointer(
            ignoring: giveTouchToViewer,
            child: list,
          ),
        );
        return Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: GestureDetector(
            onDoubleTap: _handleDoubleTap,
            onDoubleTapDown: _handleDoubleTapDown,
            child: viewer,
          ),
        );
      },
    );
  }

  Widget _buildNextEp() {
    if (super._fullscreenController()) {
      return Container();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      child: MaterialButton(
        onPressed: () {
          if (super._hasNextEp()) {
            super._onNextAction();
          } else {
            Navigator.of(context).pop();
          }
        },
        textColor: Colors.white,
        child: Container(
          padding: const EdgeInsets.only(top: 40, bottom: 40),
          child: Text(
            super._hasNextEp()
                ? context.l10n.tr('下一章', en: 'Next chapter')
                : context.l10n.tr('结束阅读', en: 'Finish reading'),
          ),
        ),
      ),
    );
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_animationController.isAnimating) {
      return;
    }
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      var position = _doubleTapDetails.localPosition;
      var animation = Tween(begin: 0, end: 1.0).animate(_animationController);
      animation.addListener(() {
        _transformationController.value = Matrix4.identity()
          ..translate(
              -position.dx * animation.value, -position.dy * animation.value)
          ..scale(animation.value + 1.0);
      });
      _animationController.forward(from: 0);
    }
  }
}

///////////////////////////////////////////////////////////////////////////////

class _TwoPageGalleryReaderState extends _ComicReaderState {
  late PageController _pageController;
  late final List<Size?> _trueSizes = [];
  List<ImageProvider> ips = [];
  List<PhotoViewGalleryPageOptions> options = [];
  late PhotoViewGallery _view;
  final Map<int, int> _imageProviderKeys = {};

  @override
  void initState() {
    super.initState();
    // Initialize chapter state before using startIndex.
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    _pageController = PageController(initialPage: widget.startIndex ~/ 2);
    for (var index = 0; index < widget.chapter.images.length; index++) {
      _imageProviderKeys[index] = 0;
      ips.add(PageImageProvider(
        widget.chapter.id,
        widget.chapter.images[index],
      ));
    }
    _buildOptions();
    _buildView();
    _preloadJump(widget.startIndex, init: true);
  }

  void _buildView() {
    _view = PhotoViewGallery(
      pageController: _pageController,
      pageOptions: options,
      scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: widget.readerDirection == ReaderDirection.rightToLeft,
      onPageChanged: _onGalleryPageChange,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
    );
  }

  void _buildOptions() {
    options.clear();
    for (var index = 0; index < ips.length; index += 2) {
      ImageProvider? leftIp = ips[index];
      ImageProvider? rightIp;
      var leftIndex = index;
      var rightIndex = -1;
      if (index + 1 < ips.length) {
        rightIp = ips[index + 1];
        rightIndex = index + 1;
      }
      if (currentTwoPageDirection == TwoPageDirection.rightToLeft) {
        final tempIp = leftIp;
        final tempIndex = leftIndex;
        leftIp = rightIp;
        leftIndex = rightIndex;
        rightIp = tempIp;
        rightIndex = tempIndex;
      }
      options.add(
        PhotoViewGalleryPageOptions.customChild(
          disableGestures:
              currentReaderControllerType == ReaderControllerType.touchDouble ||
                  currentReaderControllerType ==
                      ReaderControllerType.touchDoubleOnceNext,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return Row(
                children: [
                  Expanded(
                    child: _buildPageCell(
                      context: context,
                      constraints: constraints,
                      alignment: Alignment.centerRight,
                      imageProvider: leftIp,
                      imageIndex: leftIndex,
                    ),
                  ),
                  Expanded(
                    child: _buildPageCell(
                      context: context,
                      constraints: constraints,
                      alignment: Alignment.centerLeft,
                      imageProvider: rightIp,
                      imageIndex: rightIndex,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
  }

  Widget _buildPageCell({
    required BuildContext context,
    required BoxConstraints constraints,
    required Alignment alignment,
    required ImageProvider? imageProvider,
    required int imageIndex,
  }) {
    if (imageProvider == null || imageIndex < 0) {
      return const SizedBox.expand();
    }
    final effectiveProvider = _readerPageProvider(
      imageIndex,
      // Each page occupies half of the two-page viewport.  Use a width-only
      // target so the codec preserves the source aspect ratio and never
      // changes the pairing/layout semantics.
      width: constraints.maxWidth / 2,
    );
    return Align(
      alignment: alignment,
      child: Image(
        key: ValueKey(_imageProviderKeys[imageIndex] ?? 0),
        image: effectiveProvider,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return buildLoading(
            context,
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
          );
        },
        errorBuilder: (b, e, s) {
          debugPrient("$e,$s");
          return buildError(
            context,
            constraints.maxWidth / 2,
            constraints.maxHeight / 2,
            onReload: () => _reloadImage(imageIndex),
          );
        },
      ),
    );
  }

  void _reloadImage(int index) {
    if (mounted && index >= 0 && index < widget.chapter.images.length) {
      setState(() {
        _imageProviderKeys[index] = (_imageProviderKeys[index] ?? 0) + 1;
        // Clear image cache for this page.
        evictPageImageMemoryCache(
            widget.chapter.id, widget.chapter.images[index]);
        imageCache.evict(ips[index]);
        imageCache.evict(
          _readerPageProvider(
            index,
            width: (MediaQuery.maybeSizeOf(context)?.width ?? 0) / 2,
          ),
        );
        ips[index] =
            PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
        _buildOptions();
        // Rebuild the gallery view without resetting whole widget key.
        _buildView();
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void _needJumpTo(int index, bool animation) {
    if (index < 0 || index >= widget.chapter.images.length) {
      return;
    }
    if (currentNoAnimation() || animation == false) {
      _pageController.jumpToPage(
        index ~/ 2,
      );
    } else {
      _pageController.animateToPage(
        index ~/ 2,
        duration: const Duration(milliseconds: 400),
        curve: Curves.ease,
      );
    }
    _preloadJump(index);
    super._onCurrentChange(index, forceUiSync: true);
  }

  _preloadJump(int index, {bool init = false}) {
    fn() {
      if (!mounted) {
        return;
      }
      for (var i = index - 2; i < index + 5; i++) {
        if (i < 0 || i >= ips.length) continue;
        final ip = _readerPageProvider(i,
            width: (MediaQuery.maybeSizeOf(context)?.width ?? 0) / 2);
        _precacheReaderImage(ip);
      }
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fn());
    } else {
      fn();
    }
  }

  @override
  Widget _buildViewer() {
    return Stack(
      children: [
        GestureDetector(
          child: _view,
        ),
        _buildNextEpController(),
      ],
    );
  }

  void _onGalleryPageChange(int to) {
    if (!mounted || to < 0) {
      return;
    }
    var toIndex = to * 2;
    // Preload nearby pages.
    for (var i = toIndex + 2; i < toIndex + 5 && i < ips.length; i++) {
      final ip = _readerPageProvider(i,
          width: (MediaQuery.maybeSizeOf(context)?.width ?? 0) / 2);
      _precacheReaderImage(ip);
    }
    // Includes a synthetic trailing item for next-episode action.
    if (to >= 0 && to < widget.chapter.images.length) {
      super._onCurrentChange(toIndex, forceUiSync: true);
    }
  }

  Widget _buildNextEpController() {
    if (super._fullscreenController() ||
        _current < widget.chapter.images.length - 2) {
      return Container();
    }
    return Align(
      alignment: Alignment.bottomRight,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding:
              const EdgeInsets.only(left: 10, right: 10, top: 4, bottom: 4),
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            color: Color(0x88000000),
          ),
          child: GestureDetector(
            onTap: () {
              if (_hasNextEp()) {
                _onNextAction();
              } else {
                Navigator.of(context).pop();
              }
            },
            child: Text(
              _hasNextEp()
                  ? context.l10n.tr('下一章', en: 'Next chapter')
                  : context.l10n.tr('结束阅读', en: 'Finish reading'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

///////////////////////////////////////////////////////////////////////////////

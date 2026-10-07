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
import 'package:photo_view/photo_view_gallery.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../configs/ignore_view_log.dart';
import '../configs/no_animation.dart';
import '../configs/volume_key_control.dart';
import 'components/images.dart';
import 'components/reader_preloader.dart';
import 'components/reader_progress.dart';
import 'components/reader_zoom_surface.dart';
import 'components/right_click_pop.dart';

/// 释放远离当前页且已经没有活动监听器的解码图片，避免长章节持续占用内存。
/// includeLive=false 会保留仍在树上的图片，防止释放后马上重复解码。
void _releasePageImageMemory(ChapterResponse chapter, int index) {
  if (index < 0 || index >= chapter.images.length) {
    return;
  }
  evictPageImageDecodeCache(chapter.id, chapter.images[index]);
}

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

  void _load() {
    setState(() {
      _readerType = currentReaderType;
      _readerDirection = currentReaderDirection;
      _chapterFuture = widget.loadChapter(widget.chapterId);
    });
  }

  @override
  void initState() {
    if (currentIgnoreVewLog()) {
      late Future<AlbumResponse> _albumFuture = methods.album(
        widget.comic.id,
      );
      _albumFuture.then((value) {
        methods.updateViewLog(
            widget.comic.id, widget.chapterId, widget.initRank);
      });
    } else {
      methods.updateViewLog(widget.comic.id, widget.chapterId, widget.initRank);
    }
    _load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return rightClickPop(child: buildScreen(context), context: context);
  }

  Widget buildScreen(BuildContext context) {
    return FutureBuilder(
      future: _chapterFuture,
      builder: (BuildContext context, AsyncSnapshot<ChapterResponse> snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: ContentError(
              onRefresh: () async {
                setState(() {
                  // 阅读器可能来自在线漫画或本地下载，重试必须沿用注入的章节加载器。
                  _chapterFuture = widget.loadChapter(widget.chapterId);
                });
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
        final screen = Scaffold(
          backgroundColor: Colors.black,
          body: _ComicReader(
            comicId: widget.comic.id,
            chapter: chapter,
            startIndex: widget.initRank,
            reload: (int index, bool fullScreen) async {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return ComicReaderScreen(
                    comic: widget.comic,
                    series: widget.series,
                    chapterId: widget.chapterId,
                    initRank: index,
                    loadChapter: widget.loadChapter,
                    fullScreenOnInit: fullScreen,
                  );
                }),
              );
            },
            onChangeEp: (int id, bool fullScreen) async {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (BuildContext context) {
                  return ComicReaderScreen(
                    comic: widget.comic,
                    series: widget.series,
                    chapterId: id,
                    initRank: 0,
                    loadChapter: widget.loadChapter,
                    fullScreenOnInit: fullScreen,
                  );
                }),
              );
            },
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
  _volumeListenCount++;
  if (_volumeListenCount == 1) {
    volumeS =
        volumeButtonChannel.receiveBroadcastStream().listen(_onVolumeEvent);
  }
}

void delVolumeListen() {
  _volumeListenCount--;
  if (_volumeListenCount == 0) {
    volumeS?.cancel();
  }
}

Widget readerKeyboardHolder(Widget widget) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    widget = RawKeyboardListener(
      focusNode: FocusNode(),
      child: widget,
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
  return widget;
}

////////////////////////////////

Event<_ReaderControllerEventArgs> _readerControllerEvent =
    Event<_ReaderControllerEventArgs>();

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

/// 组件回归测试直接挂载实际阅读器，省去外层章节网络请求和导航路由。
@visibleForTesting
Widget buildComicReaderForTest({
  required GlobalKey key,
  required ChapterResponse chapter,
  required ReaderType readerType,
  required ReaderDirection direction,
  int startIndex = 0,
}) =>
    _ComicReader(
      key: key,
      comicId: chapter.id,
      chapter: chapter,
      startIndex: startIndex,
      readerType: readerType,
      readerDirection: direction,
      fullScreenOnInit: false,
      reload: (_, __) {},
      onChangeEp: (_, __) {},
    );

/// 测试驱动与键盘/音量键相同的跳页入口，验证真实动画产生的中间页回调。
@visibleForTesting
void jumpComicReaderForTest(GlobalKey key, int index, {bool animation = true}) {
  (key.currentState! as _ComicReaderState)._needJumpTo(index, animation);
}

@visibleForTesting
void controlComicReaderForTest(String direction) {
  _readerControllerEvent.broadcast(_ReaderControllerEventArgs(direction));
}

@visibleForTesting
({int current, int slider, int? jumpTarget}) comicReaderProgressForTest(
    GlobalKey key) {
  final state = key.currentState! as _ComicReaderState;
  return (
    current: state._current,
    slider: state._slider,
    jumpTarget: state._jumpTarget
  );
}

abstract class _ComicReaderState extends State<_ComicReader> {
  static const int _uiSyncMinIntervalMs = 80;
  bool _sliderDragging = false;
  Widget _buildViewer();

  _needJumpTo(int pageIndex, bool animation);

  late bool _fullScreen;
  late int _current;
  late int _slider;
  late int _memoryCenter;
  List<int> _sortedSeriesIds = const <int>[];
  int? _nextEpId;
  Timer? _viewLogDebounce;
  Timer? _uiSyncTimer;
  int? _pendingViewLogPage;
  int _lastUiSyncMs = 0;
  final ReaderPreloader _preloader = ReaderPreloader();
  int _preloadRequest = 0;
  int _jumpGeneration = 0;
  int? _jumpTarget;
  bool _disposed = false;

  void _releaseChapterImageMemory() {
    final chapter = widget.chapter;
    void release() {
      for (final imageName in chapter.images) {
        evictPageImageMemoryCache(chapter.id, imageName);
      }
    }

    release();
    // 子 Image 和 precache 的监听器会在帧末移除，再清理一次避免退出后留下解码缓存。
    WidgetsBinding.instance.addPostFrameCallback((_) => release());
  }

  void _preloadPages(int center, List<int> indexes, {bool init = false}) {
    if (_disposed || (_jumpTarget != null && _jumpTarget != center)) {
      return;
    }
    final request = ++_preloadRequest;
    void run() {
      if (_disposed || !mounted || request != _preloadRequest) {
        return;
      }
      final chapter = widget.chapter;
      unawaited(_preloader.preload(
        indexes: indexes
            .where((index) => index >= 0 && index < chapter.images.length),
        load: (index) => precacheImage(
          PageImageProvider(chapter.id, chapter.images[index]),
          context,
          onError: (error, stackTrace) => debugPrient(
            "precache page ${chapter.images[index]} failed: $error\n$stackTrace",
          ),
        ),
        releaseStale: (index) {
          final imageName = chapter.images[index];
          void release() {
            if (_disposed) {
              evictPageImageMemoryCache(chapter.id, imageName);
            } else if ((index - _memoryCenter).abs() > _cacheRadius) {
              evictPageImageDecodeCache(chapter.id, imageName);
            }
          }

          release();
          // precacheImage 自己也在帧末移除监听器，延后清理让过期解码真正离开缓存。
          WidgetsBinding.instance.addPostFrameCallback((_) => release());
        },
        onError: (error, stackTrace) => debugPrient("$error\n$stackTrace"),
      ));
    }

    if (init) {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    } else {
      run();
    }
  }

  Future<void> _jumpPagedReader(
    PageController controller,
    int imageIndex,
    bool animation, {
    int imagesPerPage = 1,
  }) async {
    if (_disposed || !controller.hasClients) {
      return;
    }
    final target = (imageIndex ~/ imagesPerPage) * imagesPerPage;
    await _jumpReader(
      target,
      () async {
        if (animation && !currentNoAnimation()) {
          await controller.animateToPage(
            target ~/ imagesPerPage,
            duration: const Duration(milliseconds: 400),
            curve: Curves.ease,
          );
        } else {
          controller.jumpToPage(target ~/ imagesPerPage);
        }
      },
      settledIndex: () => controller.hasClients
          ? ((controller.page ?? (target ~/ imagesPerPage)).round() *
              imagesPerPage)
          : target,
    );
  }

  Future<void> _jumpReader(
    int target,
    Future<void> Function() jump, {
    required int Function() settledIndex,
  }) async {
    final generation = ++_jumpGeneration;
    _jumpTarget = target;
    _slider = target;
    _viewLogDebounce?.cancel();
    _pendingViewLogPage = null;
    // 跳页刚开始时仍保留实际可见页，仅把滑块锁定到目标；中途退出可保存真实进度。
    _onCurrentChange(_current, forceUiSync: true);
    try {
      await jump();
    } finally {
      // 连续跳页时，旧动画完成只能结束自己的代数，不能解锁新跳页的进度目标。
      if (!_disposed && mounted && generation == _jumpGeneration) {
        final settled = settledIndex();
        _jumpTarget = null;
        _onCurrentChange(settled, forceUiSync: true);
      }
    }
  }

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

  int get _cacheRadius =>
      widget.readerType == ReaderType.twoPageGallery ? 3 : 2;

  void _releasePreviousPageWindow(int center) {
    if (_memoryCenter == center) {
      return;
    }
    final radius = _cacheRadius;
    final oldFirst = max(0, _memoryCenter - radius);
    final oldLast =
        min(widget.chapter.images.length - 1, _memoryCenter + radius);
    final newFirst = max(0, center - radius);
    final newLast = min(widget.chapter.images.length - 1, center + radius);
    for (var index = oldFirst; index <= oldLast; index++) {
      if (index >= newFirst && index <= newLast) {
        continue;
      }
      // 活跃页仍由 ImageStream 引用时不强制释放，避免重新进入页面时闪烁。
      _releasePageImageMemory(widget.chapter, index);
    }
    _memoryCenter = center;
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
    final entries = [...widget.chapter.series];
    entries.sort(
      (a, b) => int.parse(a.sort).compareTo(int.parse(b.sort)),
    );
    _sortedSeriesIds = entries.map((e) => e.id).toList(growable: false);
    final index = _sortedSeriesIds.indexOf(widget.chapter.id);
    if (index >= 0 && index < _sortedSeriesIds.length - 1) {
      _nextEpId = _sortedSeriesIds[index + 1];
    } else {
      _nextEpId = null;
    }
  }

  Future _onFullScreenChange(bool fullScreen) async {
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
    if (_disposed) {
      return;
    }
    final changed = index != _current;
    final slider = _jumpTarget ?? index;
    final sliderChanged = !_sliderDragging && _slider != slider;
    if (!changed && !sliderChanged && !forceUiSync) {
      return;
    }
    _current = index;
    // 拖动进度条期间保留用户正在选择的位置，避免滚动监听覆盖拇指位置。
    if (!_sliderDragging) {
      _slider = slider;
    }
    _releasePreviousPageWindow(_jumpTarget ?? index);
    // 程序跳页期间不持久化经过的中间页，最终到达/中断时再保存实际停留页。
    if (_jumpTarget == null) {
      _schedulePersistViewLog(index);
    }
    if (!mounted) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final isEdge = index <= 0 || index >= widget.chapter.images.length - 1;
    if (forceUiSync || isEdge || now - _lastUiSyncMs >= _uiSyncMinIntervalMs) {
      _uiSyncTimer?.cancel();
      _uiSyncTimer = null;
      _lastUiSyncMs = now;
      setState(() {});
    } else {
      // 限流必须保留最后一次同步，滚动停止后仍显示最终可见页。
      _uiSyncTimer ??= Timer(
        Duration(milliseconds: _uiSyncMinIntervalMs - (now - _lastUiSyncMs)),
        () {
          _uiSyncTimer = null;
          if (!_disposed && mounted) {
            _lastUiSyncMs = DateTime.now().millisecondsSinceEpoch;
            setState(() {});
          }
        },
      );
    }
  }

  @override
  void initState() {
    _fullScreen = widget.fullScreenOnInit;
    if (_fullScreen) {
      if (Platform.isAndroid || Platform.isIOS) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values,
        );
      }
    }
    _current = widget.startIndex;
    _slider = widget.startIndex;
    _memoryCenter = widget.startIndex;
    _readerControllerEvent.subscribe(_onPageControl);
    if (currentVolumeKeyControl()) {
      addVolumeListen();
    }
    _rebuildSeriesCache();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant _ComicReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chapter, widget.chapter)) {
      _rebuildSeriesCache();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _preloadRequest++;
    _jumpGeneration++;
    _preloader.dispose();
    _releaseChapterImageMemory();
    _uiSyncTimer?.cancel();
    if (_jumpTarget != null) {
      _pendingViewLogPage = _current;
    }
    _viewLogDebounce?.cancel();
    _flushViewLogPersist();
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (currentVolumeKeyControl()) {
      delVolumeListen();
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
    if (args != null) {
      var event = args.key;
      final page = _jumpTarget ?? _current;
      // 双页相册每次按键翻一个完整跨页，避免奇数目标归一化后停留在原跨页。
      final step = widget.readerType == ReaderType.twoPageGallery ? 2 : 1;
      switch (event) {
        case "UP":
          if (page > 0) {
            _needJumpTo(max(0, page - step), !currentNoAnimation());
          }
          break;
        case "DOWN":
          if (page < widget.chapter.images.length - 1) {
            _needJumpTo(min(widget.chapter.images.length - 1, page + step),
                !currentNoAnimation());
          }
          break;
      }
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
            _slider = _current;
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

    var entries = [...widget.chapter.series];
    entries.sort(
      (a, b) => int.parse(a.sort).compareTo(int.parse(b.sort)),
    );
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
  late final List<Size?> _trueSizes = [];
  late final ItemScrollController _itemScrollController;
  late final ItemPositionsListener _itemPositionsListener;
  bool _trueSizeRefreshQueued = false;

  @override
  void initState() {
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();
    _itemPositionsListener.itemPositions.addListener(_onListCurrentChange);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onListCurrentChange);
    super.dispose();
  }

  void _onListCurrentChange() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) {
      return;
    }
    final visible = positions
        .where((item) =>
            item.itemTrailingEdge > 0 &&
            item.itemLeadingEdge < 1 &&
            item.index >= 0 &&
            item.index < widget.chapter.images.length)
        .map((item) => ReaderPageBounds(
              item.index,
              item.itemLeadingEdge,
              item.itemTrailingEdge,
            ));
    final index = readerPageAtViewportCenter(visible);
    if (index == null) {
      return;
    }
    super._onCurrentChange(index);
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
    if (!_itemScrollController.isAttached) {
      return;
    }
    unawaited(_jumpReader(index, () async {
      if (animation && !currentNoAnimation()) {
        await _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 400),
        );
      } else {
        _itemScrollController.jumpTo(index: index);
        await WidgetsBinding.instance.endOfFrame;
      }
    },
        settledIndex: () =>
            readerPageAtViewportCenter(
              _itemPositionsListener.itemPositions.value
                  .where((item) => item.index < widget.chapter.images.length)
                  .map((item) => ReaderPageBounds(
                      item.index, item.itemLeadingEdge, item.itemTrailingEdge)),
            ) ??
            index));
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
    _pageController = PageController(initialPage: widget.startIndex);
    super.initState();
    _preloadJump(widget.startIndex, init: true);
  }

  void _reloadImage(int index) {
    if (mounted) {
      // Clear image cache for this page.
      final oldProvider =
          PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
      evictPageImageMemoryCache(
          widget.chapter.id, widget.chapter.images[index]);
      imageCache.evict(oldProvider);
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
      // 关闭隐式保活，让滑过的远页可以被 Flutter 回收，降低长章节内存峰值。
      allowImplicitScrolling: false,
      builder: (BuildContext context, int index) {
        final reloadKey = _reloadKeys[index] ?? 0;
        final imageProvider =
            PageImageProvider(widget.chapter.id, widget.chapter.images[index]);

        return PhotoViewGalleryPageOptions.customChild(
          disableGestures:
              currentReaderControllerType == ReaderControllerType.touchDouble ||
                  currentReaderControllerType ==
                      ReaderControllerType.touchDoubleOnceNext,
          child: LayoutBuilder(
            key: ValueKey(
                'page_${widget.chapter.id}_${widget.chapter.images[index]}_$reloadKey'),
            builder: (BuildContext context, BoxConstraints constraints) {
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
    unawaited(_jumpPagedReader(_pageController, pageIndex, animation));
    _preloadJump(pageIndex);
  }

  void _onGalleryPageChange(int to) {
    // 先完成当前页，再按阅读方向预加载后页和前页，避免图片显示顺序反转。
    _preloadJump(to);
    super._onCurrentChange(to);
  }

  _preloadJump(int index, {bool init = false}) {
    _preloadPages(index, [index, index + 1, index + 2, index - 1], init: init);
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
  final Map<int, GlobalKey<_PagedZoomImageState>> _zoomPageKeys = {};
  bool _isZoomed = false;

  @override
  void initState() {
    _pageController = PageController(initialPage: widget.startIndex);
    super.initState();
    _preloadAround(widget.startIndex, init: true);
  }

  @override
  void dispose() {
    _zoomPageKeys.clear();
    _pageController.dispose();
    super.dispose();
  }

  void _setZoomed(bool value) {
    if (_isZoomed == value || !mounted) {
      return;
    }
    setState(() {
      _isZoomed = value;
    });
  }

  void _resetZoomFor(int index) {
    _zoomPageKeys[index]?.currentState?.resetZoom();
    _setZoomed(false);
  }

  void _reloadImage(int index) {
    if (!mounted) {
      return;
    }
    final oldProvider =
        PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
    evictPageImageMemoryCache(widget.chapter.id, widget.chapter.images[index]);
    imageCache.evict(oldProvider);
    setState(() {
      _reloadKeys[index] = (_reloadKeys[index] ?? 0) + 1;
      _resetZoomFor(index);
    });
  }

  @override
  void _needJumpTo(int pageIndex, bool animation) {
    if (pageIndex < 0 || pageIndex >= widget.chapter.images.length) {
      return;
    }
    _resetZoomFor(_current);
    unawaited(_jumpPagedReader(_pageController, pageIndex, animation));
    _preloadAround(pageIndex);
  }

  void _onGalleryPageChange(int to) {
    _resetZoomFor(_current);
    _preloadAround(to);
    super._onCurrentChange(to);
  }

  void _preloadAround(int index, {bool init = false}) {
    _preloadPages(index, [index, index + 1, index + 2, index - 1], init: init);
  }

  Widget _buildGallery() {
    final axis = widget.readerDirection == ReaderDirection.topToBottom
        ? Axis.vertical
        : Axis.horizontal;
    return PageView.builder(
      scrollDirection: axis,
      reverse: widget.readerDirection == ReaderDirection.rightToLeft,
      controller: _pageController,
      onPageChanged: _onGalleryPageChange,
      itemCount: widget.chapter.images.length,
      // 放大时由当前缩放表面接管单指拖动，PageView 只在未放大时翻页。
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemBuilder: (BuildContext context, int index) {
        final reloadKey = _reloadKeys[index] ?? 0;
        final imageProvider =
            PageImageProvider(widget.chapter.id, widget.chapter.images[index]);
        return _PagedZoomImage(
          key: _zoomPageKeys.putIfAbsent(
              index, () => GlobalKey<_PagedZoomImageState>()),
          onZoomChanged: (zoomed) {
            if (index == _current && !_disposed) {
              _setZoomed(zoomed);
            }
          },
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
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

class _PagedZoomImage extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool> onZoomChanged;

  const _PagedZoomImage(
      {required this.child, required this.onZoomChanged, super.key});

  @override
  State<_PagedZoomImage> createState() => _PagedZoomImageState();
}

class _PagedZoomImageState extends State<_PagedZoomImage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.001;
    if (zoomed != _zoomed && mounted) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  void resetZoom() => _controller.value = Matrix4.identity();

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReaderZoomSurface(
        controller: _controller,
        panEnabled: _zoomed,
        allowDoubleTap:
            currentReaderControllerType != ReaderControllerType.touchDouble &&
                currentReaderControllerType !=
                    ReaderControllerType.touchDoubleOnceNext,
        child: widget.child,
      );
}

class _ListViewReaderState extends _ComicReaderState {
  var _isZoomed = false;
  var _activePointers = 0;
  final List<Size?> _trueSizes = [];
  bool _trueSizeRefreshQueued = false;
  final _transformationController = TransformationController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  @override
  void initState() {
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    _itemPositionsListener.itemPositions.addListener(_onScrollChanged);
    _transformationController.addListener(_onTransformChanged);
    super.initState();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onScrollChanged);
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
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
    if (_isZoomed || _activePointers > 1 || !mounted) {
      return;
    }
    // PositionedList 在布局结束后提供真实边界，避免异高图片和上帧几何数据造成进度跳动。
    final index = _visiblePageIndex();
    if (index != null) {
      super._onCurrentChange(index);
    }
  }

  int? _visiblePageIndex() => readerPageAtViewportCenter(
        _itemPositionsListener.itemPositions.value
            .where((item) => item.index < widget.chapter.images.length)
            .map((item) => ReaderPageBounds(
                  item.index,
                  item.itemLeadingEdge,
                  item.itemTrailingEdge,
                )),
      );

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
    if (index < 0 ||
        index >= widget.chapter.images.length ||
        !_itemScrollController.isAttached) {
      return;
    }
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    }
    // 直接按页索引定位远页，无需按整章高度比例猜测，也无需提前下载整章图片尺寸。
    unawaited(_jumpReader(index, () async {
      if (animation && !currentNoAnimation()) {
        await _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.ease,
        );
      } else {
        _itemScrollController.jumpTo(index: index);
        await WidgetsBinding.instance.endOfFrame;
      }
    }, settledIndex: () => _visiblePageIndex() ?? index));
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
        // 放大后单指拖动全部交给 InteractiveViewer；复原后恢复列表自然滚动。
        final giveTouchToViewer = _isZoomed || _activePointers > 1;
        var list = ScrollablePositionedList.builder(
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          initialScrollIndex: widget.startIndex,
          scrollDirection: currentReaderDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: currentReaderDirection == ReaderDirection.rightToLeft,
          minCacheExtent: currentReaderDirection == ReaderDirection.topToBottom
              ? constraints.maxHeight
              : constraints.maxWidth,
          physics: giveTouchToViewer
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
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
              child: JMPageImage(
                key: ValueKey(
                    "fz_${widget.chapter.id}_${widget.chapter.images[index]}"),
                widget.chapter.id,
                widget.chapter.images[index],
                width: renderSize.width,
                height: renderSize.height,
                onTrueSize: (size) => _onTrueSize(index, size),
              ),
            );
          },
        );
        var viewer = ReaderZoomSurface(
          controller: _transformationController,
          maxScale: 2,
          panEnabled: giveTouchToViewer,
          // 双击全屏控制模式保留外层双击入口，缩放仍可使用双指捏合。
          allowDoubleTap:
              currentReaderControllerType != ReaderControllerType.touchDouble &&
                  currentReaderControllerType !=
                      ReaderControllerType.touchDoubleOnceNext,
          child: IgnorePointer(
            ignoring: giveTouchToViewer,
            child: list,
          ),
        );
        return SizedBox.expand(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerEnd,
            onPointerCancel: _onPointerEnd,
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
    // Initialize chapter state before using startIndex.
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    super.initState();
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
      // 关闭隐式保活，避免双页阅读器把相邻页面全部留在内存中。
      allowImplicitScrolling: false,
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
    return Align(
      alignment: alignment,
      child: Image(
        key: ValueKey(_imageProviderKeys[imageIndex] ?? 0),
        image: imageProvider,
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
    if (mounted) {
      setState(() {
        _imageProviderKeys[index] = (_imageProviderKeys[index] ?? 0) + 1;
        // Clear image cache for this page.
        evictPageImageMemoryCache(
            widget.chapter.id, widget.chapter.images[index]);
        imageCache.evict(ips[index]);
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
    unawaited(
        _jumpPagedReader(_pageController, index, animation, imagesPerPage: 2));
    _preloadJump((index ~/ 2) * 2);
  }

  _preloadJump(int index, {bool init = false}) {
    _preloadPages(
        index, [index, index + 1, index + 2, index + 3, index - 1, index - 2],
        init: init);
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
    var toIndex = to * 2;
    // 当前双页完成后，按阅读顺序预加载后续页面，再释放远处图片。
    _preloadJump(toIndex);
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

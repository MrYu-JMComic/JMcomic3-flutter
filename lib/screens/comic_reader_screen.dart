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
import '../configs/reader_feature_flags.dart';
import '../configs/reader_target_decode.dart';
import '../basic/reader_system_ui.dart';
import 'components/images.dart';
import 'components/reader_preloader.dart';
import 'components/reader_progress.dart';
import 'components/reader_zoom_surface.dart';
import 'components/right_click_pop.dart';
import '../reader_session.dart';
import '../reader_viewlog_queue.dart';
import '../basic/reader_pages.dart';
import '../basic/page_pairing.dart';
import '../reader_progress.dart';

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
      debugPrient(
          "initial view log failed: ${error.runtimeType}/${stackTrace.runtimeType}");
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
      debugPrient(
          "reader navigation failed: ${error.runtimeType}/${stackTrace.runtimeType}");
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
  final ReaderSession _readerSession = ReaderSession();
  ReaderGeneration? _readerGeneration;
  final PrefetchScheduler _prefetchScheduler = PrefetchScheduler();

  /// Source-neutral page metadata; legacy `chapter.images` remains the
  /// rendering source until the repository-backed pipeline is enabled.
  Map<int, PageDescriptor> _pageDescriptorByPosition =
      const <int, PageDescriptor>{};
  final Set<PageImageProvider> _readerImageProviders = <PageImageProvider>{};
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
    if (index < 0 || index >= widget.chapter.images.length) {
      throw RangeError.index(
        index,
        widget.chapter.images,
        'index',
        'reader page index is outside the chapter',
      );
    }
    final descriptor = _descriptorAt(index);
    final imageName = descriptor?.name ?? widget.chapter.images[index];
    final localOnly =
        readerOfflineOwnerV1 && widget.chapter.offlineImages != null;
    // Avoid inherited-widget lookup during initState. Callers that need target
    // decoding provide the concrete layout width from their build callback.
    final safeWidth = width;
    final provider = readerPageImageProvider(
      context,
      widget.chapter.id,
      imageName,
      width: safeWidth,
      height: height,
      pageIndex: index,
      localPath:
          descriptor?.localAvailable == true ? descriptor!.localPath : null,
      localOnly: localOnly,
      enabled: readerTargetDecodeV1,
    );
    _readerImageProviders.add(provider);
    return provider;
  }

  PageDescriptor? _descriptorAt(int index) {
    return _pageDescriptorByPosition[index];
  }

  String _imageNameAt(int index) {
    if (index < 0 || index >= widget.chapter.images.length) {
      throw RangeError.index(index, widget.chapter.images, 'index');
    }
    return _descriptorAt(index)?.name ?? widget.chapter.images[index];
  }

  String? _localPathAt(int index) {
    final descriptor = _descriptorAt(index);
    return descriptor?.localAvailable == true ? descriptor?.localPath : null;
  }

  bool _isLocalOnlyChapter() =>
      readerOfflineOwnerV1 && widget.chapter.offlineImages != null;

  /// Preloading is opportunistic: a failed neighbour must never turn into a
  /// current-page error or an unhandled Future. Keep the context access behind
  /// a mounted check because several callers are post-frame callbacks.
  void _precacheReaderImage(
    ImageProvider provider, {
    int? pageIndex,
    int priority = 0,
    Object? key,
  }) {
    if (!mounted) {
      return;
    }
    try {
      final generation = _readerGeneration;
      if (readerPrefetchSchedulerV1 && generation != null) {
        final dedupeKey =
            key ?? Object.hash(widget.chapter.id, pageIndex, provider.hashCode);
        final handle = _prefetchScheduler.schedule<void>(generation, () async {
          await precacheImage(provider, context);
        },
            isCurrent: () => mounted && _readerSession.isCurrent(generation),
            priority: priority,
            key: dedupeKey);
        unawaited(handle.future.then((result) {
          if (result.outcome == PrefetchOutcome.failed) {
            debugPrient("reader prefetch failed: ${result.error.runtimeType}");
          }
        }));
        return;
      }
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
  Timer? _uiSyncTimer;
  ReaderViewlogQueue? _viewLogQueue;
  int? _pendingViewLogPage;
  int? _pendingViewLogComicId;
  int? _pendingViewLogChapterId;
  int _lastUiSyncMs = 0;
  final ReaderPreloader _preloader = ReaderPreloader();
  int _preloadRequest = 0;
  List<int> _lastPreloadIndexes = const <int>[];
  int _jumpGeneration = 0;
  int? _jumpTarget;
  bool _disposed = false;

  void _releaseChapterImages(ChapterResponse chapter) {
    final providers = _readerImageProviders
        .where((provider) => provider.id == chapter.id)
        .toList(growable: false);
    _readerImageProviders.removeAll(providers);
    void release() {
      for (final imageName in chapter.images) {
        evictPageImageMemoryCache(
          chapter.id,
          imageName,
          includeLive: true,
        );
      }
      for (final provider in providers) {
        imageCache.evict(provider, includeLive: true);
      }
    }

    release();
    // Image 子树和 precache 监听器会在帧末移除，再清理一次退出时仍存活的流。
    WidgetsBinding.instance.addPostFrameCallback((_) => release());
  }

  void _releaseChapterImageMemory() => _releaseChapterImages(widget.chapter);

  void _preloadPages(
    int center,
    Iterable<int> visibleIndexes, {
    bool init = false,
  }) {
    if (_disposed || (_jumpTarget != null && _jumpTarget != center)) {
      return;
    }
    final indexes = readerPreloadOrder(
      visibleIndexes: visibleIndexes,
      pageCount: widget.chapter.images.length,
    );
    if (indexes.isEmpty) {
      return;
    }
    if (!init && _sameIndexes(_lastPreloadIndexes, indexes)) {
      return;
    }
    _lastPreloadIndexes = indexes;
    final request = ++_preloadRequest;
    void run() {
      if (_disposed || !mounted || request != _preloadRequest) {
        return;
      }
      final chapter = widget.chapter;
      unawaited(_preloader.preload(
        indexes: indexes,
        load: (index) => precacheImage(
          _readerPageProvider(index),
          context,
          onError: (error, stackTrace) => debugPrient(
            "precache page $index failed: ${error.runtimeType}",
          ),
        ),
        releaseStale: (index) {
          if (index >= 0 && index < chapter.images.length) {
            evictPageImageMemoryCache(
              chapter.id,
              chapter.images[index],
              includeLive: true,
            );
          }
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

  bool _sameIndexes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  void _onVisiblePages(
    Iterable<int> indexes, {
    int? anchor,
    bool init = false,
  }) {
    final visible = indexes
        .where((index) => index >= 0 && index < widget.chapter.images.length)
        .toSet()
        .toList()
      ..sort();
    if (visible.isEmpty) {
      return;
    }
    final safeAnchor = anchor != null && visible.contains(anchor)
        ? anchor
        : visible[visible.length ~/ 2];
    _preloadPages(safeAnchor, visible, init: init);
    _onCurrentChange(safeAnchor);
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

  bool _didAddVolumeListen = false;
  ReaderSystemUiLease? _systemUiLease;
  int _systemUiChangeSerial = 0;
  bool _navigationInFlight = false;
  bool _modalInFlight = false;

  Future<void> _sendQueuedViewLog(Map<String, dynamic> event) async {
    final comicId = event['comic_id'];
    final chapterId = event['chapter_id'];
    final page = event['page'];
    if (comicId is! int || chapterId is! int || page is! int) {
      throw const FormatException('invalid reader view-log event');
    }
    await methods.updateViewLog(comicId, chapterId, page);
  }

  void _persistViewLog(int index, {int? comicId, int? chapterId}) {
    final queue = _viewLogQueue;
    if (queue != null) {
      queue.add(
        page: index,
        comicId: comicId ?? widget.comicId,
        chapterId: chapterId ?? widget.chapter.id,
        mode: widget.readerType.name,
        direction: widget.readerDirection.name,
      );
      return;
    }
    methods
        .updateViewLog(
      comicId ?? widget.comicId,
      chapterId ?? widget.chapter.id,
      index,
    )
        .catchError((e, st) {
      debugPrient(
          "reader view-log update failed: ${e.runtimeType}/${st.runtimeType}");
    });
  }

  void _schedulePersistViewLog(int index) {
    _pendingViewLogPage = index;
    _pendingViewLogComicId = widget.comicId;
    _pendingViewLogChapterId = widget.chapter.id;
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
    final comicId = _pendingViewLogComicId;
    final chapterId = _pendingViewLogChapterId;
    _pendingViewLogComicId = null;
    _pendingViewLogChapterId = null;
    _persistViewLog(page, comicId: comicId, chapterId: chapterId);
  }

  Future<void> _flushViewLogPersistAndWait() async {
    _flushViewLogPersist();
    final queue = _viewLogQueue;
    if (queue != null) {
      await queue.flush();
    }
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
    final serial = ++_systemUiChangeSerial;
    final lease = _systemUiLease;
    try {
      if (lease != null) {
        await lease.setFullScreen(fullScreen);
      }
    } catch (error, stackTrace) {
      // A platform channel can disappear during route teardown.  The reader
      // state must still remain usable, and diagnostics must not expose the
      // platform exception text (which may contain device paths).
      debugPrient(
          "reader system-ui update failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    }
    if (!mounted || serial != _systemUiChangeSerial) {
      return;
    }
    setState(() => _fullScreen = fullScreen);
  }

  List<PageDescriptor> _descriptorsForChapter() {
    final offline = widget.chapter.offlineImages;
    if (offline != null && readerOfflineOwnerV1) {
      return ReaderPageRepository.fromOffline(offline);
    }
    // Keep the descriptor facade independently rollbackable.  The legacy
    // reader addresses `chapter.images` directly when the experiment is off;
    // an offline owner may opt in only after it has supplied validated paths.
    if (!readerPageDescriptorV1) {
      return const <PageDescriptor>[];
    }
    return ReaderPageRepository.fromOnline(widget.chapter.images);
  }

  void _setPageDescriptors(List<PageDescriptor> descriptors) {
    _pageDescriptorByPosition = {
      // Descriptors may carry sparse/duplicate persisted source indices. The
      // reader itself always addresses a contiguous 0-based list, so map by
      // normalized ordinal rather than trusting `sourceIndex`/`position` from
      // an imported record.
      for (var index = 0; index < descriptors.length; index++)
        index: descriptors[index],
    };
  }

  void _onCurrentChange(int index, {bool forceUiSync = false}) {
    if (!mounted || widget.chapter.images.isEmpty) {
      return;
    }
    final safeIndex = index.clamp(0, widget.chapter.images.length - 1).toInt();
    final changed = safeIndex != _current;
    final slider = _jumpTarget ?? safeIndex;
    final sliderChanged = !_sliderDragging && _slider != slider;
    if (!changed && !sliderChanged && !forceUiSync) {
      return;
    }
    _current = safeIndex;
    if (!_sliderDragging) {
      _slider = slider;
    }
    if (_jumpTarget == null) {
      _schedulePersistViewLog(safeIndex);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final isEdge =
        safeIndex <= 0 || safeIndex >= widget.chapter.images.length - 1;
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
    super.initState();
    _fullScreen = widget.fullScreenOnInit;
    if (Platform.isAndroid || Platform.isIOS) {
      _systemUiLease = enterReaderSystemUi(fullScreen: _fullScreen);
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
    _setPageDescriptors(_descriptorsForChapter());
    _readerGeneration = _readerSession.openChapter(
      ChapterIdentity('${widget.comicId}:${widget.chapter.id}'),
    );
    if (readerViewLogQueueV1) {
      _viewLogQueue = ReaderViewlogQueue(
        sessionId:
            'reader-${widget.comicId}-${widget.chapter.id}-${identityHashCode(this)}',
        sink: _sendQueuedViewLog,
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ComicReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId ||
        oldWidget.chapter.id != widget.chapter.id ||
        !identical(oldWidget.chapter, widget.chapter)) {
      // A reused reader state has left the old chapter even though the route
      // itself remains mounted. Release it with the same scoped cleanup used
      // when the reader route is popped.
      _releaseChapterImages(oldWidget.chapter);
      // Publish the last event with the old chapter identity before replacing
      // the generation. The queue carries explicit IDs, so a delayed flush
      // cannot be misattributed to the new chapter.
      _flushViewLogPersist();
      final previousGeneration = _readerGeneration;
      if (previousGeneration != null) {
        _prefetchScheduler.cancelGeneration(previousGeneration);
      }
      _preloadRequest++;
      // Advance generation before rebuilding caches so in-flight work from
      // the previous chapter can only be discarded, never published.
      _readerGeneration = _readerSession.openChapter(
        ChapterIdentity('${widget.comicId}:${widget.chapter.id}'),
      );
      _setPageDescriptors(_descriptorsForChapter());
      _rebuildSeriesCache();
      final imageCount = widget.chapter.images.length;
      final safeStart = imageCount == 0
          ? 0
          : widget.startIndex.clamp(0, imageCount - 1).toInt();
      _current = safeStart;
      _slider = safeStart;
      _lastPreloadIndexes = const <int>[];
      _pendingViewLogPage = null;
      _pendingViewLogComicId = null;
      _pendingViewLogChapterId = null;
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
    _prefetchScheduler.close();
    _readerSession.close();
    _flushViewLogPersist();
    final queue = _viewLogQueue;
    _viewLogQueue = null;
    if (queue != null) {
      // Flutter dispose is synchronous; close performs one bounded flush and
      // retains failed events in the queue for an owning persistence layer.
      unawaited(queue.close());
    }
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (_didAddVolumeListen) {
      delVolumeListen();
      _didAddVolumeListen = false;
    }
    unawaited(_systemUiLease?.release());
    _systemUiLease = null;
    super.dispose();
  }

  void _onPageControl(_ReaderControllerEventArgs? args) {
    if (!mounted || args == null || widget.chapter.images.isEmpty) {
      return;
    }
    {
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
    if (!mounted || _modalInFlight || _navigationInFlight) {
      return;
    }
    _modalInFlight = true;
    try {
      await showMaterialModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xAA000000),
        builder: (context) {
          return SizedBox(
            height: MediaQuery.of(context).size.height * (.45),
            child: _EpChooser(widget.chapter, (id, fullScreen) {
              if (!mounted) return Future<void>.value();
              return widget.onChangeEp(id, fullScreen);
            }),
          );
        },
      );
    } catch (error, stackTrace) {
      debugPrient(
          "chapter chooser failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    } finally {
      _modalInFlight = false;
    }
  }

  //
  _onMoreSetting() async {
    if (!mounted || _modalInFlight || _navigationInFlight) {
      return;
    }
    _modalInFlight = true;
    try {
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
    } catch (error, stackTrace) {
      debugPrient(
          "reader settings failed: ${error.runtimeType}/${stackTrace.runtimeType}");
      return;
    } finally {
      _modalInFlight = false;
    }
    if (!mounted) {
      return;
    }
    if (widget.readerDirection != currentReaderDirection ||
        widget.readerType != currentReaderType) {
      try {
        await _flushViewLogPersistAndWait();
        await Future<void>.sync(() => widget.reload(_current, _fullScreen));
      } catch (error, stackTrace) {
        debugPrient(
            "reader mode reload failed: ${error.runtimeType}/${stackTrace.runtimeType}");
      }
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

  Future<void> _onNextAction() async {
    if (!mounted || _navigationInFlight) {
      return;
    }
    _navigationInFlight = true;
    final nextId = _nextEpId;
    if (nextId == null) {
      _navigationInFlight = false;
      defaultToast(
        context,
        context.l10n.tr("已经到头了", en: "You have reached the end"),
      );
      return;
    }
    try {
      await Future<void>.sync(() => widget.onChangeEp(nextId, _fullScreen));
    } catch (error, stackTrace) {
      debugPrient(
          "next chapter navigation failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    } finally {
      _navigationInFlight = false;
    }
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
  bool _selectionInFlight = false;

  Future<void> _selectChapter(int id) async {
    if (_selectionInFlight || !mounted) {
      return;
    }
    _selectionInFlight = true;
    try {
      if (mounted) {
        Navigator.of(context).pop();
      }
      await Future<void>.sync(() => widget.onChangeEp(id, false));
    } catch (error, stackTrace) {
      debugPrient(
          "chapter selection failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    } finally {
      _selectionInFlight = false;
    }
  }

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
            onPressed: _selectionInFlight
                ? null
                : () => unawaited(_selectChapter(e.id)),
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
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.view_day_outlined,
              title: readerTypeName(currentReaderType, context),
              onPressed: () async {
                await chooseReaderType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.control_camera_outlined,
              title: currentReaderControllerTypeName(context),
              onPressed: () async {
                await chooseReaderControllerType(context);
                if (mounted) setState(() {});
              },
            ),
            _bottomIcon(
              icon: Icons.straighten_sharp,
              title: currentReaderSliderPositionName(context),
              onPressed: () async {
                await chooseReaderSliderPosition(context);
                if (mounted) setState(() {});
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
        .toList(growable: false);
    final index = readerPageAtViewportCenter(visible.map((item) =>
        ReaderPageBounds(
          item.index,
          item.itemLeadingEdge,
          item.itemTrailingEdge,
        )));
    if (index == null) {
      return;
    }
    _onVisiblePages(
      visible.map((item) => item.index),
      anchor: index,
    );
  }

  Size _renderSizeFor(BoxConstraints constraints, int index) {
    if (index < 0 || index >= _trueSizes.length) {
      return Size(
        max(1.0, constraints.maxWidth),
        max(1.0, constraints.maxWidth / 2),
      );
    }
    final trueSize = _trueSizes[index];
    if (trueSize != null &&
        trueSize.width.isFinite &&
        trueSize.height.isFinite &&
        trueSize.width > 0 &&
        trueSize.height > 0) {
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
      return Size(max(1.0, maxHeight * trueSize.width / trueSize.height),
          max(1.0, maxHeight));
    }
    if (widget.readerDirection == ReaderDirection.topToBottom) {
      return Size(
          max(1.0, constraints.maxWidth), max(1.0, constraints.maxWidth / 2));
    }
    return Size(
        max(1.0, constraints.maxWidth / 2), max(1.0, constraints.maxHeight));
  }

  void _onTrueSize(int index, Size size) {
    if (index < 0 ||
        index >= _trueSizes.length ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
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
                    "wt_${widget.chapter.id}_${index}_${_imageNameAt(index)}"),
                widget.chapter.id,
                _imageNameAt(index),
                pageIndex: index,
                localPath: _localPathAt(index),
                localOnly: _isLocalOnlyChapter(),
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
      final oldProvider = _readerPageProvider(index);
      evictPageImageMemoryCache(widget.chapter.id, _imageNameAt(index));
      imageCache.evict(oldProvider);
      imageCache.evict(_readerPageProvider(index));
      // Image names may contain an absolute URL or a local path in legacy
      // metadata.  Keep eviction diagnostics keyed by the stable page index
      // so retry logs cannot disclose that value.
      debugPrient("evict reader page index=$index");
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

        return PhotoViewGalleryPageOptions.customChild(
          disableGestures:
              currentReaderControllerType == ReaderControllerType.touchDouble ||
                  currentReaderControllerType ==
                      ReaderControllerType.touchDoubleOnceNext,
          child: LayoutBuilder(
            key: ValueKey(
                'page_${widget.chapter.id}_${index}_${_imageNameAt(index)}_$reloadKey'),
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
                    'image_${widget.chapter.id}_${index}_${_imageNameAt(index)}_$reloadKey'),
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
                  debugPrient(
                      "image decode failed: ${e.runtimeType}/${s.runtimeType}");
                  if (_isLocalOnlyChapter()) {
                    return buildOfflineImageUnavailable(
                      context,
                      constraints.maxWidth,
                      constraints.maxHeight,
                      onReload: () => _reloadImage(index),
                    );
                  }
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
    unawaited(_jumpPagedReader(_pageController, pageIndex, animation));
    _preloadJump(pageIndex);
  }

  void _onGalleryPageChange(int to) {
    if (!mounted || to < 0 || to >= widget.chapter.images.length) {
      return;
    }
    // 先完成当前页，再按阅读方向预加载后页和前页，避免图片显示顺序反转。
    _preloadJump(to);
    super._onCurrentChange(to);
  }

  _preloadJump(int index, {bool init = false}) {
    _preloadPages(index, [index], init: init);
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
    if (!mounted || index < 0 || index >= widget.chapter.images.length) {
      return;
    }
    final oldProvider = _readerPageProvider(index);
    evictPageImageMemoryCache(widget.chapter.id, _imageNameAt(index));
    imageCache.evict(oldProvider);
    imageCache.evict(_readerPageProvider(index));
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
    if (!mounted || to < 0 || to >= widget.chapter.images.length) {
      return;
    }
    _resetZoomFor(_current);
    _preloadAround(to);
    super._onCurrentChange(to);
  }

  void _preloadAround(int index, {bool init = false}) {
    _preloadPages(index, [index], init: init);
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
              final imageProvider = _readerPageProvider(
                index,
                width: constraints.maxWidth,
              );
              return SizedBox.expand(
                child: Image(
                  key: ValueKey(
                    'fz_image_${widget.chapter.id}_${index}_${_imageNameAt(index)}_$reloadKey',
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
                    debugPrient(
                        "image decode failed: ${e.runtimeType}/${s.runtimeType}");
                    if (_isLocalOnlyChapter()) {
                      return buildOfflineImageUnavailable(
                        context,
                        constraints.maxWidth,
                        constraints.maxHeight,
                        onReload: () => _reloadImage(index),
                      );
                    }
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
  final List<GlobalKey> _pageKeys = [];
  final GlobalKey _viewportKey = GlobalKey();
  BoxConstraints? _lastLayoutConstraints;
  bool _trueSizeRefreshQueued = false;
  final _transformationController = TransformationController();
  final ScrollController _scrollController = ScrollController();
  ReaderExtentIndex? _extentIndex;
  BoxConstraints? _extentIndexConstraints;
  int _suppressScrollUntilMs = 0;
  int? _manualJumpPage;

  @override
  void initState() {
    super.initState();
    for (var index = 0; index < widget.chapter.images.length; index++) {
      final descriptor = _descriptorAt(index);
      _trueSizes.add(descriptor?.hasDimensions == true
          ? Size(descriptor!.width.toDouble(), descriptor.height.toDouble())
          : null);
      _pageKeys.add(GlobalKey());
    }
    _scrollController.addListener(_onScrollChanged);
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
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
    if (_isZoomed ||
        _activePointers > 1 ||
        !mounted ||
        !_scrollController.hasClients ||
        _jumpTarget != null ||
        DateTime.now().millisecondsSinceEpoch < _suppressScrollUntilMs ||
        _manualJumpPage != null) {
      return;
    }
    final imageCount = widget.chapter.images.length;
    if (imageCount <= 1) {
      _preloadPages(0, const [0]);
      super._onCurrentChange(0);
      return;
    }
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      _preloadPages(0, const [0]);
      super._onCurrentChange(0);
      return;
    }
    final constraints = _lastLayoutConstraints;
    final index = readerPreciseProgressV1 && constraints != null
        ? _extentIndexFor(constraints)
            .estimate(
                max(0.0, _scrollController.offset - _listLeadingPadding()))
            .page
        : (((_scrollController.offset / maxExtent).clamp(0.0, 1.0).toDouble()) *
                (imageCount - 1))
            .ceil();
    _preloadPages(index, _visiblePageIndexes(index));
    super._onCurrentChange(index);
  }

  List<int> _visiblePageIndexes(int fallbackIndex) {
    final viewportObject = _viewportKey.currentContext?.findRenderObject();
    if (viewportObject is! RenderBox || !viewportObject.hasSize) {
      return [fallbackIndex];
    }
    final viewportOrigin = viewportObject.localToGlobal(Offset.zero);
    final viewportRect = viewportOrigin & viewportObject.size;
    final visible = <int>[];
    final center = fallbackIndex.clamp(0, _pageKeys.length - 1).toInt();
    const probeRadius = 32;
    for (var delta = 0; delta <= probeRadius; delta++) {
      final candidates = delta == 0
          ? <int>[center]
          : <int>[center - delta, center + delta];
      for (final index in candidates) {
        if (index < 0 || index >= _pageKeys.length) {
          continue;
        }
        final object = _pageKeys[index].currentContext?.findRenderObject();
        if (object is! RenderBox || !object.hasSize) {
          continue;
        }
        final pageRect = object.localToGlobal(Offset.zero) & object.size;
        if (pageRect.right > viewportRect.left &&
            pageRect.left < viewportRect.right &&
            pageRect.bottom > viewportRect.top &&
            pageRect.top < viewportRect.bottom) {
          visible.add(index);
        }
      }
    }
    return visible.isEmpty ? [fallbackIndex] : visible;
  }

  List<double> _pageExtents(BoxConstraints constraints) {
    final vertical = currentReaderDirection == ReaderDirection.topToBottom;
    final fallback = max(1.0, constraints.maxWidth / 2);
    return List<double>.generate(widget.chapter.images.length, (index) {
      final size = _renderSizeFor(constraints, index);
      final extent = vertical ? size.height : size.width;
      return extent.isFinite && extent > 0 ? extent : fallback;
    }, growable: false);
  }

  ReaderExtentIndex _extentIndexFor(BoxConstraints constraints) {
    if (_extentIndex == null || _extentIndexConstraints != constraints) {
      _extentIndex = ReaderExtentIndex(_pageExtents(constraints));
      _extentIndexConstraints = constraints;
    }
    return _extentIndex!;
  }

  double _listLeadingPadding() =>
      currentReaderDirection == ReaderDirection.topToBottom
          ? super._appBarHeight()
          : max(super._appBarHeight(), super._bottomBarHeight());

  void _onPointerDown(PointerDownEvent event) {
    _manualJumpPage = null;
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
        !_scrollController.hasClients) {
      return;
    }
    if (_isZoomed) {
      _transformationController.value = Matrix4.identity();
    }
    final targetContext = _pageKeys[index].currentContext;
    if (targetContext != null) {
      unawaited(_jumpReader(index, () async {
        await Scrollable.ensureVisible(
          targetContext,
          duration: animation && !currentNoAnimation()
              ? const Duration(milliseconds: 400)
              : Duration.zero,
          curve: Curves.ease,
        );
      }, settledIndex: () => index));
      return;
    }
    final constraints = _lastLayoutConstraints;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final estimatedTarget = readerPreciseProgressV1 && constraints != null
        ? _extentIndexFor(constraints).offsetForPage(index) +
            _listLeadingPadding()
        : (maxExtent *
            (widget.chapter.images.length <= 1
                ? 0.0
                : index / (widget.chapter.images.length - 1)));
    final target = estimatedTarget.clamp(0.0, maxExtent).toDouble();
    _suppressScrollUntilMs = DateTime.now().millisecondsSinceEpoch +
        (animation && !currentNoAnimation() ? 500 : 100);
    unawaited(_jumpReader(index, () async {
      if (animation && !currentNoAnimation()) {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 400),
          curve: Curves.ease,
        );
      } else {
        _scrollController.jumpTo(target);
        await WidgetsBinding.instance.endOfFrame;
      }
    }, settledIndex: () {
      _manualJumpPage = index;
      return index;
    }));
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
    if (index < 0 || index >= _trueSizes.length) {
      return Size(
        max(1.0, constraints.maxWidth / 2),
        max(1.0, constraints.maxHeight),
      );
    }
    final trueSize = _trueSizes[index];
    if (trueSize != null &&
        trueSize.width.isFinite &&
        trueSize.height.isFinite &&
        trueSize.width > 0 &&
        trueSize.height > 0) {
      if (currentReaderDirection == ReaderDirection.topToBottom) {
        return Size(
          max(1.0, constraints.maxWidth),
          max(1.0, constraints.maxWidth * trueSize.height / trueSize.width),
        );
      }
      final maxHeight = constraints.maxHeight -
          super._appBarHeight() -
          (super._fullScreen
              ? super._appBarHeight()
              : super._bottomBarHeight());
      return Size(
        max(1.0, maxHeight * trueSize.width / trueSize.height),
        max(1.0, maxHeight),
      );
    }
    if (currentReaderDirection == ReaderDirection.topToBottom) {
      return Size(
          max(1.0, constraints.maxWidth), max(1.0, constraints.maxWidth / 2));
    }
    return Size(
        max(1.0, constraints.maxWidth / 2), max(1.0, constraints.maxHeight));
  }

  void _onTrueSize(int index, Size size) {
    if (index < 0 ||
        index >= _trueSizes.length ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
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
    _extentIndex = null;
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
        if (_lastLayoutConstraints != constraints) {
          _extentIndex = null;
        }
        _lastLayoutConstraints = constraints;
        // 放大后单指拖动全部交给 InteractiveViewer；复原后恢复列表自然滚动。
        final giveTouchToViewer = _isZoomed || _activePointers > 1;
        var list = ListView.builder(
          key: _viewportKey,
          controller: _scrollController,
          scrollDirection: currentReaderDirection == ReaderDirection.topToBottom
              ? Axis.vertical
              : Axis.horizontal,
          reverse: currentReaderDirection == ReaderDirection.rightToLeft,
          cacheExtent: currentReaderDirection == ReaderDirection.topToBottom
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
              child: KeyedSubtree(
                key: _pageKeys[index],
                child: JMPageImage(
                  key: ValueKey(
                      "fz_${widget.chapter.id}_${index}_${_imageNameAt(index)}"),
                  widget.chapter.id,
                  _imageNameAt(index),
                  pageIndex: index,
                  localPath: _localPathAt(index),
                  localOnly: _isLocalOnlyChapter(),
                  width: renderSize.width,
                  height: renderSize.height,
                  onTrueSize: (size) => _onTrueSize(index, size),
                ),
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
  late final List<PagePair> _pagePairs;
  List<ImageProvider> ips = [];
  List<PhotoViewGalleryPageOptions> options = [];
  late PhotoViewGallery _view;
  final Map<int, int> _imageProviderKeys = {};

  int _legacyPairPrimaryPage(int slot) {
    final first = slot * 2;
    if (first < 0 || first >= widget.chapter.images.length) {
      return -1;
    }
    final second = first + 1;
    final rtl = currentTwoPageDirection == TwoPageDirection.rightToLeft;
    if (rtl && second < widget.chapter.images.length) {
      return second;
    }
    return first;
  }

  @override
  void initState() {
    super.initState();
    // Initialize chapter state before using startIndex.
    for (var _ in widget.chapter.images) {
      _trueSizes.add(null);
    }
    _pagePairs = buildPagePairs(
      widget.chapter.images.length,
      // The experimental windowed path reserves the cover as a solo page;
      // the legacy path below remains byte-for-byte compatible until the
      // flag is enabled.
      cover: readerTwoPageWindowV1,
      rtl: currentTwoPageDirection == TwoPageDirection.rightToLeft,
      startIndex: widget.startIndex,
    );
    final initialSlot = readerTwoPageWindowV1
        ? (pairForPage(_pagePairs, widget.startIndex)?.slot ?? 0)
        : widget.startIndex ~/ 2;
    _pageController = PageController(initialPage: initialSlot);
    for (var index = 0; index < widget.chapter.images.length; index++) {
      _imageProviderKeys[index] = 0;
    }
    if (readerTwoPageWindowV1) {
      _preloadJump(widget.startIndex, init: true);
      return;
    }
    for (var index = 0; index < widget.chapter.images.length; index++) {
      ips.add(_readerPageProvider(index));
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

  Widget _buildWindowedView() {
    return PhotoViewGallery.builder(
      pageController: _pageController,
      itemCount: _pagePairs.length,
      scrollDirection: widget.readerDirection == ReaderDirection.topToBottom
          ? Axis.vertical
          : Axis.horizontal,
      reverse: widget.readerDirection == ReaderDirection.rightToLeft,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      onPageChanged: _onGalleryPageChange,
      allowImplicitScrolling: true,
      builder: (BuildContext context, int slot) {
        final pair = _pagePairs[slot];
        return PhotoViewGalleryPageOptions.customChild(
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
                      imageProvider: pair.left == null
                          ? null
                          : _readerPageProvider(pair.left!,
                              width: constraints.maxWidth / 2),
                      imageIndex: pair.left ?? -1,
                    ),
                  ),
                  Expanded(
                    child: _buildPageCell(
                      context: context,
                      constraints: constraints,
                      alignment: Alignment.centerLeft,
                      imageProvider: pair.right == null
                          ? null
                          : _readerPageProvider(pair.right!,
                              width: constraints.maxWidth / 2),
                      imageIndex: pair.right ?? -1,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
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
          debugPrient("image decode failed: ${e.runtimeType}/${s.runtimeType}");
          if (_isLocalOnlyChapter()) {
            return buildOfflineImageUnavailable(
              context,
              constraints.maxWidth / 2,
              constraints.maxHeight / 2,
              onReload: () => _reloadImage(imageIndex),
            );
          }
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
        evictPageImageMemoryCache(widget.chapter.id, _imageNameAt(index));
        if (index < ips.length) imageCache.evict(ips[index]);
        imageCache.evict(
          _readerPageProvider(
            index,
            width: (MediaQuery.maybeSizeOf(context)?.width ?? 0) / 2,
          ),
        );
        if (index < ips.length) {
          ips[index] = _readerPageProvider(index);
        }
        if (!readerTwoPageWindowV1) {
          _buildOptions();
          // Rebuild the legacy gallery view without resetting whole widget key.
          _buildView();
        }
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
    if (readerTwoPageWindowV1) {
      if (!_pageController.hasClients || _pagePairs.isEmpty) {
        return;
      }
      final slot = pairForPage(_pagePairs, index)?.slot ?? 0;
      if (currentNoAnimation() || !animation) {
        _pageController.jumpToPage(slot);
      } else {
        _pageController.animateToPage(
          slot,
          duration: const Duration(milliseconds: 400),
          curve: Curves.ease,
        );
      }
      _preloadJump(index);
      super._onCurrentChange(index, forceUiSync: true);
      return;
    }
    unawaited(
        _jumpPagedReader(_pageController, index, animation, imagesPerPage: 2));
    _preloadJump((index ~/ 2) * 2);
  }

  _preloadJump(int index, {bool init = false}) {
    final visible = <int>[];
    if (readerTwoPageWindowV1) {
      final pair = pairForPage(_pagePairs, index);
      if (pair != null) {
        if (pair.left != null) {
          visible.add(pair.left!);
        }
        if (pair.right != null) {
          visible.add(pair.right!);
        }
      }
    } else {
      final first = (index ~/ 2) * 2;
      visible
        ..add(first)
        ..add(first + 1);
    }
    _preloadPages(index, visible, init: init);
  }

  @override
  Widget _buildViewer() {
    final viewer = readerTwoPageWindowV1 ? _buildWindowedView() : _view;
    return Stack(
      children: [
        GestureDetector(
          child: viewer,
        ),
        _buildNextEpController(),
      ],
    );
  }

  void _onGalleryPageChange(int to) {
    if (!mounted || to < 0) {
      return;
    }
    if (readerTwoPageWindowV1 && to >= _pagePairs.length) {
      return;
    }
    final toIndex = readerTwoPageWindowV1
        ? _pagePairs[to].primaryPage(
            rtl: currentTwoPageDirection == TwoPageDirection.rightToLeft,
          )
        : to * 2;
    if (toIndex < 0 || toIndex >= widget.chapter.images.length) {
      return;
    }
    // 当前双页完成后，按可见双页、阅读顺序和邻近页预加载。
    _preloadJump(toIndex);
    // Includes a synthetic trailing item for next-episode action.
    if (to >= 0 &&
        to <
            (readerTwoPageWindowV1
                ? _pagePairs.length
                : widget.chapter.images.length)) {
      super._onCurrentChange(toIndex, forceUiSync: true);
    }
  }

  Widget _buildNextEpController() {
    final finalPrimaryPage = readerTwoPageWindowV1
        ? (_pagePairs.isEmpty
            ? -1
            : _pagePairs.last.primaryPage(
                rtl: currentTwoPageDirection == TwoPageDirection.rightToLeft,
              ))
        : _legacyPairPrimaryPage(
            max(0, (widget.chapter.images.length - 1) ~/ 2),
          );
    if (super._fullscreenController() ||
        finalPrimaryPage < 0 ||
        _current < finalPrimaryPage) {
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

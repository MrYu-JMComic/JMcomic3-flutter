import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:another_xlider/another_xlider.dart';
import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:photo_view/photo_view.dart';
import 'package:zoomable_positioned_list/zoomable_positioned_list.dart'
    as zoomable;
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

import '../configs/ignore_view_log.dart';
import '../configs/no_animation.dart';
import '../configs/volume_key_control.dart';
import '../basic/reader_system_ui.dart';
import 'components/images.dart';
import 'components/right_click_pop.dart';
import '../basic/reader_pages.dart';
import '../basic/page_pairing.dart';
import 'reader/reader_position.dart';

part 'reader/reader_viewers.dart';
part 'reader/reader_panels.dart';

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

  /// Preserve the server-side history behavior. Local page progress is written
  /// exclusively by the mounted reader after its starting index is validated.
  Future<void> _recordServerHistory() async {
    final comicId = widget.comic.id;
    try {
      if (currentIgnoreVewLog()) {
        await methods.album(comicId);
      }
    } catch (error, stackTrace) {
      debugPrient(
          "server history failed: ${error.runtimeType}/${stackTrace.runtimeType}");
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
    unawaited(_recordServerHistory());
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
      unawaited(_recordServerHistory());
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
            fallbackSeries: widget.series,
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
    return KeyboardListener(
      focusNode: _focusNode,
      child: widget.child,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _readerControllerEvent.broadcast(_ReaderControllerEventArgs("UP"));
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
  final List<Series> fallbackSeries;
  final FutureOr Function(int, bool) reload;
  final FutureOr Function(int, bool) onChangeEp;
  final int startIndex;
  final ReaderType readerType;
  final ReaderDirection readerDirection;
  final bool fullScreenOnInit;

  const _ComicReader({
    required this.comicId,
    required this.chapter,
    this.fallbackSeries = const [],
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
        return _ContinuousReaderState();
      case ReaderType.gallery:
        return _PagedReaderState();
      case ReaderType.webToonFreeZoom:
        return _ContinuousReaderState();
      case ReaderType.twoPageGallery:
        return _PagedReaderState();
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

abstract class _ComicReaderState extends State<_ComicReader>
    with WidgetsBindingObserver {
  late ReaderPosition _position;
  late ReaderProgressWriter _progressWriter;
  late bool _fullScreen;
  ReaderSystemUiLease? _systemUiLease;
  bool _didAddVolumeListen = false;
  bool _navigationInFlight = false;
  bool _modalInFlight = false;
  bool _repaintQueued = false;
  int _preloadRevision = 0;
  final Map<int, PageImageProvider> _providers = {};
  late List<PageDescriptor> _pages;

  int get _current => _position.current;
  int get _slider => _position.displayPage;
  int? get _jumpTarget => _position.target;
  bool get _doubleTapFullscreen =>
      currentReaderControllerType == ReaderControllerType.touchDouble ||
      currentReaderControllerType == ReaderControllerType.touchDoubleOnceNext;
  bool get _handlesSingleTap =>
      currentReaderControllerType == ReaderControllerType.touchOnce ||
      currentReaderControllerType == ReaderControllerType.touchDoubleOnceNext ||
      currentReaderControllerType == ReaderControllerType.threeArea;
  bool get _paired => widget.readerType == ReaderType.twoPageGallery;
  int _normalizePage(int page) =>
      _paired ? (_position.clamp(page) ~/ 2) * 2 : _position.clamp(page);

  Widget _buildViewer();
  Future<void> _moveTo(int page, bool animation);
  int _visiblePage();

  @override
  void initState() {
    super.initState();
    _position = ReaderPosition(widget.chapter.images.length, widget.startIndex);
    _position.report(_normalizePage(widget.startIndex));
    _fullScreen = widget.fullScreenOnInit;
    final comicId = widget.comicId;
    final chapterId = widget.chapter.id;
    _progressWriter = ReaderProgressWriter(
      comicId: comicId,
      save: (page) async => methods.updateViewLog(comicId, chapterId, page),
      onError: (error, stack) =>
          debugPrient('reader progress write failed: ${error.runtimeType}'),
    );
    _pages = widget.chapter.offlineImages == null
        ? ReaderPageRepository.fromOnline(widget.chapter.images)
        : ReaderPageRepository.fromOffline(widget.chapter.offlineImages!);
    WidgetsBinding.instance.addObserver(this);
    _readerControllerEvent.subscribe(_onPageControl);
    if (Platform.isAndroid && currentVolumeKeyControl()) {
      addVolumeListen();
      _didAddVolumeListen = true;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      _systemUiLease = enterReaderSystemUi(fullScreen: _fullScreen);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _progressWriter.schedule(_current);
      _preloadAround(_current);
    });
  }

  PageDescriptor _pageAt(int index) => _pages[index];

  PageImageProvider _readerPageProvider(int index) =>
      _providers.putIfAbsent(index, () {
        final page = _pageAt(index);
        return PageImageProvider(widget.chapter.id, page.name,
            pageIndex: page.sourceIndex,
            localPath: page.localAvailable ? page.localPath : null,
            localOnly: page.localPath != null);
      });

  void _preloadAround(int page) {
    final revision = ++_preloadRevision;
    final count = _paired ? 4 : 3;
    Future<void> run() async {
      for (var index = page;
          index < min(page + count, widget.chapter.images.length);
          index++) {
        if (!mounted || revision != _preloadRevision) return;
        final provider = _readerPageProvider(index);
        await precacheImage(provider, context, onError: (_, __) {});
        if (!mounted) {
          imageCache.evict(provider, includeLive: true);
          return;
        }
      }
    }

    unawaited(run().catchError((Object error, StackTrace stack) {
      debugPrient('reader preload failed: ${error.runtimeType}');
    }));
  }

  void _repaint() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.midFrameMicrotasks) {
      if (_repaintQueued) return;
      _repaintQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _repaintQueued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _onCurrentChange(int index) {
    if (!mounted) return;
    final previousTarget = _jumpTarget;
    final changed = _position.report(index);
    if (changed) {
      _progressWriter.schedule(_current);
      _preloadAround(_current);
    }
    if (changed || previousTarget != _jumpTarget) _repaint();
  }

  void _needJumpTo(int index, bool animation) {
    if (!mounted) return;
    final replacing = _position.target != null;
    final target = _normalizePage(index);
    final revision = _position.request(target);
    _repaint();
    // Coalesce controls issued in one frame. A newer intent is never discarded
    // by a timer, nor may an old animation completion overwrite that intent.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_position.isCurrent(revision)) return;
      try {
        await _moveTo(target, animation && !replacing && !currentNoAnimation());
        if (!mounted || !_position.isCurrent(revision)) return;
        _position.finish(revision, _visiblePage());
        _progressWriter.schedule(_current);
        _repaint();
      } catch (error) {
        if (!mounted || !_position.isCurrent(revision)) return;
        _position.cancel();
        _repaint();
        debugPrient('reader jump failed: ${error.runtimeType}');
      }
    });
  }

  void _onPageControl(_ReaderControllerEventArgs? event) {
    if (!mounted ||
        event == null ||
        _modalInFlight ||
        _navigationInFlight ||
        ModalRoute.of(context)?.isCurrent == false) return;
    final delta = event.key == 'UP'
        ? -1
        : event.key == 'DOWN'
            ? 1
            : 0;
    if (delta != 0) {
      _needJumpTo(_position.navigationPage + delta * (_paired ? 2 : 1),
          !currentNoAnimation());
    }
  }

  void _cancelJump() {
    if (_position.target == null) return;
    _position.cancel();
    _repaint();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_progressWriter.flush());
  }

  @override
  void dispose() {
    _preloadRevision++;
    _position.cancel();
    _progressWriter.schedule(_current);
    unawaited(_progressWriter.close());
    WidgetsBinding.instance.removeObserver(this);
    _readerControllerEvent.unsubscribe(_onPageControl);
    if (_didAddVolumeListen) delVolumeListen();
    unawaited(_systemUiLease?.release());
    final providers = _providers.values.toList();
    final chapter = widget.chapter;
    void release() {
      for (final name in chapter.images) {
        evictPageImageMemoryCache(chapter.id, name, includeLive: true);
      }
      for (final provider in providers) {
        imageCache.evict(provider, includeLive: true);
      }
    }

    release();
    WidgetsBinding.instance.addPostFrameCallback((_) => release());
    super.dispose();
  }

  void _toggleFullscreen() {
    if (!mounted) return;
    setState(() => _fullScreen = !_fullScreen);
    unawaited(_systemUiLease?.setFullScreen(_fullScreen).catchError((_) {}));
  }

  void _handleTap(TapUpDetails details, Size size) {
    switch (currentReaderControllerType) {
      case ReaderControllerType.touchOnce:
        _toggleFullscreen();
        break;
      case ReaderControllerType.touchDoubleOnceNext:
        _onPageControl(_ReaderControllerEventArgs('DOWN'));
        break;
      case ReaderControllerType.threeArea:
        var fraction = widget.readerDirection == ReaderDirection.topToBottom
            ? details.localPosition.dy / size.height
            : details.localPosition.dx / size.width;
        if (widget.readerDirection == ReaderDirection.rightToLeft) {
          fraction = 1 - fraction;
        }
        if (fraction < 1 / 3) {
          _onPageControl(_ReaderControllerEventArgs('UP'));
        } else if (fraction > 2 / 3) {
          _onPageControl(_ReaderControllerEventArgs('DOWN'));
        } else {
          _toggleFullscreen();
        }
        break;
      case ReaderControllerType.controller:
      case ReaderControllerType.touchDouble:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sideSlider =
        currentReaderSliderPosition != ReaderSliderPosition.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: !_fullScreen && !sideSlider,
      appBar: _fullScreen
          ? null
          : AppBar(
              title: Text(widget.chapter.name),
              actions: [
                IconButton(
                    onPressed: _onChooseEp, icon: const Icon(Icons.menu_open)),
                IconButton(
                    onPressed: _onMoreSetting,
                    icon: const Icon(Icons.more_horiz)),
              ],
            ),
      body: Stack(children: [
        Positioned.fill(child: _buildViewer()),
        if (!_fullScreen && sideSlider)
          Align(
            alignment: currentReaderSliderPosition == ReaderSliderPosition.left
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Container(
                width: 36,
                height: 300,
                color: const Color(0x88000000),
                child: _buildSliderWidget(Axis.vertical)),
          ),
        if (currentReaderControllerType == ReaderControllerType.controller &&
            (_fullScreen || sideSlider))
          SafeArea(
              child: Align(
            alignment: Alignment.bottomLeft,
            child: IconButton(
                onPressed: _toggleFullscreen,
                color: Colors.white,
                icon: Icon(
                    _fullScreen ? Icons.fullscreen_exit : Icons.fullscreen)),
          )),
        if (_position.preview != null)
          IgnorePointer(
              child: Center(
                  child: Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xAA000000),
            child: Text('${_slider + 1} / ${widget.chapter.images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 28)),
          ))),
      ]),
      bottomNavigationBar: _fullScreen || sideSlider
          ? null
          : ColoredBox(
              key: const ValueKey('reader-bottom-controls'),
              color: const Color(0x88000000),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 45,
                  child: Row(children: [
                    IconButton(
                        onPressed: _toggleFullscreen,
                        color: Colors.white,
                        icon: const Icon(Icons.fullscreen)),
                    Expanded(
                      child: _buildSliderWidget(Axis.horizontal),
                    ),
                    Text('${_slider + 1}/${widget.chapter.images.length}',
                        style: const TextStyle(color: Colors.white)),
                    IconButton(
                        onPressed: _onNextAction,
                        color: Colors.white,
                        icon: const Icon(Icons.skip_next_outlined)),
                  ]),
                ),
              ),
            ),
    );
  }

  Widget _buildSliderWidget(Axis axis) {
    if (widget.chapter.images.length <= 1) return const SizedBox.shrink();
    return FlutterSlider(
      axis: axis,
      handlerWidth: 14,
      handlerHeight: 14,
      touchSize: 17,
      handler: FlutterSliderHandler(
        decoration: const BoxDecoration(),
        child: const DecoratedBox(
          key: ValueKey('reader-progress-thumb'),
          decoration:
              BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: SizedBox.expand(),
        ),
      ),
      handlerAnimation: const FlutterSliderHandlerAnimation(scale: 1),
      trackBar: FlutterSliderTrackBar(
        activeTrackBarHeight: 3,
        inactiveTrackBarHeight: 3,
        inactiveTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.grey.shade300,
        ),
        activeTrackBar: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      values: [_slider.toDouble()],
      min: 0,
      max: (widget.chapter.images.length - 1).toDouble(),
      onDragStarted: (_, __, ___) =>
          setState(() => _position.preview = _current),
      onDragging: (_, value, __) =>
          setState(() => _position.preview = _position.clamp(value.toInt())),
      onDragCompleted: (_, value, __) => _needJumpTo(value.toInt(), false),
      step: const FlutterSliderStep(step: 1, isPercentRange: false),
      tooltip: FlutterSliderTooltip(disabled: true),
    );
  }

  int? get _nextChapterId {
    final entries = _sortReaderSeries(_series);
    final index = entries.indexWhere((entry) => entry.id == widget.chapter.id);
    return index >= 0 && index + 1 < entries.length
        ? entries[index + 1].id
        : null;
  }

  Future<void> _navigate(int id) async {
    if (!mounted || _navigationInFlight) return;
    _navigationInFlight = true;
    _progressWriter.schedule(_current);
    unawaited(_progressWriter.flush());
    try {
      await widget.onChangeEp(id, _fullScreen);
    } catch (error) {
      debugPrient('reader chapter navigation failed: ${error.runtimeType}');
    } finally {
      _navigationInFlight = false;
    }
  }

  Future<void> _onNextAction() async {
    final next = _nextChapterId;
    if (next != null) {
      await _navigate(next);
    } else if (mounted) {
      defaultToast(
          context, context.l10n.tr('已经到头了', en: 'You have reached the end'));
    }
  }

  Widget _buildNextEp() => Padding(
      padding: EdgeInsets.only(
          bottom: !_fullScreen &&
                  currentReaderSliderPosition == ReaderSliderPosition.bottom
              ? 45 + MediaQuery.viewPaddingOf(context).bottom
              : 0),
      child: SizedBox(
          height: 100,
          child: Center(
            child: TextButton(
              onPressed: _nextChapterId != null
                  ? _onNextAction
                  : () => Navigator.maybePop(context),
              child: Text(_nextChapterId != null
                  ? context.l10n.tr('下一章', en: 'Next chapter')
                  : context.l10n.tr('结束阅读', en: 'Finish reading')),
            ),
          )));

  List<Series> get _series => widget.chapter.series.isEmpty
      ? widget.fallbackSeries
      : widget.chapter.series;

  Future<void> _onChooseEp() async {
    if (_modalInFlight || _navigationInFlight) return;
    _modalInFlight = true;
    try {
      await showMaterialModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xDD000000),
        builder: (_) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .45,
            child: _EpChooser(widget.chapter, (id, _) => _navigate(id),
                series: _series)),
      );
    } catch (error) {
      debugPrient('reader chapter chooser failed: ${error.runtimeType}');
    } finally {
      _modalInFlight = false;
    }
  }

  Future<void> _onMoreSetting() async {
    if (_modalInFlight || _navigationInFlight) return;
    _modalInFlight = true;
    try {
      await showMaterialModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xDD000000),
          builder: (_) => SizedBox(
              height: MediaQuery.sizeOf(context).height / 2,
              child: _SettingPanel()));
    } catch (error) {
      debugPrient('reader settings failed: ${error.runtimeType}');
      return;
    } finally {
      _modalInFlight = false;
    }
    if (!mounted) return;
    if (widget.readerDirection != currentReaderDirection ||
        widget.readerType != currentReaderType) {
      _progressWriter.schedule(_current);
      unawaited(_progressWriter.flush());
      await widget.reload(_current, _fullScreen);
    } else {
      setState(() {});
    }
  }
}

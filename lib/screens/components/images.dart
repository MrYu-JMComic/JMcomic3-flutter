import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/screens/components/types.dart';

import '../file_photo_view_screen.dart';

//JM3x4Cover
class JM3x4ImageProvider extends ImageProvider<JM3x4ImageProvider> {
  final int comicId;
  final double scale;

  JM3x4ImageProvider(this.comicId, {this.scale = 1.0});

  @override
  ImageStreamCompleter loadBuffer(
    JM3x4ImageProvider key,
    DecoderBufferCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithBuffer(key, decode),
      scale: key.scale,
    );
  }

  @override
  ImageStreamCompleter loadImage(
    JM3x4ImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithImage(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<JM3x4ImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<JM3x4ImageProvider>(this);
  }

  Future<ui.Codec> _loadAsyncWithBuffer(
    JM3x4ImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    assert(key == this);
    final bytes =
        await File(await _cachedJm3x4CoverPath(comicId)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<ui.Codec> _loadAsyncWithImage(
    JM3x4ImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final bytes =
        await File(await _cachedJm3x4CoverPath(comicId)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    final JM3x4ImageProvider typedOther = other as JM3x4ImageProvider;
    return comicId == typedOther.comicId && scale == typedOther.scale;
  }

  @override
  int get hashCode => Object.hash(comicId, scale);

  @override
  String toString() => '$runtimeType('
      ' comicId: ${describeIdentity(comicId)},'
      ' scale: $scale'
      ')';
}

//JM3x4Cover
class PageImageProvider extends ImageProvider<PageImageProvider> {
  final int id;
  final String imageName;
  final double scale;

  PageImageProvider(this.id, this.imageName, {this.scale = 1.0});

  @override
  ImageStreamCompleter loadBuffer(
    PageImageProvider key,
    DecoderBufferCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithBuffer(key, decode),
      scale: key.scale,
    );
  }

  @override
  ImageStreamCompleter loadImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsyncWithImage(key, decode),
      scale: key.scale,
    );
  }

  @override
  Future<PageImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<PageImageProvider>(this);
  }

  Future<ui.Codec> _loadAsyncWithBuffer(
    PageImageProvider key,
    DecoderBufferCallback decode,
  ) async {
    assert(key == this);
    final bytes =
        await File(await _cachedPageImagePath(id, imageName)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<ui.Codec> _loadAsyncWithImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final bytes =
        await File(await _cachedPageImagePath(id, imageName)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    final PageImageProvider typedOther = other as PageImageProvider;
    return id == typedOther.id &&
        imageName == typedOther.imageName &&
        scale == typedOther.scale;
  }

  @override
  int get hashCode => Object.hash(id, imageName, scale);

  @override
  String toString() => '$runtimeType('
      ' id: ${describeIdentity(id)},'
      ' imageName: ${describeIdentity(imageName)},'
      ' scale: $scale'
      ')';
}

const _pageImagePathCacheLimit = 800;
const _pageImageTrueSizeCacheLimit = 800;
const _coverPathCacheLimit = 400;
const _photoPathCacheLimit = 400;

final Map<int, Future<String>> _jm3x4CoverPathFutureCache = {};
final Map<int, Future<String>> _jmSquareCoverPathFutureCache = {};
final Map<String, Future<String>> _photoPathFutureCache = {};
final Map<String, Future<String>> _pageImagePathFutureCache = {};
final Map<String, Future<Size>> _pageImageTrueSizeFutureCache = {};

String _pageImageCacheKey(int id, String imageName) => "$id/$imageName";

T _putCacheWithLimit<K, T>(
  Map<K, T> cache,
  K key,
  T value,
  int limit,
) {
  if (!cache.containsKey(key) && cache.length >= limit) {
    cache.remove(cache.keys.first);
  }
  cache[key] = value;
  return value;
}

Future<String> _cachePathFuture<K>({
  required Map<K, Future<String>> cache,
  required K key,
  required Future<String> Function() loader,
  required int limit,
}) {
  final cached = cache[key];
  if (cached != null) {
    return cached;
  }
  Future<String>? currentFuture;
  currentFuture = loader().then((path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) {
      throw StateError("empty image path");
    }
    final file = File(normalized);
    if (!await file.exists()) {
      throw StateError("image file not found: $normalized");
    }
    if (await file.length() <= 0) {
      throw StateError("image file empty: $normalized");
    }
    return normalized;
  }).catchError((Object error, StackTrace stackTrace) {
    // A forced refresh may have replaced this Future while the old request
    // was still in flight. Only evict when the cache still points at the
    // failing Future; otherwise an old failure could remove the new value.
    if (identical(cache[key], currentFuture)) {
      cache.remove(key);
    }
    Error.throwWithStackTrace(error, stackTrace);
  });
  return _putCacheWithLimit(cache, key, currentFuture, limit);
}

Future<String> _cachedJm3x4CoverPath(
  int comicId, {
  bool forceRefresh = false,
}) {
  if (forceRefresh) {
    _jm3x4CoverPathFutureCache.remove(comicId);
  }
  return _cachePathFuture(
    cache: _jm3x4CoverPathFutureCache,
    key: comicId,
    loader: () => methods.jm3x4Cover(comicId),
    limit: _coverPathCacheLimit,
  );
}

Future<String> _cachedJmSquareCoverPath(
  int comicId, {
  bool forceRefresh = false,
}) {
  if (forceRefresh) {
    _jmSquareCoverPathFutureCache.remove(comicId);
  }
  return _cachePathFuture(
    cache: _jmSquareCoverPathFutureCache,
    key: comicId,
    loader: () => methods.jmSquareCover(comicId),
    limit: _coverPathCacheLimit,
  );
}

Future<String> _cachedPhotoPath(
  String photoName, {
  bool forceRefresh = false,
}) {
  if (forceRefresh) {
    _photoPathFutureCache.remove(photoName);
  }
  return _cachePathFuture(
    cache: _photoPathFutureCache,
    key: photoName,
    loader: () => methods.jmPhotoImage(photoName),
    limit: _photoPathCacheLimit,
  );
}

Future<String> _cachedPageImagePath(
  int id,
  String imageName, {
  bool forceRefresh = false,
}) {
  final key = _pageImageCacheKey(id, imageName);
  if (forceRefresh) {
    _pageImagePathFutureCache.remove(key);
  }
  return _cachePathFuture(
    cache: _pageImagePathFutureCache,
    key: key,
    loader: () => methods.jmPageImage(id, imageName),
    limit: _pageImagePathCacheLimit,
  );
}

Future<Size> _cachedPageImageTrueSize(
  int id,
  String imageName,
  String path, {
  bool forceRefresh = false,
}) async {
  final key = _pageImageCacheKey(id, imageName);
  if (forceRefresh) {
    _pageImageTrueSizeFutureCache.remove(key);
  }
  final cached = _pageImageTrueSizeFutureCache[key];
  if (cached != null) {
    return cached;
  }
  Future<Size>? currentFuture;
  currentFuture = methods.imageSize(path).then((imageSize) {
    return Size(imageSize.w.toDouble(), imageSize.h.toDouble());
  }).catchError((Object error, StackTrace stackTrace) {
    if (identical(_pageImageTrueSizeFutureCache[key], currentFuture)) {
      _pageImageTrueSizeFutureCache.remove(key);
    }
    Error.throwWithStackTrace(error, stackTrace);
  });
  // 阅读器同一页可能被预加载、当前页和双页模式同时请求尺寸；缓存 Future 可以合并并发桥接调用。
  return _putCacheWithLimit(
    _pageImageTrueSizeFutureCache,
    key,
    currentFuture,
    _pageImageTrueSizeCacheLimit,
  );
}

void _evictPageImageCache(int id, String imageName) {
  final key = _pageImageCacheKey(id, imageName);
  _pageImagePathFutureCache.remove(key);
  _pageImageTrueSizeFutureCache.remove(key);
}

/// Evict one page image's in-memory path and size cache.
void evictPageImageMemoryCache(int id, String imageName) {
  _evictPageImageCache(id, imageName);
}

@visibleForTesting
Future<Size> cachedPageImageTrueSizeForTest(
  int id,
  String imageName,
  String path, {
  bool forceRefresh = false,
}) {
  return _cachedPageImageTrueSize(
    id,
    imageName,
    path,
    forceRefresh: forceRefresh,
  );
}

/// Clear all in-memory image path and size caches.
void clearAllImageMemoryCaches() {
  _jm3x4CoverPathFutureCache.clear();
  _jmSquareCoverPathFutureCache.clear();
  _photoPathFutureCache.clear();
  _pageImagePathFutureCache.clear();
  _pageImageTrueSizeFutureCache.clear();
}

// 远端图片
class JM3x4Cover extends StatefulWidget {
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  const JM3x4Cover({
    Key? key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JM3x4CoverState();
}

class _JM3x4CoverState extends State<JM3x4Cover> {
  late Future<String> _future;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = _cachedJm3x4CoverPath(widget.comicId);
  }

  @override
  void didUpdateWidget(covariant JM3x4Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = _cachedJm3x4CoverPath(widget.comicId);
    }
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _cachedJm3x4CoverPath(widget.comicId, forceRefresh: true);
    });
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) {
      return;
    }
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) {
        return;
      }
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      longPressMenuItems: widget.longPressMenuItems,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
    );
  }
}

// 远端图片
class JMSquareCover extends StatefulWidget {
  final int comicId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final List<LongPressMenuItem>? longPressMenuItems;

  const JMSquareCover({
    Key? key,
    required this.comicId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.longPressMenuItems,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMSquareCoverState();
}

class _JMSquareCoverState extends State<JMSquareCover> {
  late Future<String> _future;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = _cachedJmSquareCoverPath(widget.comicId);
  }

  @override
  void didUpdateWidget(covariant JMSquareCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comicId != widget.comicId) {
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = _cachedJmSquareCoverPath(widget.comicId);
    }
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _cachedJmSquareCoverPath(widget.comicId, forceRefresh: true);
    });
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) {
      return;
    }
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) {
        return;
      }
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      longPressMenuItems: widget.longPressMenuItems,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
    );
  }
}

class JMPhotoImage extends StatefulWidget {
  final String photoName;

  final double? width;
  final double? height;
  final BoxFit fit;

  const JMPhotoImage({
    Key? key,
    required this.photoName,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMPhotoImageState();
}

class _JMPhotoImageState extends State<JMPhotoImage> {
  late Future<String> _future;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = _cachedPhotoPath(widget.photoName);
  }

  @override
  void didUpdateWidget(covariant JMPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoName != widget.photoName) {
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = _cachedPhotoPath(widget.photoName);
    }
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _cachedPhotoPath(widget.photoName, forceRefresh: true);
    });
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) {
      return;
    }
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) {
        return;
      }
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      fit: widget.fit,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
    );
  }
}

//
class JMPageImage extends StatefulWidget {
  final int id;
  final String imageName;
  final double? width;
  final double? height;
  final Function(Size size)? onTrueSize;

  const JMPageImage(this.id, this.imageName,
      {Key? key, this.width, this.height, this.onTrueSize})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _JMPageImageState();
}

class _JMPageImageState extends State<JMPageImage> {
  late Future<String> _future;
  int _generation = 0;
  int _autoRetryCount = 0;
  bool _autoRetryQueued = false;

  @override
  void initState() {
    super.initState();
    _future = _init();
  }

  @override
  void didUpdateWidget(covariant JMPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.imageName != widget.imageName) {
      _generation++;
      _autoRetryCount = 0;
      _autoRetryQueued = false;
      _future = _init();
    }
  }

  Future<String> _init({bool forceRefresh = false}) async {
    final generation = _generation;
    final id = widget.id;
    final imageName = widget.imageName;
    final onTrueSize = widget.onTrueSize;
    final _path = await _cachedPageImagePath(
      id,
      imageName,
      forceRefresh: forceRefresh,
    );
    // A newer widget/reload may have replaced this request while the path was
    // loading. Do not start a force-refresh size lookup from the stale
    // request, since it could evict the newer size Future for the same key.
    if (!mounted || generation != _generation ||
        widget.id != id || widget.imageName != imageName) {
      return _path;
    }
    if (onTrueSize != null) {
      // Check again immediately before the size bridge call. The path Future
      // can complete while a newer widget/reload is being installed; without
      // this second guard the stale request would still perform I/O and could
      // populate the size cache for a page that is no longer mounted.
      if (!mounted || generation != _generation ||
          widget.id != id || widget.imageName != imageName) {
        return _path;
      }
      final size = await _cachedPageImageTrueSize(
        id,
        imageName,
        _path,
        forceRefresh: forceRefresh,
      );
      // Do not let an old request publish into a reused State whose widget
      // identity has changed while the request was in flight.
      if (mounted && generation == _generation &&
          widget.id == id && widget.imageName == imageName) {
        onTrueSize(size);
      }
    }
    return _path;
  }

  void _reload() {
    _generation++;
    _evictPageImageCache(widget.id, widget.imageName);
    if (!mounted) {
      return;
    }
    setState(() {
      _future = _init(forceRefresh: true);
    });
  }

  void _autoRetryOnDecodeError() {
    if (_autoRetryCount >= 1 || _autoRetryQueued) {
      return;
    }
    _autoRetryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoRetryQueued = false;
      if (!mounted) {
        return;
      }
      _autoRetryCount++;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 按 future 状态渲染图片
    return pathFutureImage(
      context,
      _future,
      widget.width,
      widget.height,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
    );
  }
}

Widget pathFutureImage(
    BuildContext context, Future<String> future, double? width, double? height,
    {BoxFit fit = BoxFit.cover,
    List<LongPressMenuItem>? longPressMenuItems,
    VoidCallback? onReload,
    VoidCallback? onDecodeError}) {
  // 使用 FutureBuilder 渲染加载/错误/成功状态
  return FutureBuilder<String>(
      future: future,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        if (snapshot.hasError) {
          debugPrient("${snapshot.error}");
          debugPrient("${snapshot.stackTrace}");
          return buildError(
            context,
            width,
            height,
            longPressMenuItems: longPressMenuItems,
            onReload: onReload,
          );
        }
        // 检查是否完成
        if (snapshot.connectionState == ConnectionState.done) {
          return buildFile(
            context,
            snapshot.data!,
            width,
            height,
            fit: fit,
            longPressMenuItems: longPressMenuItems,
            onReload: onReload,
            onDecodeError: onDecodeError,
          );
        }
        // 其他状态（waiting/active/none）显示加载状态
        return buildLoading(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
        );
      });
}

// 通用方法

Widget buildSvg(String source, double? width, double? height,
    {Color? color, double? margin}) {
  final widget = Container(
    width: width,
    height: height,
    padding: margin != null ? const EdgeInsets.all(10) : null,
    child: Center(
      child: SvgPicture.asset(
        source,
        width: width,
        height: height,
        color: color,
      ),
    ),
  );
  return GestureDetector(onLongPress: () {}, child: widget);
}

Widget buildMock(double? width, double? height) {
  final widget = Container(
    width: width,
    height: height,
    padding: const EdgeInsets.all(10),
    child: Center(
      child: SvgPicture.asset(
        'lib/assets/unknown.svg',
        width: width,
        height: height,
        color: Colors.grey.shade600,
      ),
    ),
  );
  return GestureDetector(onLongPress: () {}, child: widget);
}

Widget buildError(BuildContext context, double? width, double? height,
    {List<LongPressMenuItem>? longPressMenuItems, VoidCallback? onReload}) {
  double? size;
  if (width != null && height != null) {
    size = width < height ? width : height;
  }
  final error = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(
        Icons.error_outline,
        size: size,
        color: Colors.grey,
      ),
    ),
  );
  if (onReload != null ||
      (longPressMenuItems != null && longPressMenuItems.isNotEmpty)) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () async {
        final reloadText = context.l10n.tr('重新加载', en: 'Reload');
        List<String> menuItems = [];
        if (onReload != null) {
          menuItems.add(reloadText);
        }
        if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
          menuItems.addAll(longPressMenuItems.map((e) => e.title));
        }
        if (menuItems.isEmpty) return;

        String? choose = await chooseListDialog(
          context,
          title: context.l10n.choose,
          values: menuItems,
        );
        if (choose == reloadText && onReload != null) {
          onReload();
        } else {
          for (var item in longPressMenuItems ?? []) {
            if (item.title == choose) {
              item.onChoose();
              break;
            }
          }
        }
      },
      child: error,
    );
  }
  return error;
}

Widget buildLoading(BuildContext context, double? width, double? height,
    {List<LongPressMenuItem>? longPressMenuItems}) {
  double? size;
  if (width != null && height != null) {
    size = width < height ? width : height;
  }
  final loading = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(
        Icons.downloading,
        size: size,
        color: Colors.grey.withAlpha(150),
      ),
    ),
  );
  if (longPressMenuItems != null && longPressMenuItems.isNotEmpty) {
    return GestureDetector(
      onLongPress: () async {
        String? choose = await chooseListDialog(
          context,
          title: context.l10n.choose,
          values: longPressMenuItems.map((e) => e.title).toList(),
        );
        for (var item in longPressMenuItems) {
          if (item.title == choose) {
            item.onChoose();
            break;
          }
        }
      },
      child: loading,
    );
  }
  return loading;
}

int? _cacheExtent(double? logicalExtent, double devicePixelRatio) {
  if (logicalExtent == null || logicalExtent <= 0) {
    return null;
  }
  final value = (logicalExtent * devicePixelRatio).round();
  return value > 0 ? value : null;
}

Widget buildFile(
    BuildContext context, String file, double? width, double? height,
    {BoxFit fit = BoxFit.cover,
    List<LongPressMenuItem>? longPressMenuItems,
    VoidCallback? onReload,
    VoidCallback? onDecodeError}) {
  final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  final cacheWidth = _cacheExtent(width, devicePixelRatio);
  final cacheHeight = _cacheExtent(height, devicePixelRatio);
  final image = Image(
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      FileImage(File(file)),
    ),
    width: width,
    height: height,
    errorBuilder: (a, b, c) {
      debugPrient("$b");
      debugPrient("$c");
      onDecodeError?.call();
      return buildError(
        context,
        width,
        height,
        longPressMenuItems: longPressMenuItems,
        onReload: onReload,
      );
    },
    fit: fit,
  );
  return GestureDetector(
    onLongPress: () async {
      final previewText = context.l10n.tr('预览图片', en: 'Preview image');
      final saveToGalleryText =
          context.l10n.tr('保存图片到相册', en: 'Save image to gallery');
      final saveToFileText =
          context.l10n.tr('保存图片到文件', en: 'Save image to file');
      String? choose = await chooseListDialog(
        context,
        title: context.l10n.choose,
        values: [
          previewText,
          ...Platform.isAndroid || Platform.isIOS
              ? [
                  saveToGalleryText,
                ]
              : [],
          ...!Platform.isIOS
              ? [
                  saveToFileText,
                ]
              : [],
          ...longPressMenuItems?.map((e) => e.title) ?? [],
        ],
      );
      if (choose == previewText) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => FilePhotoViewScreen(file),
        ));
      } else if (choose == saveToGalleryText) {
        saveImageFileToGallery(context, file);
      } else if (choose == saveToFileText) {
        saveImageFileToFile(context, file);
      } else {
        for (var item in longPressMenuItems ?? []) {
          if (item.title == choose) {
            item.onChoose();
            break;
          }
        }
      }
    },
    child: image,
  );
}

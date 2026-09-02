import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'dart:io';
import 'dart:math' as math;
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
    final bytes = await File(
      await _cachedJm3x4CoverPath(comicId),
    ).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  Future<ui.Codec> _loadAsyncWithImage(
    JM3x4ImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final bytes = await File(
      await _cachedJm3x4CoverPath(comicId),
    ).readAsBytes();
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
  String toString() =>
      '$runtimeType('
      ' comicId: ${describeIdentity(comicId)},'
      ' scale: $scale'
      ')';
}

//JM3x4Cover
class PageImageProvider extends ImageProvider<PageImageProvider> {
  final int id;
  final String imageName;
  final double scale;

  /// Optional source-page identity.  The transport still uses [imageName],
  /// but the source index keeps two malformed/legacy entries with the same
  /// name from sharing a Flutter image-cache key.
  final int? pageIndex;

  /// Optional codec target in physical pixels.  This is deliberately a
  /// property of the Flutter provider only: the file resolved by
  /// [_cachedPageImagePath] is still the canonical, fully decrypted image.
  final int? cacheWidth;
  final int? cacheHeight;

  /// Optional already-resolved canonical path, used by offline readers and
  /// tests.  It is never a network URL and is validated for existence before
  /// handing bytes to the codec.
  final String? localPath;

  /// When true, a missing [localPath] is a hard local-only failure.  This is
  /// used by the opt-in offline owner so metadata-only pages never silently
  /// fall back to an online bridge request.
  final bool localOnly;

  PageImageProvider(
    this.id,
    this.imageName, {
    this.scale = 1.0,
    int? pageIndex,
    int? cacheWidth,
    int? cacheHeight,
    String? localPath,
    this.localOnly = false,
  }) : pageIndex = _normalizePageIndex(pageIndex),
       cacheWidth = _normalizeDecodeTarget(cacheWidth),
       cacheHeight = _normalizeDecodeTarget(cacheHeight),
       localPath = _normalizeLocalPath(localPath);

  Future<String> _pathForKey(PageImageProvider key) async {
    final supplied = key.localPath;
    if (supplied != null) {
      return _validateLocalImagePath(supplied);
    }
    if (key.localOnly) {
      throw StateError('local image unavailable');
    }
    return _cachedPageImagePath(key.id, key.imageName);
  }

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

  /// Direct codec hook for deterministic fixture tests. Production callers
  /// should resolve the provider through [Image] so Flutter's image cache and
  /// lifecycle remain in charge.
  @visibleForTesting
  Future<ui.Codec> loadCodecForTest() => _loadAsyncWithImage(
    this,
    PaintingBinding.instance.instantiateImageCodecWithSize,
  );

  /// Exercise the deprecated buffer decoder path too. Some supported Flutter
  /// runtimes still resolve providers through [loadBuffer], so its fit logic
  /// must stay equivalent to [loadImage].
  @visibleForTesting
  Future<ui.Codec> loadBufferCodecForTest() => _loadAsyncWithBuffer(
    this,
    // ignore: deprecated_member_use
    PaintingBinding.instance.instantiateImageCodecFromBuffer,
  );

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
    final bytes = await File(await _pathForKey(key)).readAsBytes();
    final width = key.cacheWidth;
    final height = key.cacheHeight;
    if (width == null && height == null) {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    }
    try {
      // DecoderBufferCallback has no getTargetSize hook. Inspect metadata with
      // an independent buffer, then pass only the limiting edge to the legacy
      // decoder. Passing an exact width/height pair can distort the page;
      // picking the fitted edge keeps both bounds and the source ratio.
      final metadataBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.TargetImageSize target;
      try {
        descriptor = await ui.ImageDescriptor.encoded(metadataBuffer);
        target = _fitDecodeTargetSize(
          descriptor.width,
          descriptor.height,
          width,
          height,
        );
      } finally {
        descriptor?.dispose();
        metadataBuffer.dispose();
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(
        buffer,
        cacheWidth: target.width,
        cacheHeight: target.height,
        allowUpscaling: false,
      );
    } catch (_) {
      // A decoder/plugin may reject a target-size request even though the
      // canonical image is valid. Retry the same canonical bytes without a
      // target so an optimization failure cannot turn into a page failure.
      final fallbackBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(fallbackBuffer);
    }
  }

  Future<ui.Codec> _loadAsyncWithImage(
    PageImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final bytes = await File(await _pathForKey(key)).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final width = key.cacheWidth;
    final height = key.cacheHeight;
    if (width == null && height == null) {
      return decode(buffer);
    }
    try {
      return await decode(
        buffer,
        getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
          return _fitDecodeTargetSize(
            intrinsicWidth,
            intrinsicHeight,
            width,
            height,
          );
        },
      );
    } catch (_) {
      final fallbackBuffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(fallbackBuffer);
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    final PageImageProvider typedOther = other as PageImageProvider;
    return id == typedOther.id &&
        imageName == typedOther.imageName &&
        scale == typedOther.scale &&
        pageIndex == typedOther.pageIndex &&
        cacheWidth == typedOther.cacheWidth &&
        cacheHeight == typedOther.cacheHeight &&
        localPath == typedOther.localPath &&
        localOnly == typedOther.localOnly;
  }

  @override
  int get hashCode => Object.hash(
    id,
    imageName,
    scale,
    pageIndex,
    cacheWidth,
    cacheHeight,
    localPath,
    localOnly,
  );

  @override
  String toString() =>
      '$runtimeType('
      ' id: ${describeIdentity(id)},'
      ' imageName: ${describeIdentity(imageName)},'
      ' scale: $scale,'
      ' pageIndex: $pageIndex,'
      ' cacheWidth: $cacheWidth,'
      ' cacheHeight: $cacheHeight,'
      ' localPath: ${localPath == null ? '<cache>' : describeIdentity(localPath)},'
      ' localOnly: $localOnly'
      ')';
}

const _pageImagePathCacheLimit = 800;
const _pageImageTrueSizeCacheLimit = 800;
const _coverPathCacheLimit = 400;
const _photoPathCacheLimit = 400;

const _decodeTargetBuckets = <int>[256, 512, 768, 1024, 1536, 2048, 3072, 4096];

int? _normalizeDecodeTarget(int? value) {
  if (value == null || value <= 0) {
    return null;
  }
  for (final bucket in _decodeTargetBuckets) {
    if (value <= bucket) {
      return bucket;
    }
  }
  // Never let a caller create an unbounded image-cache key or request a
  // decoder target larger than the largest supported profile.
  return _decodeTargetBuckets.last;
}

int? _normalizePageIndex(int? value) =>
    value != null && value >= 0 ? value : null;

String? _normalizeLocalPath(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final Map<int, Future<String>> _jm3x4CoverPathFutureCache = {};
final Map<int, Future<String>> _jmSquareCoverPathFutureCache = {};
final Map<String, Future<String>> _photoPathFutureCache = {};
final Map<String, Future<String>> _pageImagePathFutureCache = {};
final Map<String, Future<Size>> _pageImageTrueSizeFutureCache = {};

String _pageImageCacheKey(int id, String imageName, {String? path}) {
  final normalizedPath = _normalizeLocalPath(path);
  return normalizedPath == null
      ? "$id/$imageName"
      : "$id/$imageName|$normalizedPath";
}

T _putCacheWithLimit<K, T>(Map<K, T> cache, K key, T value, int limit) {
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
  currentFuture = Future<String>.sync(loader)
      .then((path) async {
        final normalized = path.trim();
        if (normalized.isEmpty) {
          throw StateError("empty image path");
        }
        final file = File(normalized);
        try {
          final stat = await file.stat();
          if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
            throw const FileSystemException('image file unavailable');
          }
        } catch (_) {
          // Keep local paths out of error text; callers can classify this as a
          // missing/invalid image without exposing filesystem details.
          throw StateError("image file unavailable");
        }
        return normalized;
      })
      .catchError((Object error, StackTrace stackTrace) {
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

Future<String> _cachedJm3x4CoverPath(int comicId, {bool forceRefresh = false}) {
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

Future<String> _cachedPhotoPath(String photoName, {bool forceRefresh = false}) {
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
  final key = _pageImageCacheKey(id, imageName, path: path);
  if (forceRefresh) {
    _pageImageTrueSizeFutureCache.remove(key);
  }
  final cached = _pageImageTrueSizeFutureCache[key];
  if (cached != null) {
    return cached;
  }
  Future<Size>? currentFuture;
  currentFuture = Future<ImageSize>.sync(() => methods.imageSize(path))
      .then((imageSize) {
        if (imageSize.w <= 0 || imageSize.h <= 0) {
          // A successful bridge response with zero/negative dimensions is still a
          // malformed image contract. Do not let it poison the true-size cache or
          // make a list reader construct a zero-sized page.
          throw const FormatException('invalid image dimensions');
        }
        return Size(imageSize.w.toDouble(), imageSize.h.toDouble());
      })
      .catchError((Object error, StackTrace stackTrace) {
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
  // True-size entries include the resolved canonical path. Evict all variants
  // for this logical page so a migrated/offline file cannot reuse stale
  // dimensions from the previous path.
  final prefix = '$key|';
  _pageImageTrueSizeFutureCache.removeWhere(
    (cacheKey, _) => cacheKey == key || cacheKey.startsWith(prefix),
  );
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

  /// Stable source-page identity for duplicate image names.
  final int? pageIndex;

  /// Optional path already validated by the offline availability contract.
  /// When present, no network/bridge lookup is performed.
  final String? localPath;

  /// Prevents a metadata-only offline page from falling back to the network.
  final bool localOnly;
  final double? width;
  final double? height;
  final Function(Size size)? onTrueSize;

  const JMPageImage(
    this.id,
    this.imageName, {
    Key? key,
    this.pageIndex,
    this.localPath,
    this.localOnly = false,
    this.width,
    this.height,
    this.onTrueSize,
  }) : super(key: key);

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
    if (oldWidget.id != widget.id ||
        oldWidget.imageName != widget.imageName ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.localOnly != widget.localOnly ||
        oldWidget.localPath != widget.localPath) {
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
    final pageIndex = widget.pageIndex;
    final localOnly = widget.localOnly;
    final onTrueSize = widget.onTrueSize;
    final suppliedPath = widget.localPath?.trim();
    if ((suppliedPath == null || suppliedPath.isEmpty) && localOnly) {
      throw StateError('local image unavailable');
    }
    final _path = suppliedPath == null || suppliedPath.isEmpty
        ? await _cachedPageImagePath(id, imageName, forceRefresh: forceRefresh)
        : await _validateLocalImagePath(suppliedPath);
    // A newer widget/reload may have replaced this request while the path was
    // loading. Do not start a force-refresh size lookup from the stale
    // request, since it could evict the newer size Future for the same key.
    if (!mounted ||
        generation != _generation ||
        widget.id != id ||
        widget.imageName != imageName ||
        widget.pageIndex != pageIndex ||
        widget.localOnly != localOnly ||
        widget.localPath?.trim() != suppliedPath) {
      return _path;
    }
    if (onTrueSize != null) {
      // Check again immediately before the size bridge call. The path Future
      // can complete while a newer widget/reload is being installed; without
      // this second guard the stale request would still perform I/O and could
      // populate the size cache for a page that is no longer mounted.
      if (!mounted ||
          generation != _generation ||
          widget.id != id ||
          widget.imageName != imageName ||
          widget.pageIndex != pageIndex ||
          widget.localOnly != localOnly ||
          widget.localPath?.trim() != suppliedPath) {
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
      if (mounted &&
          generation == _generation &&
          widget.id == id &&
          widget.imageName == imageName &&
          widget.pageIndex == pageIndex &&
          widget.localOnly == localOnly &&
          widget.localPath?.trim() == suppliedPath) {
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
      offlineOnly: widget.localOnly,
      onReload: _reload,
      onDecodeError: _autoRetryOnDecodeError,
    );
  }
}

Future<String> _validateLocalImagePath(String path) async {
  final file = File(path);
  try {
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw const FileSystemException('image file unavailable');
    }
  } catch (_) {
    throw StateError('local image unavailable');
  }
  return path;
}

Widget pathFutureImage(
  BuildContext context,
  Future<String> future,
  double? width,
  double? height, {
  BoxFit fit = BoxFit.cover,
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
  VoidCallback? onDecodeError,
  bool offlineOnly = false,
}) {
  // 使用 FutureBuilder 渲染加载/错误/成功状态
  return FutureBuilder<String>(
    future: future,
    builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
      if (snapshot.hasError) {
        debugPrient("image load failed: ${snapshot.error.runtimeType}");
        debugPrient("image load stack: ${snapshot.stackTrace?.runtimeType}");
        if (offlineOnly) {
          return buildOfflineImageUnavailable(
            context,
            width,
            height,
            onReload: onReload,
          );
        }
        return buildError(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
          onReload: onReload,
        );
      }
      // 检查是否完成
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData &&
          snapshot.data!.trim().isNotEmpty) {
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
      if (snapshot.connectionState == ConnectionState.done) {
        debugPrient("image load failed: invalid result");
        if (offlineOnly) {
          return buildOfflineImageUnavailable(
            context,
            width,
            height,
            onReload: onReload,
          );
        }
        return buildError(
          context,
          width,
          height,
          longPressMenuItems: longPressMenuItems,
          onReload: onReload,
        );
      }
      // 其他状态（waiting/active/none）显示加载状态
      return buildLoading(
        context,
        width,
        height,
        longPressMenuItems: longPressMenuItems,
      );
    },
  );
}

/// A distinct state for an offline page whose metadata exists but whose
/// validated local file is missing or unreadable. Keeping this separate from
/// the generic network error makes the recovery action clear and prevents a
/// user from assuming that toggling network settings will fix the page.
Widget buildOfflineImageUnavailable(
  BuildContext context,
  double? width,
  double? height, {
  VoidCallback? onReload,
}) {
  final content = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: (width != null && height != null)
                  ? math.min(width, height).clamp(24.0, 56.0).toDouble()
                  : 32,
              color: Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.tr(
                '离线图片不可用，请重新下载',
                en: 'Offline image unavailable; download again',
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
  if (onReload == null) {
    return content;
  }
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onReload,
    child: content,
  );
}

// 通用方法

Widget buildSvg(
  String source,
  double? width,
  double? height, {
  Color? color,
  double? margin,
}) {
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

Widget buildError(
  BuildContext context,
  double? width,
  double? height, {
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
}) {
  double? size;
  if (width != null && height != null) {
    size = width < height ? width : height;
  }
  final error = SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Icon(Icons.error_outline, size: size, color: Colors.grey),
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

Widget buildLoading(
  BuildContext context,
  double? width,
  double? height, {
  List<LongPressMenuItem>? longPressMenuItems,
}) {
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
  if (logicalExtent == null ||
      !logicalExtent.isFinite ||
      logicalExtent <= 0 ||
      !devicePixelRatio.isFinite ||
      devicePixelRatio <= 0) {
    return null;
  }
  final value = (logicalExtent * devicePixelRatio).round();
  if (value <= 0) return null;
  // Keep the codec/cache key space bounded.  The source file remains the
  // canonical (fully decoded/decrypted) image; this only controls Flutter's
  // codec sampling target and therefore cannot affect decryption semantics.
  return _normalizeDecodeTarget(value);
}

/// Fits an intrinsic image inside optional physical-pixel bounds without ever
/// passing an exact two-dimensional codec target. The selected edge is enough
/// for Flutter to preserve aspect ratio, including in the deprecated buffer
/// decoder which does not expose a target-size callback.
ui.TargetImageSize _fitDecodeTargetSize(
  int intrinsicWidth,
  int intrinsicHeight,
  int? cacheWidth,
  int? cacheHeight,
) {
  assert(intrinsicWidth > 0);
  assert(intrinsicHeight > 0);

  if (cacheWidth == null && cacheHeight == null) {
    return const ui.TargetImageSize();
  }

  final widthScale = cacheWidth == null
      ? double.infinity
      : cacheWidth / intrinsicWidth;
  final heightScale = cacheHeight == null
      ? double.infinity
      : cacheHeight / intrinsicHeight;
  final limitByWidth =
      cacheWidth != null && (cacheHeight == null || widthScale <= heightScale);

  if (limitByWidth) {
    return ui.TargetImageSize(width: math.min(intrinsicWidth, cacheWidth));
  }

  return ui.TargetImageSize(height: math.min(intrinsicHeight, cacheHeight!));
}

@visibleForTesting
int? decodeTargetExtentForTest(
  double? logicalExtent,
  double devicePixelRatio,
) => _cacheExtent(logicalExtent, devicePixelRatio);

/// Exercise the same target-size codec contract as [PageImageProvider] with a
/// canonical (already decrypted) fixture, without creating an image stream.
/// This is test-only and never participates in the production cache path.
@visibleForTesting
Future<ui.Codec> decodeCanonicalPageBytesForTest(
  Uint8List bytes, {
  int? cacheWidth,
  int? cacheHeight,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  return ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (int intrinsicWidth, int intrinsicHeight) =>
        _fitDecodeTargetSize(
          intrinsicWidth,
          intrinsicHeight,
          _normalizeDecodeTarget(cacheWidth),
          _normalizeDecodeTarget(cacheHeight),
        ),
  );
}

/// Build the reader page provider for a concrete layout box.
///
/// `width`/`height` are logical Flutter pixels and are converted to bounded
/// physical codec targets.  The returned provider always resolves the same
/// canonical file as [PageImageProvider]; target decoding is never applied to
/// the scrambled network bytes or to the Rust cache writer.
PageImageProvider readerPageImageProvider(
  BuildContext context,
  int id,
  String imageName, {
  double? width,
  double? height,
  int? pageIndex,
  String? localPath,
  bool localOnly = false,
  bool enabled = true,
}) {
  if (!enabled) {
    return PageImageProvider(
      id,
      imageName,
      pageIndex: pageIndex,
      localPath: localPath,
      localOnly: localOnly,
    );
  }
  final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  return PageImageProvider(
    id,
    imageName,
    pageIndex: pageIndex,
    cacheWidth: _cacheExtent(width, devicePixelRatio),
    cacheHeight: _cacheExtent(height, devicePixelRatio),
    localPath: localPath,
    localOnly: localOnly,
  );
}

@visibleForTesting
PageImageProvider readerPageImageProviderForTest({
  required int id,
  required String imageName,
  double? width,
  double? height,
  int? pageIndex,
  String? localPath,
  bool localOnly = false,
  double devicePixelRatio = 1.0,
}) {
  return PageImageProvider(
    id,
    imageName,
    pageIndex: pageIndex,
    cacheWidth: _cacheExtent(width, devicePixelRatio),
    cacheHeight: _cacheExtent(height, devicePixelRatio),
    localPath: localPath,
    localOnly: localOnly,
  );
}

Widget buildFile(
  BuildContext context,
  String file,
  double? width,
  double? height, {
  BoxFit fit = BoxFit.cover,
  List<LongPressMenuItem>? longPressMenuItems,
  VoidCallback? onReload,
  VoidCallback? onDecodeError,
}) {
  final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
  final cacheWidth = _cacheExtent(width, devicePixelRatio);
  // ResizeImagePolicy.exact may interpret both dimensions literally and
  // distort covers. A single bound lets Flutter derive the other dimension.
  final cacheHeight = width != null && height != null
      ? null
      : _cacheExtent(height, devicePixelRatio);
  final image = Image(
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      FileImage(File(file)),
    ),
    width: width,
    height: height,
    errorBuilder: (a, b, c) {
      debugPrient("image decode failed: ${b.runtimeType}");
      debugPrient("image decode stack: ${c.runtimeType}");
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
      final saveToGalleryText = context.l10n.tr(
        '保存图片到相册',
        en: 'Save image to gallery',
      );
      final saveToFileText = context.l10n.tr(
        '保存图片到文件',
        en: 'Save image to file',
      );
      String? choose = await chooseListDialog(
        context,
        title: context.l10n.choose,
        values: [
          previewText,
          ...Platform.isAndroid || Platform.isIOS ? [saveToGalleryText] : [],
          ...!Platform.isIOS ? [saveToFileText] : [],
          ...longPressMenuItems?.map((e) => e.title) ?? [],
        ],
      );
      if (choose == previewText) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => FilePhotoViewScreen(file)),
        );
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

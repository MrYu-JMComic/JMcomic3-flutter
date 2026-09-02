import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/log.dart';

import 'backend_invoker.dart';
import 'method_response_decoder.dart';
import 'entities.dart';
import 'page_image_batch.dart';

export 'page_image_batch.dart';

export 'entities.dart';

const methods = Methods._();

class Methods {
  const Methods._();

  static const _channel = MethodChannel("methods");
  static HttpClient httpClient = HttpClient();
  static const Set<String> _downloadDebugMethods = {
    "all_downloads",
    "download_by_id",
    "create_download",
    "dl_image_by_chapter_id",
    "delete_download",
    "renew_all_downloads",
    "jm_3x4_cover",
    "jm_square_cover",
    "jm_page_image",
    "jm_photo_image",
    "image_size",
  };
  static const Duration _categoriesCacheTtl = Duration(minutes: 10);
  static const Duration _comicsCacheTtl = Duration(minutes: 5);
  static const Duration _albumCacheTtl = Duration(minutes: 10);
  static const Duration _coverCacheTtl = Duration(minutes: 30);
  static const String _defaultCategoriesCacheKey = "__default__";
  static const int _maxSearchHistoryCountHint = 200;
  static const int _downloadThreadMin = 1;
  static const int _downloadThreadMax = 5;

  static final Map<String, _CacheEntry<String>> _categoriesCache = {};
  static final Map<String, _CacheEntry<String>> _comicsCache = {};
  static final Map<String, _CacheEntry<String>> _albumCache = {};
  static final Map<String, _CacheEntry<String>> _coverCache = {};
  static final Map<String, Future<String>> _categoriesInflight = {};
  static final Map<String, Future<String>> _comicsInflight = {};
  static final Map<String, Future<String>> _albumInflight = {};
  static final Map<String, Future<String>> _coverInflight = {};
  static int _cacheEpoch = 0;

  void _clearResponseCaches() {
    _cacheEpoch++;
    _categoriesCache.clear();
    _comicsCache.clear();
    _albumCache.clear();
    _coverCache.clear();
    _categoriesInflight.clear();
    _comicsInflight.clear();
    _albumInflight.clear();
    _coverInflight.clear();
  }

  void _evictAlbumCache(int comicId) {
    _albumCache.removeWhere((key, _) => key.startsWith("$comicId|"));
    _albumInflight.removeWhere((key, _) => key.startsWith("$comicId|"));
  }

  bool _isLegacyArgumentContractError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('invalid-params') ||
        message.contains('invalid params') ||
        message.contains('unknown method') ||
        message.contains('not implemented in rust-frb backend');
  }

  Future<String> _loadCachedString({
    required String cacheKey,
    required Duration ttl,
    required Map<String, _CacheEntry<String>> cache,
    required Map<String, Future<String>> inflight,
    required Future<String> Function() loader,
    bool allowStaleOnError = false,
    String? debugName,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final current = cache[cacheKey];
    if (current != null &&
        (nowMs - current.createdAtMs) <= ttl.inMilliseconds) {
      if (debugName != null) {
        debugPrient("[api-cache-hit] method=$debugName key=$cacheKey");
      }
      return current.value;
    }

    final running = inflight[cacheKey];
    if (running != null) {
      if (debugName != null) {
        debugPrient("[api-cache-wait] method=$debugName key=$cacheKey");
      }
      return running;
    }

    final future = loader();
    final epoch = _cacheEpoch;
    inflight[cacheKey] = future;
    try {
      final value = await future;
      // A cache clear/account switch may have happened while this request was
      // in flight. Do not let the stale response repopulate the new session.
      if (epoch == _cacheEpoch && identical(inflight[cacheKey], future)) {
        cache[cacheKey] = _CacheEntry(
          value,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
      if (debugName != null) {
        debugPrient("[api-cache-store] method=$debugName key=$cacheKey");
      }
      return value;
    } catch (e) {
      if (allowStaleOnError && current != null && epoch == _cacheEpoch) {
        // 类别/封面等展示型接口在网络抖动时允许回退陈旧缓存，避免页面直接报错闪退。
        // 回退成功后刷新缓存时间戳，避免离线期间每次进入页面都立即重试并重复报错。
        cache[cacheKey] = _CacheEntry(
          current.value,
          DateTime.now().millisecondsSinceEpoch,
        );
        if (debugName != null) {
          debugPrient(
            "[api-cache-stale-fallback] method=$debugName key=$cacheKey errorType=${e.runtimeType}",
          );
        }
        return current.value;
      }
      rethrow;
    } finally {
      // Only remove our own request; a newer request may already occupy key.
      if (identical(inflight[cacheKey], future)) {
        inflight.remove(cacheKey);
      }
      if (cache.length > 600) {
        final removeCount = cache.length - 500;
        final keys = cache.keys.take(removeCount).toList();
        for (final key in keys) {
          cache.remove(key);
        }
      }
    }
  }

  bool _isLikelyProGateError(String method, String errorMessage) {
    final lower = errorMessage.toLowerCase();
    if (method == "get_pro_server_name" || method == "set_pro_server_name") {
      return false;
    }
    if (lower.contains("no flat")) {
      return false;
    }
    return errorMessage.contains("发电") ||
        lower.contains("please activate pro") ||
        lower.contains("pro is required") ||
        lower.contains("need pro") ||
        lower.contains("vip");
  }

  Future<String> _invokeRaw(String method, dynamic params) async {
    final injected = BackendInvokerRegistry.handler;
    if (injected != null) {
      return injected(method, params);
    }
    late String resp;
    // if (Platform.isLinux) {
    //   var req = await httpClient.post("127.0.0.1", 52764, "invoke");
    //   req.add(utf8.encode(jsonEncode({
    //     "method": method,
    //     "params": params is String ? params : jsonEncode(params),
    //   })));
    //   var rsp = await req.close();
    //   resp = await rsp.transform(utf8.decoder).join();
    // } else
    {
      resp = await _channel.invokeMethod(
        "invoke",
        jsonEncode({
          "method": method,
          "params": params is String ? params : jsonEncode(params),
        }),
      );
    }
    return resp;
  }

  Future<String> _invoke(String method, dynamic params) async {
    final shouldDebug = _downloadDebugMethods.contains(method);
    if (shouldDebug) {
      debugPrient(
        "[download-api:req] method=$method params=${_briefSafe(params)}",
      );
    }
    final resp = await _invokeRaw(method, params);
    final response = _Response.fromJson(jsonDecode(resp));

    if (response.errorMessage.isNotEmpty) {
      if (shouldDebug) {
        debugPrient(
          "[download-api:err] method=$method errorClass=${_errorClass(response.errorMessage)}",
        );
      }
      if (_isLikelyProGateError(method, response.errorMessage)) {
        debugPrient(
          "backend-pro-gate method=$method errorClass=${_errorClass(response.errorMessage)}",
        );
      }
      throw StateError(response.errorMessage);
    }
    if (shouldDebug) {
      debugPrient(
        "[download-api:rsp] method=$method data=${_briefSafe(response.responseData)}",
      );
    }
    return response.responseData;
  }

  String _brief(dynamic value) {
    final raw = value == null ? "null" : value.toString();
    if (raw.length <= 320) {
      return raw;
    }
    return "${raw.substring(0, 320)}...";
  }

  String _briefSafe(dynamic value) {
    dynamic sanitize(dynamic v, [String? key]) {
      if (key != null &&
          RegExp(
            r'(url|cookie|token|path|image_size)',
            caseSensitive: false,
          ).hasMatch(key)) {
        return '<redacted>';
      }
      if (v is Map) {
        return v.map((k, val) => MapEntry(k, sanitize(val, '$k')));
      }
      if (v is Iterable) return v.map((item) => sanitize(item)).toList();
      if (v is String &&
          (v.contains('://') || v.contains('\\') || v.contains('/'))) {
        return '<redacted-string>';
      }
      return v;
    }

    return _brief(sanitize(value));
  }

  String _errorClass(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('vip') ||
        lower.contains('pro') ||
        message.contains('发电')) {
      return 'pro-gate';
    }
    if (lower.contains('network') || lower.contains('timeout')) {
      return 'network';
    }
    return 'backend-error';
  }

  /// 后端整数响应历史上偶发过空串/非数字脏值；这里集中兜底，
  /// 避免调用点散落 `int.parse` 导致页面因单个字段异常直接抛错。
  int _parseBackendInt(String raw, String method, {required int fallback}) {
    final trimmed = raw.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed != null) {
      return parsed;
    }
    // 兼容历史桥接中偶发的双层 JSON 字符串（如 "\"3\""）或数值类型响应。
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is int) {
        return decoded;
      }
      if (decoded is String) {
        final decodedTrimmed = decoded.trim();
        final nestedParsed = int.tryParse(decodedTrimmed);
        if (nestedParsed != null) {
          return nestedParsed;
        }
        final nestedNum = num.tryParse(decodedTrimmed);
        if (nestedNum != null &&
            nestedNum.isFinite &&
            nestedNum == nestedNum.truncateToDouble()) {
          return nestedNum.toInt();
        }
      }
      if (decoded is num &&
          decoded.isFinite &&
          decoded == decoded.truncateToDouble()) {
        return decoded.toInt();
      }
    } on FormatException {
      // 非 JSON 形态继续走统一回退分支。
    }
    debugPrient(
      "[method-parse-int-fallback] method=$method raw=${_brief(raw)} fallback=$fallback",
    );
    return fallback;
  }

  /// 下载线程配置来自跨版本桥接与本地缓存，解析成功后仍需做边界归一化。
  /// 这样即使旧版本返回越界值，也不会把异常并发数直接传给 UI/调用链。
  int _normalizeDownloadThreadCount(int value, String method) {
    final normalized = value.clamp(_downloadThreadMin, _downloadThreadMax);
    if (normalized != value) {
      debugPrient(
        "[method-download-thread-clamp] method=$method raw=$value normalized=$normalized",
      );
    }
    return normalized;
  }

  /// 平台通道返回类型在不同设备/插件版本上可能是 List、单值、JSON 字符串或 null。
  /// 这里统一归一化为“去空白 + 去重”的字符串列表，避免设置页因返回形态差异崩溃。
  List<String> _normalizePlatformStringList(
    dynamic raw,
    String method, {
    bool dedupe = true,
  }) {
    dynamic source = raw;
    if (source == null) {
      return const <String>[];
    }
    if (source is String) {
      final trimmed = source.trim();
      if (trimmed.isEmpty) {
        return const <String>[];
      }
      try {
        final decoded = jsonDecode(trimmed);
        source = decoded;
      } on FormatException {
        source = <dynamic>[source];
      }
    }
    if (source is Map) {
      // 部分机型/插件版本返回对象壳（如 {"modes":[...] }），这里优先提取常见列表字段。
      const listKeys = <String>[
        "modes",
        "mode_list",
        "modeList",
        "items",
        "data",
      ];
      dynamic listPayload;
      for (final key in listKeys) {
        if (!source.containsKey(key)) {
          continue;
        }
        listPayload = source[key];
        break;
      }
      if (listPayload is String) {
        final trimmed = listPayload.trim();
        if (trimmed.isNotEmpty) {
          try {
            listPayload = jsonDecode(trimmed);
          } on FormatException {
            listPayload = <dynamic>[listPayload];
          }
        } else {
          listPayload = const <dynamic>[];
        }
      }
      if (listPayload is Iterable) {
        source = listPayload;
      } else if (listPayload != null) {
        source = <dynamic>[listPayload];
      } else {
        // 未命中约定字段时退化为值列表，避免把整张 Map 字符串化成单条脏数据。
        source = source.values;
      }
    }
    if (source is! Iterable) {
      source = <dynamic>[source];
    }

    final result = <String>[];
    final seen = dedupe ? <String>{} : null;
    for (final item in source) {
      if (item == null) {
        continue;
      }
      final normalized = "$item".trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (seen != null && !seen.add(normalized)) {
        continue;
      }
      result.add(normalized);
    }
    if (result.isEmpty && raw != null) {
      debugPrient(
        "[method-platform-list-empty] method=$method raw=${_brief(raw)}",
      );
    }
    return List<String>.unmodifiable(result);
  }

  Map<String, dynamic> _decodeMapResponse(
    String rsp,
    String method, {
    bool nullAsEmpty = false,
  }) {
    return decodeMapResponse(rsp, method, nullAsEmpty: nullAsEmpty);
  }

  T _decodeEntityResponse<T>(
    String rsp,
    String method,
    T Function(Map<String, dynamic>) mapper, {
    bool immutableItem = false,
    bool nullAsEmpty = false,
  }) {
    return decodeEntityResponse(
      rsp,
      method,
      mapper,
      immutableItem: immutableItem,
      nullAsEmpty: nullAsEmpty,
    );
  }

  List<T> _decodeEntityListResponse<T>(
    String rsp,
    String method,
    T Function(Map<String, dynamic>) mapper, {
    bool immutableItems = false,
  }) {
    return decodeEntityListResponse(
      rsp,
      method,
      mapper,
      immutableItems: immutableItems,
    );
  }

  T? _decodeNullableEntityResponse<T>(
    String rsp,
    String method,
    T Function(Map<String, dynamic>) mapper, {
    bool immutableItem = false,
  }) {
    return decodeNullableEntityResponse(
      rsp,
      method,
      mapper,
      immutableItem: immutableItem,
    );
  }

  List<String> _decodeStringListResponse(
    String rsp,
    String method, {
    bool dedupe = false,
  }) {
    return decodeStringListResponse(rsp, method, dedupe: dedupe);
  }

  Map<String, String> _decodeStringMapResponse(String rsp, String method) {
    return decodeStringMapResponse(rsp, method);
  }

  Future init() {
    return _invoke("init_dart", "");
  }

  Future<Map<String, String>> configLinks() async {
    return _decodeStringMapResponse(
      await _invoke("config_links", ""),
      "config_links",
    );
  }

  Future<Map<String, dynamic>> appConfig() async {
    return _decodeMapResponse(
      await _invoke("app_config", ""),
      "app_config",
      nullAsEmpty: true,
    );
  }

  Future<String> loadProperty(String propertyKey) {
    return _invoke("load_property", propertyKey);
  }

  Future<ComicsResponse> comics(String slug, SortBy sortBy, int page) async {
    final normalizedSlug = slug.trim();
    final cacheKey = "$normalizedSlug|${sortBy.value}|$page";
    final rsp = await _loadCachedString(
      cacheKey: cacheKey,
      ttl: _comicsCacheTtl,
      cache: _comicsCache,
      inflight: _comicsInflight,
      loader: () => _invoke("comics", {
        "categories_slug": normalizedSlug,
        "sort_by": sortBy.value,
        "page": page,
      }),
      allowStaleOnError: true,
      debugName: "comics",
    );
    return _decodeEntityResponse(rsp, "comics", ComicsResponse.fromJson);
  }

  Future<ComicsResponse> comicSearch(
    String searchQuery,
    SortBy sortBy,
    int page,
  ) async {
    final rsp = await _invoke("comic_search", {
      "search_query": searchQuery,
      "sort_by": sortBy.value,
      "page": page,
    });
    return _decodeEntityResponse(rsp, "comic_search", ComicsResponse.fromJson);
  }

  Future<ComicsResponse> pageViewLog(int page) async {
    final rsp = await _invoke("page_view_log", page);
    return _decodeEntityResponse(rsp, "page_view_log", ComicsResponse.fromJson);
  }

  Future<dynamic> deleteViewLogByComicId(int comicId) async {
    final rsp = await _invoke("delete_view_log_by_comic_id", comicId);
    return rsp;
  }

  Future<CategoriesResponse> categories() async {
    final rsp = await _loadCachedString(
      cacheKey: _defaultCategoriesCacheKey,
      ttl: _categoriesCacheTtl,
      cache: _categoriesCache,
      inflight: _categoriesInflight,
      loader: () => _invoke("categories", ""),
      allowStaleOnError: true,
      debugName: "categories",
    );
    return _decodeEntityResponse(
      rsp,
      "categories",
      CategoriesResponse.fromJson,
    );
  }

  Future saveImageFileToGallery(String path) {
    return _channel.invokeMethod("saveImageFileToGallery", path);
  }

  Future saveProperty(String key, String v) {
    return _invoke("save_property", {"k": key, "v": v});
  }

  Future<AlbumResponse> album(int id, {bool ignoreViewLog = false}) async {
    final cacheKey = "$id|$ignoreViewLog";
    final rsp = await _loadCachedString(
      cacheKey: cacheKey,
      ttl: _albumCacheTtl,
      cache: _albumCache,
      inflight: _albumInflight,
      loader: () =>
          _invoke("album", {"id": id, "ignore_view_log": ignoreViewLog}),
      allowStaleOnError: true,
      debugName: "album",
    );
    return _decodeEntityResponse(rsp, "album", AlbumResponse.fromJson);
  }

  Future<ChapterResponse> chapter(int id) async {
    return _decodeEntityResponse(
      await _invoke("chapter", id),
      "chapter",
      ChapterResponse.fromJson,
    );
  }

  Future<CommentPage> forum(String? mode, int? aid, int? uid, int page) async {
    return _decodeEntityResponse(
      await _invoke("forum", {
        "mode": mode,
        "aid": aid,
        "uid": uid,
        "page": page,
      }),
      "forum",
      CommentPage.fromJson,
    );
  }

  Future<Favorite> favorites(int folderId, int page, String o) async {
    return _decodeEntityResponse(
      await _invoke("favorites", {"folder_id": folderId, "page": page, "o": o}),
      "favorites",
      Favorite.fromJson,
    );
  }

  Future<Favorite> favorite() async {
    return _decodeEntityResponse(
      await _invoke("favorite", ""),
      "favorite",
      Favorite.fromJson,
    );
  }

  Future<ActionResponse> setFavorite(int aid) async {
    final rsp = await _invoke("set_favorite", aid);
    _evictAlbumCache(aid);
    return _decodeEntityResponse(rsp, "set_favorite", ActionResponse.fromJson);
  }

  Future createFavoriteFolder(String name) async {
    return _invoke("create_favorite_folder", name);
  }

  Future deleteFavoriteFolder(int folderId) async {
    return _invoke("delete_favorite_folder", folderId);
  }

  Future comicFavoriteFolderMove(int comicId, int folderId) async {
    return _invoke("comic_favorite_folder_move", [comicId, folderId]);
  }

  Future renameFavoriteFolder(int folderId, String name) async {
    return _invoke("rename_favorite_folder", ["$folderId", name]);
  }

  Future<GamePage> games(int page) async {
    return _decodeEntityResponse(
      await _invoke("games", page),
      "games",
      GamePage.fromJson,
    );
  }

  Future updateViewLog(int id, int lastViewChapterId, int lastViewPage) {
    return _invoke("update_view_log", {
      "id": id,
      "last_view_chapter_id": lastViewChapterId,
      "last_view_page": lastViewPage,
    });
  }

  Future<ViewLog?> findViewLog(int id) async {
    return _decodeNullableEntityResponse(
      await _invoke("find_view_log", id),
      "find_view_log",
      ViewLog.fromJson,
    );
  }

  Future cleanAllCache() async {
    final rsp = await _invoke("clean_all_cache", "params");
    _clearResponseCaches();
    return rsp;
  }

  Future<String> jm3x4Cover(int comicId) {
    return _loadCachedString(
      cacheKey: "3x4|$comicId",
      ttl: _coverCacheTtl,
      cache: _coverCache,
      inflight: _coverInflight,
      loader: () => _invoke("jm_3x4_cover", comicId),
      allowStaleOnError: true,
      debugName: "jm_3x4_cover",
    );
  }

  Future<String> jmSquareCover(int comicId) {
    return _loadCachedString(
      cacheKey: "square|$comicId",
      ttl: _coverCacheTtl,
      cache: _coverCache,
      inflight: _coverInflight,
      loader: () => _invoke("jm_square_cover", comicId),
      allowStaleOnError: true,
      debugName: "jm_square_cover",
    );
  }

  Future<String> jmPageImage(int id, String imageName) {
    return _invoke("jm_page_image", {"id": id, "image_name": imageName});
  }

  /// Batch page fetch adapter. Backend support is opt-in; failed/malformed
  /// batches transparently fall back to the existing single-page API.
  Future<List<JmPageImageBatchItem>> jmPageImageBatch(
    List<JmPageImageRequest> pages, {
    bool enabled = false,
  }) async {
    Future<List<JmPageImageBatchItem>> fallback() async => Future.wait(
      pages.map((p) async {
        try {
          return JmPageImageBatchItem(
            id: p.id,
            path: await jmPageImage(p.id, p.imageName),
          );
        } catch (e) {
          return JmPageImageBatchItem(
            id: p.id,
            error: JmPageImageBatchItem.safeErrorCode(e),
          );
        }
      }),
    );
    if (!enabled || pages.isEmpty) return fallback();
    try {
      final output = <JmPageImageBatchItem>[];
      for (var offset = 0; offset < pages.length; offset += 16) {
        final chunk = pages.sublist(
          offset,
          (offset + 16).clamp(0, pages.length),
        );
        final raw = await _invoke("jm_page_image_batch", {
          "pages": chunk.map((p) => p.toJson()).toList(),
        });
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded["version"] != 1 ||
            decoded["items"] is! List) {
          return fallback();
        }
        // Parse every element strictly.  Filtering non-map values would let a
        // malformed response appear valid when the remaining item count still
        // happened to match the request.
        final items = (decoded["items"] as List)
            .map(JmPageImageBatchItem.fromJson)
            .toList(growable: false);
        if (items.length != chunk.length ||
            !List.generate(
              items.length,
              (i) => items[i].id == chunk[i].id,
            ).every((v) => v)) {
          return fallback();
        }
        output.addAll(items);
      }
      return output;
    } catch (_) {
      return fallback();
    }
  }

  Future<String> jmPhotoImage(String imageName) {
    return _invoke("jm_photo_image", imageName);
  }

  Future<ImageSize> imageSize(String path) async {
    return _decodeEntityResponse(
      await _invoke("image_size", path),
      "image_size",
      ImageSize.fromJson,
    );
  }

  Future httpGet(String versionUrl) {
    return _invoke("http_get", versionUrl);
  }

  Future<String> loadApiHost() {
    return _invoke("load_api_host", "");
  }

  Future<List<String>> loadApiHostList() async {
    return _decodeStringListResponse(
      await _invoke("load_api_host_list", ""),
      "load_api_host_list",
      dedupe: true,
    );
  }

  Future<List<String>> refreshApiHostList() async {
    return _decodeStringListResponse(
      await _invoke("refresh_api_host_list", ""),
      "refresh_api_host_list",
      dedupe: true,
    );
  }

  Future<String> loadCdnHost() {
    return _invoke("load_cdn_host", "");
  }

  Future saveApiHost(String choose) {
    _clearResponseCaches();
    return _invoke("save_api_host", choose);
  }

  Future saveCdnHost(String choose) {
    _clearResponseCaches();
    return _invoke("save_cdn_host", choose);
  }

  Future<PreLoginResponse> preLogin() async {
    return _decodeEntityResponse(
      await _invoke("pre_login", ""),
      "pre_login",
      PreLoginResponse.fromJson,
    );
  }

  Future<SelfInfo> login(String username, String password) async {
    final rsp = await _invoke("login", {
      "username": username,
      "password": password,
    });
    _clearResponseCaches();
    return _decodeEntityResponse(rsp, "login", SelfInfo.fromJson);
  }

  Future logout() async {
    await _invoke("logout", {});
    _clearResponseCaches();
  }

  Future<CommentResponse> commentResponse(int aid, String comment) async {
    return _decodeEntityResponse(
      await _invoke("comment", {"aid": aid, "comment": comment}),
      "comment",
      CommentResponse.fromJson,
    );
  }

  Future<CommentResponse> comment(int aid, String comment) async {
    return _decodeEntityResponse(
      await _invoke("comment", {"aid": aid, "comment": comment}),
      "comment",
      CommentResponse.fromJson,
    );
  }

  Future<CommentResponse> childComment(
    int aid,
    String comment,
    int? commentId,
  ) async {
    return _decodeEntityResponse(
      await _invoke("child_comment", {
        "aid": aid,
        "comment": comment,
        "comment_id": commentId,
      }),
      "child_comment",
      CommentResponse.fromJson,
    );
  }

  Future<String> loadUsername() {
    return _invoke("load_username", "");
  }

  Future<String> loadLastLoginUsername() {
    return _invoke("loadLastLoginUsername", "");
  }

  Future<String> loadPassword() {
    return _invoke("load_password", "");
  }

  Future clearViewLog() {
    return _invoke("clear_view_log", "");
  }

  Future<List<SearchHistory>> lastSearchHistories(int count) async {
    if (count <= 0) {
      // 调用方用 0 表示不展示搜索历史；直接在 Dart 侧短路，避免一次无意义桥接调用。
      return const <SearchHistory>[];
    }
    // 后端当前最多返回 200 条；提前在前端裁剪可减少桥接 payload，保持行为兼容。
    final normalizedCount = count > _maxSearchHistoryCountHint
        ? _maxSearchHistoryCountHint
        : count;
    return _decodeEntityListResponse(
      await _invoke("last_search_histories", "$normalizedCount"),
      "last_search_histories",
      SearchHistory.fromJson,
    );
  }

  /// Download list
  Future<List<DownloadAlbum>> allDownloads() async {
    return _decodeEntityListResponse(
      await _invoke("all_downloads", ""),
      "all_downloads",
      DownloadAlbum.fromJson,
    );
  }

  Future<DownloadAlbum?> downloadAlbumById(int id) async {
    // 下载详情页轮询只需要摘要字段；后端单项接口复用 all_downloads 的 wire 形状。
    return _decodeNullableEntityResponse(
      await _invoke("download_album_by_id", "$id"),
      "download_album_by_id",
      DownloadAlbum.fromJson,
    );
  }

  /// Find download item
  Future<DownloadCreate?> downloadById(int id) async {
    return _decodeNullableEntityResponse(
      await _invoke("download_by_id", "$id"),
      "download_by_id",
      DownloadCreate.fromJson,
    );
  }

  /// Create download task
  Future<dynamic> createDownload(DownloadCreate create) async {
    return _invoke("create_download", create);
  }

  /// Download image list
  Future<List<DlImage>> dlImageByChapterId(int id, {int? albumId}) async {
    final params = albumId == null
        ? "$id"
        : {"chapter_id": id, "album_id": albumId};
    dynamic raw;
    try {
      raw = await _invoke("dl_image_by_chapter_id", params);
    } catch (e) {
      final retryable = albumId != null && _isLegacyArgumentContractError(e);
      if (!retryable) rethrow;
      raw = await _invoke("dl_image_by_chapter_id", "$id");
    }
    return _decodeEntityListResponse(
      raw,
      "dl_image_by_chapter_id",
      DlImage.fromJson,
    );
  }

  /// Optional, read-only local availability probe. Older backends may not
  /// implement it; callers must treat errors/unknown payloads as unavailable.
  Future<List<DlImage>> dlImageLocalAvailability(int id, {int? albumId}) async {
    try {
      final params = albumId == null
          ? "$id"
          : {"chapter_id": id, "album_id": albumId};
      dynamic raw;
      try {
        raw = await _invoke("dl_image_local_availability", params);
      } catch (e) {
        if (albumId == null || !_isLegacyArgumentContractError(e)) rethrow;
        raw = await _invoke("dl_image_local_availability", "$id");
      }
      return _decodeEntityListResponse(
        raw,
        "dl_image_local_availability",
        DlImage.fromJson,
      );
    } catch (_) {
      return const <DlImage>[];
    }
  }

  Future<dynamic> deleteDownload(int id) async {
    return _invoke("delete_download", id);
  }

  Future<dynamic> renewAllDownloads() async {
    return _invoke("renew_all_downloads", "");
  }

  /// Get Android refresh modes
  Future<List<String>> loadAndroidModes() async {
    try {
      final raw = await _channel.invokeMethod("androidGetModes");
      return _normalizePlatformStringList(raw, "androidGetModes");
    } on PlatformException catch (e, s) {
      // 刷新率模式只影响设置页展示；通道异常时降级为空列表，避免应用初始化被阻断。
      debugPrient(
        "androidGetModes fallback []: ${e.runtimeType}/${s.runtimeType}",
      );
      return const <String>[];
    }
  }

  /// Set Android refresh mode
  Future setAndroidMode(String androidDisplayMode) {
    final normalizedMode = androidDisplayMode.trim();
    return _channel.invokeMethod("androidSetMode", {"mode": normalizedMode});
  }

  /// Get Android SDK version
  Future<int> androidGetVersion() async {
    if (Platform.isAndroid) {
      return await _channel.invokeMethod("androidGetVersion", {});
    }
    return 0;
  }

  Future export_jm_jpegs(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jpegs", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_zip", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jpegs_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_jpegs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_jmi", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jmi_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_jmi_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_cbzs_zip_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_cbzs_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_pdf2(int id, String folder, bool deleteExported) {
    return _invoke("export_jm_pdf2", {
      "comic_id": [id],
      "dir": folder,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub(List<int> idList, String path, bool deleteExported) {
    return _invoke("export_jm_epub", {
      "comic_id": idList,
      "dir": path,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_epub_single(
    int id,
    String folder,
    String? rename,
    bool deleteExported,
  ) {
    return _invoke("export_jm_epub_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future import_jm_zip(String path) {
    debugPrient('[import] type=zip pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_zip", path);
  }

  Future import_jm_jmi(String path) {
    debugPrient('[import] type=jmi pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_jmi", path);
  }

  Future import_jm_dir(String path) {
    debugPrient('[import] type=dir pathProvided=${path.isNotEmpty}');
    return _invoke("import_jm_dir", path);
  }

  Future<IsPro> isPro() async {
    return _decodeEntityResponse(
      await _invoke("is_pro", ""),
      "is_pro",
      IsPro.fromJson,
    );
  }

  Future<ProInfoAll> proInfoAll() async {
    return _decodeEntityResponse(
      await _invoke("pro_info_all", ""),
      "pro_info_all",
      ProInfoAll.fromJson,
    );
  }

  Future reloadPro() {
    return _invoke("reload_pro", "");
  }

  Future inputCdKey(String cdKey) {
    return _invoke("input_cd_key", cdKey);
  }

  Future checkPat(String accessKey) {
    return _invoke("check_pat", accessKey);
  }

  Future bindPatAccount(String accessKey, String username) {
    return _invoke(
      "bind_pat",
      jsonEncode({"access_key": accessKey, "username": username}),
    );
  }

  Future reloadPatAccount() {
    return _invoke("reload_pat_account", "");
  }

  Future clearPat() {
    return _invoke("clear_pat", "");
  }

  Future<int> load_download_thread() async {
    final parsed = _parseBackendInt(
      await _invoke("load_download_thread", ""),
      "load_download_thread",
      fallback: _downloadThreadMin,
    );
    return _normalizeDownloadThreadCount(parsed, "load_download_thread");
  }

  Future set_download_thread(int count) {
    // 与后端线程约束保持一致，避免无效值反复跨桥接往返。
    final normalized = _normalizeDownloadThreadCount(
      count,
      "set_download_thread",
    );
    return _invoke("set_download_thread", "$normalized");
  }

  Future clearAllSearchLog() {
    return _invoke("clear_all_search_log", "");
  }

  Future clearASearchLog(String log) {
    return _invoke("clear_a_search_log", log);
  }

  Future setProxy(String url) {
    _clearResponseCaches();
    return _invoke("set_proxy", url);
  }

  Future<String> getProxy() {
    return _invoke("get_proxy", "");
  }

  Future webDavSync(dynamic params) {
    return _invoke("sync_webdav", params);
  }

  Future<String> iosGetDocumentDir() async {
    return await _channel.invokeMethod("iosGetDocumentDir");
  }

  Future<String> androidDefaultExportsDir() async {
    return await _channel.invokeMethod("androidDefaultExportsDir");
  }

  Future<String> getDownloadAndExportTo() async {
    return await _invoke("get_download_and_export_to", "");
  }

  Future<String> getHomeDir() async {
    return await _invoke("getHomeDir", "");
  }

  Future setDownloadAndExportTo(String path) async {
    return await _invoke("set_download_and_export_to", path);
  }

  Future<int> ping(String idx) async {
    debugPrient("PING API $idx");
    return _parseBackendInt(
      await _invoke("ping_server", idx),
      "ping_server",
      fallback: 0,
    );
  }

  Future<int> pingCdn(String idx) async {
    debugPrient("PING CDN $idx");
    return _parseBackendInt(
      await _invoke("ping_cdn", idx),
      "ping_cdn",
      fallback: 0,
    );
  }

  Future mkdirs(String path) {
    return _invoke("mkdirs", path);
  }

  Future androidMkdirs(String path) async {
    return await _channel.invokeMethod("androidMkdirs", path);
  }

  Future<String> picturesDir() async {
    return await _channel.invokeMethod("picturesDir");
  }

  Future<String> copyPictureToFolder(String folder, String path) async {
    return await _invoke("copyPictureToFolder", {
      "folder": folder,
      "path": path,
    });
  }

  Future<String> getProServerName() async {
    try {
      final name = await _invoke("get_pro_server_name", "");
      if (name == "HK" || name == "US") {
        return name;
      }
    } catch (e, s) {
      debugPrient(
        "get_pro_server_name fallback HK: ${e.runtimeType}/${s.runtimeType}",
      );
    }
    return "HK";
  }

  Future setProServerName(String serverName) async {
    try {
      return await _invoke("set_pro_server_name", serverName);
    } catch (e, s) {
      debugPrient(
        "set_pro_server_name ignored: ${e.runtimeType}/${s.runtimeType}",
      );
      return "";
    }
  }

  Future<bool> verifyAuthentication() async {
    return await _channel.invokeMethod("verifyAuthentication");
  }

  Future<String> daily(int uid) {
    return _invoke("daily", uid);
  }

  Future<WeekData> week(int page) async {
    return _decodeEntityResponse(
      await _invoke("week", {"page": page}),
      "week",
      WeekData.fromJson,
    );
  }

  Future<WeekFilterResponse> weekFilter(
    String categoryId,
    String typeId,
    int page,
  ) async {
    return _decodeEntityResponse(
      await _invoke("week_filter", {
        "category_id": categoryId,
        "type_id": typeId,
        "page": page,
      }),
      "week_filter",
      WeekFilterResponse.fromJson,
    );
  }
}

class _Response {
  final String errorMessage;
  final String responseData;

  const _Response({required this.errorMessage, required this.responseData});

  factory _Response.fromJson(dynamic json) {
    if (json is! Map) {
      throw FormatException(
        "Unexpected invoke response shape: ${json.runtimeType}",
      );
    }
    final errorMessage = json["error_message"];
    final responseData = json["response_data"];
    if (errorMessage is! String || responseData is! String) {
      throw const FormatException(
        "Unexpected invoke response payload: expect string fields",
      );
    }
    return _Response(errorMessage: errorMessage, responseData: responseData);
  }
}

class _CacheEntry<T> {
  final T value;
  final int createdAtMs;

  const _CacheEntry(this.value, this.createdAtMs);
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:jmcomic3/basic/log.dart';

import 'method_response_decoder.dart';
import 'entities.dart';

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

  static final Map<String, _CacheEntry<String>> _categoriesCache = {};
  static final Map<String, _CacheEntry<String>> _comicsCache = {};
  static final Map<String, _CacheEntry<String>> _albumCache = {};
  static final Map<String, _CacheEntry<String>> _coverCache = {};
  static final Map<String, Future<String>> _categoriesInflight = {};
  static final Map<String, Future<String>> _comicsInflight = {};
  static final Map<String, Future<String>> _albumInflight = {};
  static final Map<String, Future<String>> _coverInflight = {};

  void _clearResponseCaches() {
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

  Future<String> _loadCachedString({
    required String cacheKey,
    required Duration ttl,
    required Map<String, _CacheEntry<String>> cache,
    required Map<String, Future<String>> inflight,
    required Future<String> Function() loader,
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
    inflight[cacheKey] = future;
    try {
      final value = await future;
      cache[cacheKey] = _CacheEntry(value, nowMs);
      if (debugName != null) {
        debugPrient("[api-cache-store] method=$debugName key=$cacheKey");
      }
      return value;
    } finally {
      inflight.remove(cacheKey);
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
          }));
    }
    return resp;
  }

  Future<String> _invoke(String method, dynamic params) async {
    final shouldDebug = _downloadDebugMethods.contains(method);
    if (shouldDebug) {
      debugPrient("[download-api:req] method=$method params=${_brief(params)}");
    }
    final resp = await _invokeRaw(method, params);
    final response = _Response.fromJson(jsonDecode(resp));

    if (response.errorMessage.isNotEmpty) {
      if (shouldDebug) {
        debugPrient(
          "[download-api:err] method=$method error=${response.errorMessage}",
        );
      }
      if (_isLikelyProGateError(method, response.errorMessage)) {
        debugPrient(
          "backend-pro-gate method=$method params=$params error=${response.errorMessage}",
        );
      }
      throw StateError(response.errorMessage);
    }
    if (shouldDebug) {
      debugPrient(
        "[download-api:rsp] method=$method data=${_brief(response.responseData)}",
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

  Map<String, dynamic>? _decodeNullableMapResponse(String rsp, String method) {
    return decodeNullableMapResponse(rsp, method);
  }

  Map<String, dynamic> _decodeMapResponse(
    String rsp,
    String method, {
    bool nullAsEmpty = false,
  }) {
    return decodeMapResponse(rsp, method, nullAsEmpty: nullAsEmpty);
  }

  List<Map<String, dynamic>> _decodeMapListResponse(
    String rsp,
    String method, {
    bool immutableItems = true,
  }) {
    return decodeMapListResponse(
      rsp,
      method,
      immutableItems: immutableItems,
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
      debugName: "comics",
    );
    return ComicsResponse.fromJson(jsonDecode(rsp));
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
    return ComicsResponse.fromJson(jsonDecode(rsp));
  }

  Future<ComicsResponse> pageViewLog(int page) async {
    final rsp = await _invoke("page_view_log", page);
    return ComicsResponse.fromJson(jsonDecode(rsp));
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
      debugName: "categories",
    );
    return CategoriesResponse.fromJson(jsonDecode(rsp));
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
      loader: () => _invoke("album", {
        "id": id,
        "ignore_view_log": ignoreViewLog,
      }),
      debugName: "album",
    );
    return AlbumResponse.fromJson(jsonDecode(rsp));
  }

  Future<ChapterResponse> chapter(int id) async {
    return ChapterResponse.fromJson(jsonDecode(await _invoke("chapter", id)));
  }

  Future<CommentPage> forum(String? mode, int? aid, int? uid, int page) async {
    return CommentPage.fromJson(jsonDecode(await _invoke("forum", {
      "mode": mode,
      "aid": aid,
      "uid": uid,
      "page": page,
    })));
  }

  Future<Favorite> favorites(int folderId, int page, String o) async {
    return Favorite.fromJson(
      jsonDecode(await _invoke("favorites", {
        "folder_id": folderId,
        "page": page,
        "o": o,
      })),
    );
  }

  Future<Favorite> favorite() async {
    return Favorite.fromJson(
      jsonDecode(await _invoke("favorite", "")),
    );
  }

  Future<ActionResponse> setFavorite(int aid) async {
    final rsp = await _invoke("set_favorite", aid);
    _evictAlbumCache(aid);
    return ActionResponse.fromJson(jsonDecode(rsp));
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
    return GamePage.fromJson(
      jsonDecode(await _invoke("games", page)),
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
    final map = _decodeNullableMapResponse(
      await _invoke("find_view_log", id),
      "find_view_log",
    );
    if (map == null) {
      return null;
    }
    return ViewLog.fromJson(map);
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
      debugName: "jm_square_cover",
    );
  }

  Future<String> jmPageImage(int id, String imageName) {
    return _invoke("jm_page_image", {"id": id, "image_name": imageName});
  }

  Future<String> jmPhotoImage(String imageName) {
    return _invoke("jm_photo_image", imageName);
  }

  Future<ImageSize> imageSize(String path) async {
    return ImageSize.fromJson(jsonDecode(await _invoke("image_size", path)));
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
    return PreLoginResponse.fromJson(
      jsonDecode(await _invoke("pre_login", "")),
    );
  }

  Future<SelfInfo> login(String username, String password) async {
    final rsp = await _invoke("login", {
      "username": username,
      "password": password,
    });
    _clearResponseCaches();
    return SelfInfo.fromJson(jsonDecode(rsp));
  }

  Future logout() async {
    await _invoke("logout", {});
    _clearResponseCaches();
  }

  Future<CommentResponse> commentResponse(int aid, String comment) async {
    return CommentResponse.fromJson(jsonDecode(await _invoke("comment", {
      "aid": aid,
      "comment": comment,
    })));
  }

  Future<CommentResponse> comment(int aid, String comment) async {
    return CommentResponse.fromJson(jsonDecode(await _invoke("comment", {
      "aid": aid,
      "comment": comment,
    })));
  }

  Future<CommentResponse> childComment(
    int aid,
    String comment,
    int? commentId,
  ) async {
    return CommentResponse.fromJson(jsonDecode(await _invoke("child_comment", {
      "aid": aid,
      "comment": comment,
      "comment_id": commentId,
    })));
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
    final normalizedCount =
        count > _maxSearchHistoryCountHint ? _maxSearchHistoryCountHint : count;
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
    final map = _decodeNullableMapResponse(
      await _invoke("download_album_by_id", "$id"),
      "download_album_by_id",
    );
    if (map == null) {
      return null;
    }
    // 下载详情页轮询只需要摘要字段；后端单项接口复用 all_downloads 的 wire 形状。
    return DownloadAlbum.fromJson(map);
  }

  /// Find download item
  Future<DownloadCreate?> downloadById(int id) async {
    final map = _decodeNullableMapResponse(
      await _invoke("download_by_id", "$id"),
      "download_by_id",
    );
    if (map == null) {
      return null;
    }
    return DownloadCreate.fromJson(map);
  }

  /// Create download task
  Future<dynamic> createDownload(DownloadCreate create) async {
    return _invoke("create_download", create);
  }

  /// Download image list
  Future<List<DlImage>> dlImageByChapterId(int id) async {
    return _decodeEntityListResponse(
      await _invoke("dl_image_by_chapter_id", "$id"),
      "dl_image_by_chapter_id",
      DlImage.fromJson,
    );
  }

  Future<dynamic> deleteDownload(int id) async {
    return _invoke("delete_download", id);
  }

  Future<dynamic> renewAllDownloads() async {
    return _invoke("renew_all_downloads", "");
  }

  /// Get Android refresh modes
  Future<List<String>> loadAndroidModes() async {
    return List.of(await _channel.invokeMethod("androidGetModes"))
        .map((e) => "$e")
        .toList();
  }

  /// Set Android refresh mode
  Future setAndroidMode(String androidDisplayMode) {
    return _channel
        .invokeMethod("androidSetMode", {"mode": androidDisplayMode});
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
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_zip_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_jm_jpegs_zip_single(
      int id, String folder, String? rename, bool deleteExported) {
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
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_jmi_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future export_cbzs_zip_single(
      int id, String folder, String? rename, bool deleteExported) {
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
      int id, String folder, String? rename, bool deleteExported) {
    return _invoke("export_jm_epub_single", {
      "id": id,
      "folder": folder,
      "rename": rename,
      "delete_exported": deleteExported,
    });
  }

  Future import_jm_zip(String path) {
    debugPrient(path);
    return _invoke("import_jm_zip", path);
  }

  Future import_jm_jmi(String path) {
    debugPrient(path);
    return _invoke("import_jm_jmi", path);
  }

  Future import_jm_dir(String path) {
    debugPrient(path);
    return _invoke("import_jm_dir", path);
  }

  Future<IsPro> isPro() async {
    return IsPro.fromJson(jsonDecode(await _invoke("is_pro", "")));
  }

  Future<ProInfoAll> proInfoAll() async {
    return ProInfoAll.fromJson(jsonDecode(await _invoke("pro_info_all", "")));
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
        jsonEncode({
          "access_key": accessKey,
          "username": username,
        }));
  }

  Future reloadPatAccount() {
    return _invoke("reload_pat_account", "");
  }

  Future clearPat() {
    return _invoke("clear_pat", "");
  }

  Future<int> load_download_thread() async {
    return int.parse(await _invoke("load_download_thread", ""));
  }

  Future set_download_thread(int count) {
    return _invoke("set_download_thread", "${count}");
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
    return int.parse(await _invoke("ping_server", idx));
  }

  Future<int> pingCdn(String idx) async {
    debugPrient("PING CDN $idx");
    return int.parse(await _invoke("ping_cdn", idx));
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
    return await _invoke(
      "copyPictureToFolder",
      {
        "folder": folder,
        "path": path,
      },
    );
  }

  Future<String> getProServerName() async {
    try {
      final name = await _invoke("get_pro_server_name", "");
      if (name == "HK" || name == "US") {
        return name;
      }
    } catch (e, s) {
      debugPrient("get_pro_server_name fallback HK: $e\n$s");
    }
    return "HK";
  }

  Future setProServerName(String serverName) async {
    try {
      return await _invoke("set_pro_server_name", serverName);
    } catch (e, s) {
      debugPrient("set_pro_server_name ignored: $e\n$s");
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
    return WeekData.fromJson(jsonDecode(await _invoke("week", {
      "page": page,
    })));
  }

  Future<WeekFilterResponse> weekFilter(
      String categoryId, String typeId, int page) async {
    return WeekFilterResponse.fromJson(jsonDecode(await _invoke("week_filter", {
      "category_id": categoryId,
      "type_id": typeId,
      "page": page,
    })));
  }
}

class _Response {
  late String errorMessage;
  late String responseData;

  _Response.fromJson(Map json) {
    errorMessage = json["error_message"];
    responseData = json["response_data"];
  }
}

class _CacheEntry<T> {
  final T value;
  final int createdAtMs;

  const _CacheEntry(this.value, this.createdAtMs);
}

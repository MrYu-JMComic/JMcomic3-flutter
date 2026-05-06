import 'dart:convert';

class SortBy {
  final String _value;
  final String _name;

  const SortBy._(this._value, this._name);

  get value => _value;

  @override
  String toString() {
    return _name;
  }
}

const sortByDefault = SortBy._("", "default");
const sortByNew = SortBy._("mr", "newest");
const sortByLike = SortBy._("tf", "like");
const sortByView = SortBy._("mv", "views");
const sortByViewDay = SortBy._("mv_t", "daily");
const sortByViewWeek = SortBy._("mv_w", "weekly");
const sortByViewMonth = SortBy._("mv_m", "monthly");

const sorts = [
  sortByDefault,
  sortByNew,
  sortByLike,
  sortByView,
  sortByViewDay,
  sortByViewWeek,
  sortByViewMonth,
];

int _toInt(dynamic value, {int fallback = 0}) {
  if (value == null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

int? _toNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

/// Rust 桥接和导入文件可能传入 Map<dynamic, dynamic>、null 或异常标量。
/// 实体层统一收口，避免页面层在恢复下载任务时重复处理边界。
Map<String, dynamic> _toStringDynamicMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    value.forEach((key, mapValue) {
      if (key != null) {
        result["$key"] = mapValue;
      }
    });
    return result;
  }
  return <String, dynamic>{};
}

/// 旧下载导入数据可能缺失列表字段；缺失时按空列表处理。
Iterable<dynamic> _toIterable(dynamic value) {
  if (value is Iterable) {
    return value;
  }
  return const <dynamic>[];
}

/// 下载详情页和阅读器会多次按章节 ID 恢复进度；实体层建一次索引避免重复线性扫描。
/// 如果导入数据出现重复章节 ID，保留首个章节，和旧的顺序遍历查找语义一致。
Map<int, DownloadCreateChapter> _indexChaptersById(
  List<DownloadCreateChapter> chapters,
) {
  final result = <int, DownloadCreateChapter>{};
  for (final chapter in chapters) {
    result.putIfAbsent(chapter.id, () => chapter);
  }
  return Map.unmodifiable(result);
}

class Page<T> {
  late final List<T> list;
  late final int total;
}

class CountPage<T> {
  late final List<T> list;
  late final int total;
  late final int count;

  CountPage.fromJson(Map<String, dynamic> json) {
    total = json["total"];
    count = json["count"];
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json["total"] = total;
    json["count"] = count;
    return json;
  }

  CountPage() {
    total = 0;
    count = 0;
  }
}

class SearchPage {
  SearchPage({required this.searchQuery, required this.total});

  late final String searchQuery;
  late final int total;
  late final int? redirectAid;

  SearchPage.fromJson(Map<String, dynamic> json) {
    searchQuery = "${json['search_query'] ?? ''}";
    total = _toInt(json['total']);
    redirectAid = _toNullableInt(json['redirect_aid']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['search_query'] = searchQuery;
    _data['total'] = total;
    _data['redirect_aid'] = redirectAid;
    return _data;
  }
}

class ComicsResponse extends SearchPage {
  late final List<ComicSimple> content;

  ComicsResponse.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    content = List.from(json['content'] ?? [])
        .whereType<Map>()
        .map((e) => ComicSimple.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['content'] = content;
    return _data;
  }
}

class ComicSimple extends ComicBasic {
  ComicSimple({
    required int id,
    required String author,
    required String description,
    required String name,
    required String image,
    int? updateAt,
    int? addtime,
    required this.category,
    required this.categorySub,
  }) : super(
          id: id,
          author: author,
          description: description,
          name: name,
          image: image,
          updateAt: updateAt,
          addtime: addtime,
        );

  late final ComicSimpleCategory category;
  late final ComicSimpleCategory categorySub;

  ComicSimple.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    final categoryMap = json['category'];
    final categorySubMap = json['category_sub'];
    category = ComicSimpleCategory.fromJson(
      categoryMap is Map<String, dynamic>
          ? categoryMap
          : (categoryMap is Map ? Map<String, dynamic>.from(categoryMap) : {}),
    );
    categorySub = ComicSimpleCategory.fromJson(
      categorySubMap is Map<String, dynamic>
          ? categorySubMap
          : (categorySubMap is Map
              ? Map<String, dynamic>.from(categorySubMap)
              : {}),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['category'] = category.toJson();
    _data['category_sub'] = categorySub.toJson();
    return _data;
  }
}

class ComicSimpleCategory {
  ComicSimpleCategory({this.id, this.title});

  late final String? id;
  late final String? title;

  ComicSimpleCategory.fromJson(Map<String, dynamic> json) {
    final idValue = json['id'];
    final titleValue = json['title'];
    final normalizedId = idValue == null ? null : "$idValue".trim();
    final normalizedTitle = titleValue == null ? null : "$titleValue".trim();
    id = (normalizedId == null || normalizedId.isEmpty) ? null : normalizedId;
    title = (normalizedTitle == null || normalizedTitle.isEmpty)
        ? null
        : normalizedTitle;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['title'] = title;
    return _data;
  }
}

class CategoriesResponse {
  CategoriesResponse({required this.categories, required this.blocks});

  late final List<Categories> categories;
  late final List<Block> blocks;

  CategoriesResponse.fromJson(Map<String, dynamic> json) {
    categories = List.from(
      json['categories'],
    ).map((e) => Categories.fromJson(e)).toList();
    blocks = List.from(json['blocks']).map((e) => Block.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['categories'] = categories.map((e) => e.toJson()).toList();
    _data['blocks'] = blocks.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Categories {
  Categories({
    required this.id,
    required this.name,
    required this.slug,
    required this.totalAlbums,
    this.type,
  });

  late final int id;
  late final String name;
  late final String slug;
  late final int totalAlbums;
  late final String? type;

  Categories.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    slug = json['slug'];
    totalAlbums = json['total_albums'];
    type = null;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['slug'] = slug;
    _data['total_albums'] = totalAlbums;
    _data['type'] = type;
    return _data;
  }
}

class Block {
  Block({required this.title, required this.content});

  late final String title;
  late final List<String> content;

  Block.fromJson(Map<String, dynamic> json) {
    title = json['title'];
    content = List.castFrom<dynamic, String>(json['content']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['title'] = title;
    _data['content'] = content;
    return _data;
  }
}

class AlbumResponse {
  AlbumResponse({
    required this.id,
    required this.name,
    required this.author,
    required this.images,
    required this.description,
    required this.totalViews,
    required this.likes,
    required this.series,
    required this.seriesId,
    required this.commentTotal,
    required this.tags,
    required this.works,
    required this.relatedList,
    required this.liked,
    required this.isFavorite,
    this.updateAt,
    this.addtime,
  });

  late final int id;
  late final String name;
  late final List<String> author;
  late final List<String> images;
  late final String description;
  late final int totalViews;
  late final int likes;
  late final List<Series> series;
  late final int seriesId;
  late final int commentTotal;
  late final List<String> tags;
  late final List<String> works;
  late final List<ComicBasic> relatedList;
  late final bool liked;
  late bool isFavorite;
  late final int? updateAt;
  late final int? addtime;

  /// 在线阅读的“从头开始”入口按章节 sort 选择首章，但不能原地重排 series。
  /// 章节列表还会被页面直接用于按钮展示，原地排序会让 UI 顺序和后端返回顺序意外漂移。
  int get initialReadableChapterId => _firstSeriesBySort(series)?.id ?? id;

  AlbumResponse.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    name = json['name'];
    author = List.castFrom<dynamic, String>(json['author']);
    images = List.castFrom<dynamic, String>(json['images']);
    description = json['description'];
    totalViews = json['total_views'];
    likes = json['likes'];
    series = List.from(json['series']).map((e) => Series.fromJson(e)).toList();
    seriesId = json['series_id'];
    commentTotal = json['comment_total'];
    tags = List.castFrom<dynamic, String>(json['tags']);
    works = List.castFrom<dynamic, String>(json['works']);
    relatedList = List.from(
      json['related_list'],
    ).map((e) => ComicBasic.fromJson(e)).toList();
    liked = json['liked'];
    isFavorite = json['is_favorite'];
    updateAt = _parseNullableInt(json['update_at']);
    addtime = _parseNullableInt(json['addtime']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['images'] = images;
    _data['description'] = description;
    _data['total_views'] = totalViews;
    _data['likes'] = likes;
    _data['series'] = series.map((e) => e.toJson()).toList();
    _data['series_id'] = seriesId;
    _data['comment_total'] = commentTotal;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['related_list'] = relatedList.map((e) => e.toJson()).toList();
    _data['liked'] = liked;
    _data['is_favorite'] = isFavorite;
    _data['update_at'] = updateAt;
    _data['addtime'] = addtime;
    return _data;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class Series {
  Series({required this.id, required this.name, required this.sort});

  late final int id;
  late final String name;
  late final String sort;

  Series.fromJson(Map<String, dynamic> json) {
    id = _toInt(json['id']);
    name = "${json['name'] ?? ''}";
    sort = "${json['sort'] ?? ''}";
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['sort'] = sort;
    return _data;
  }
}

Series? _firstSeriesBySort(List<Series> series) {
  Series? result;
  var resultSort = 0x7fffffff;
  for (final item in series) {
    final sort = int.tryParse(item.sort.trim()) ?? 0x7fffffff;
    if (result == null || sort < resultSort) {
      result = item;
      resultSort = sort;
    }
  }
  return result;
}

class ComicBasic {
  ComicBasic({
    required this.id,
    required this.author,
    required this.description,
    required this.name,
    required this.image,
    this.updateAt,
    this.addtime,
  });

  late final int id;
  late final String author;
  late final String description;
  late final String name;
  late final String image;
  late final int? updateAt;
  late final int? addtime;

  ComicBasic.fromJson(Map<String, dynamic> json) {
    id = _toInt(json['id']);
    author = "${json['author'] ?? ''}";
    description = "${json['description'] ?? ''}";
    name = "${json['name'] ?? ''}";
    image = "${json['image'] ?? ''}";
    updateAt = _toNullableInt(json['update_at']);
    addtime = _toNullableInt(json['addtime']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['author'] = author;
    _data['description'] = description;
    _data['name'] = name;
    _data['image'] = image;
    _data['update_at'] = updateAt;
    _data['addtime'] = addtime;
    return _data;
  }
}

class ChapterResponse {
  ChapterResponse({
    required this.id,
    required this.series,
    required this.tags,
    required this.name,
    required this.images,
    required this.seriesId,
    required this.isFavorite,
    required this.liked,
  });

  late final int id;
  late final List<Series> series;
  late final String tags;
  late final String name;
  late final List<String> images;
  late final int seriesId;
  late final bool isFavorite;
  late final bool liked;

  ChapterResponse.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    series = List.from(json['series']).map((e) => Series.fromJson(e)).toList();
    tags = json['tags'];
    name = json['name'];
    images = List.castFrom<dynamic, String>(json['images']);
    seriesId = json['series_id'];
    isFavorite = json['is_favorite'];
    liked = json['liked'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['series'] = series.map((e) => e.toJson()).toList();
    _data['tags'] = tags;
    _data['name'] = name;
    _data['images'] = images;
    _data['series_id'] = seriesId;
    _data['is_favorite'] = isFavorite;
    _data['liked'] = liked;
    return _data;
  }
}

class ImageSize {
  ImageSize({required this.h, required this.w});

  late final int h;
  late final int w;

  ImageSize.fromJson(Map<String, dynamic> json) {
    h = json['h'];
    w = json['w'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['h'] = h;
    _data['w'] = w;
    return _data;
  }
}

class Comment {
  Comment({
    required this.AID,
    required this.CID,
    required this.UID,
    required this.username,
    required this.nickname,
    required this.likes,
    required this.gender,
    required this.updateAt,
    required this.addtime,
    required this.parentCID,
    required this.expinfo,
    required this.name,
    required this.content,
    required this.photo,
    required this.spoiler,
    required this.replys,
  });

  late final int? AID;
  late final int CID;
  late final int UID;
  late final String username;
  late final String nickname;
  late final int likes;
  late final String gender;
  late final String updateAt;
  late final String addtime;
  late final int parentCID;
  late final Expinfo expinfo;
  late final String name;
  late final String content;
  late final String photo;
  late final int spoiler;
  late final List<Comment> replys;

  Comment.fromJson(Map<String, dynamic> json) {
    AID = json['AID'];
    CID = json['CID'];
    UID = json['UID'];
    username = json['username'];
    nickname = json['nickname'];
    likes = json['likes'];
    gender = json['gender'];
    updateAt = json['update_at'];
    addtime = json['addtime'];
    parentCID = json['parent_CID'];
    expinfo = Expinfo.fromJson(json['expinfo']);
    name = json['name'];
    content = json['content'];
    photo = json['photo'];
    spoiler = json['spoiler'];
    replys = List.from(
      json['replys'],
    ).map((e) => Comment.fromJson(e)).cast<Comment>().toList();
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['AID'] = AID;
    _data['CID'] = CID;
    _data['UID'] = UID;
    _data['username'] = username;
    _data['nickname'] = nickname;
    _data['likes'] = likes;
    _data['gender'] = gender;
    _data['update_at'] = updateAt;
    _data['addtime'] = addtime;
    _data['parent_CID'] = parentCID;
    _data['expinfo'] = expinfo.toJson();
    _data['name'] = name;
    _data['content'] = content;
    _data['photo'] = photo;
    _data['spoiler'] = spoiler;
    _data['replys'] = replys.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Expinfo {
  Expinfo({
    required this.levelName,
    required this.level,
    required this.nextLevelExp,
    required this.exp,
    required this.expPercent,
    required this.uid,
    required this.badges,
  });

  late final String levelName;
  late final int level;
  late final int nextLevelExp;
  late final String exp;
  late final double expPercent;
  late final int uid;
  late final List<Badge> badges;

  Expinfo.fromJson(Map<String, dynamic> json) {
    levelName = json['level_name'];
    level = json['level'];
    nextLevelExp = json['nextLevelExp'];
    exp = json['exp'];
    expPercent = json['expPercent'];
    uid = json['uid'];
    badges = List.from(json['badges']).map((e) => Badge.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['level_name'] = levelName;
    _data['level'] = level;
    _data['nextLevelExp'] = nextLevelExp;
    _data['exp'] = exp;
    _data['expPercent'] = expPercent;
    _data['uid'] = uid;
    _data['badges'] = badges.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Badge {
  Badge({required this.content, required this.name, required this.id});

  late final String content;
  late final String name;
  late final String id;

  Badge.fromJson(Map<String, dynamic> json) {
    content = json['content'];
    name = json['name'];
    id = json['id'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['content'] = content;
    _data['name'] = name;
    _data['id'] = id;
    return _data;
  }
}

class CommentPage extends Page<Comment> {
  CommentPage.fromJson(Map<String, dynamic> json) {
    list = List.from(json['list']).map((e) => Comment.fromJson(e)).toList();
    total = json['total'];
  }
}

class PreLoginResponse {
  PreLoginResponse({
    required this.preSet,
    required this.preLogin,
    required this.selfInfo,
    required this.message,
  });

  late final bool preSet;
  late final bool preLogin;
  late final SelfInfo? selfInfo;
  late final String? message;

  PreLoginResponse.fromJson(Map<String, dynamic> json) {
    preSet = json['pre_set'];
    preLogin = json['pre_login'];
    if (json['self_info'] != null) {
      selfInfo = SelfInfo.fromJson(json['self_info']);
    } else {
      selfInfo = null;
    }
    message = json['message'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['pre_set'] = preSet;
    _data['pre_login'] = preLogin;
    _data['self_info'] = selfInfo?.toJson();
    _data['message'] = message;
    return _data;
  }
}

class SelfInfo {
  SelfInfo({
    required this.uid,
    required this.username,
    required this.email,
    required this.emailverified,
    required this.photo,
    required this.fname,
    required this.gender,
    required this.message,
    required this.coin,
    required this.albumFavorites,
    required this.s,
    required this.levelName,
    required this.level,
    required this.nextLevelExp,
    required this.exp,
    required this.expPercent,
    required this.badges,
    required this.albumFavoritesMax,
  });

  late final int uid;
  late final String username;
  late final String email;
  late final String emailverified;
  late final String photo;
  late final String fname;
  late final String gender;
  late final String message;
  late final int coin;
  late final int albumFavorites;
  late final String s;
  late final String levelName;
  late final int level;
  late final int nextLevelExp;
  late final String exp;
  late final double expPercent;
  late final List<dynamic> badges;
  late final int albumFavoritesMax;

  SelfInfo.fromJson(Map<String, dynamic> json) {
    uid = json['uid'];
    username = json['username'];
    email = json['email'];
    emailverified = json['emailverified'];
    photo = json['photo'];
    fname = json['fname'];
    gender = json['gender'];
    message = json['message'];
    coin = json['coin'];
    albumFavorites = json['album_favorites'];
    s = json['s'];
    levelName = json['level_name'];
    level = json['level'];
    nextLevelExp = json['nextLevelExp'];
    exp = json['exp'];
    expPercent = json['expPercent'];
    badges = List.castFrom<dynamic, dynamic>(json['badges']);
    albumFavoritesMax = json['album_favorites_max'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['uid'] = uid;
    _data['username'] = username;
    _data['email'] = email;
    _data['emailverified'] = emailverified;
    _data['photo'] = photo;
    _data['fname'] = fname;
    _data['gender'] = gender;
    _data['message'] = message;
    _data['coin'] = coin;
    _data['album_favorites'] = albumFavorites;
    _data['s'] = s;
    _data['level_name'] = levelName;
    _data['level'] = level;
    _data['nextLevelExp'] = nextLevelExp;
    _data['exp'] = exp;
    _data['expPercent'] = expPercent;
    _data['badges'] = badges;
    _data['album_favorites_max'] = albumFavoritesMax;
    return _data;
  }
}

class FavoriteFolder {
  FavoriteFolder({required this.fid, required this.uid, required this.name});

  late final String fid;
  late final String uid;
  late final String name;

  FavoriteFolder.fromJson(Map<String, dynamic> json) {
    fid = json['FID'];
    uid = json['UID'];
    name = json['name'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['FID'] = fid;
    _data['UID'] = uid;
    _data['name'] = name;
    return _data;
  }
}

class Favorite extends CountPage<ComicSimple> {
  late final List<FavoriteFolderItem> folderList;
  Favorite.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    list = List.from(json['list']).map((e) => ComicSimple.fromJson(e)).toList();
    folderList = List.from(
      json['folder_list'],
    ).map((e) => FavoriteFolderItem.fromJson(e)).toList();
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['list'] = list;
    _data['folder_list'] = folderList;
    return _data;
  }

  Favorite() : super() {
    list = [];
    folderList = [];
  }
}

class FavoriteFolderItem {
  FavoriteFolderItem({
    required this.fid,
    required this.uid,
    required this.name,
  });

  late final int fid;
  late final int uid;
  late final String name;

  FavoriteFolderItem.fromJson(Map<String, dynamic> json) {
    fid = json['FID'];
    uid = json['UID'];
    name = json['name'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['FID'] = fid;
    _data['UID'] = uid;
    _data['name'] = name;
    return _data;
  }
}

class FavoritesResponse extends CountPage<ComicSimple> {
  FavoritesResponse.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    list = List.from(json['list']).map((e) => ComicSimple.fromJson(e)).toList();
  }

  @override
  Map<String, dynamic> toJson() {
    final _data = super.toJson();
    _data['list'] = list;
    return _data;
  }
}

class WeekFilterResponse extends Page<ComicSimple> {
  WeekFilterResponse.fromJson(Map<String, dynamic> json) {
    list = List.from(json['list']).map((e) => ComicSimple.fromJson(e)).toList();
    total = json['total'];
  }
}

class ActionResponse {
  ActionResponse({required this.status, required this.msg, required this.type});

  late final String status;
  late final String msg;
  late final String type;

  ActionResponse.fromJson(Map<String, dynamic> json) {
    status = json['status'];
    msg = json['msg'];
    type = json['type'];
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['status'] = status;
    _data['msg'] = msg;
    _data['type'] = type;
    return _data;
  }
}

class InnerComicPage {
  final int total;
  final List<ComicSimple> list;
  final int? redirectAid;

  InnerComicPage({required this.total, required this.list, this.redirectAid});
}

class CommentResponse {
  CommentResponse({
    required this.msg,
    required this.status,
    required this.aid,
    required this.cid,
    required this.spoiler,
  });

  late final String msg;
  late final String status;
  late final int aid;
  late final int cid;
  late final String spoiler;

  bool get isSuccess {
    final normalized = status.trim().toLowerCase();
    return cid > 0 ||
        normalized == '1' ||
        normalized == 'true' ||
        normalized == 'success' ||
        normalized == 'ok';
  }

  CommentResponse.fromJson(Map<String, dynamic> json) {
    msg = '${json['msg'] ?? ''}';
    status = '${json['status'] ?? ''}';
    aid = int.tryParse('${json['aid'] ?? 0}') ?? 0;
    cid = int.tryParse('${json['cid'] ?? 0}') ?? 0;
    spoiler = '${json['spoiler'] ?? ''}';
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['msg'] = msg;
    _data['status'] = status;
    _data['aid'] = aid;
    _data['cid'] = cid;
    _data['spoiler'] = spoiler;
    return _data;
  }
}

class ViewLog {
  ViewLog({
    required this.id,
    required this.author,
    required this.description,
    required this.name,
    required this.lastViewTime,
    required this.lastViewChapterId,
    required this.lastViewPage,
  });

  late final int id;
  late final String author;
  late final String description;
  late final String name;
  late final int lastViewTime;
  late final int lastViewChapterId;
  late final int lastViewPage;

  ViewLog.fromJson(Map<String, dynamic> json) {
    // 阅读历史来自 Rust 本地存储和 WebDAV 合并结果，旧数据可能把数字写成字符串。
    id = _toInt(json['id']);
    author = "${json['author'] ?? ''}";
    description = "${json['description'] ?? ''}";
    name = "${json['name'] ?? ''}";
    lastViewTime = _toInt(json['last_view_time']);
    lastViewChapterId = _toInt(json['last_view_chapter_id']);
    lastViewPage = _toInt(json['last_view_page']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['author'] = author;
    _data['description'] = description;
    _data['name'] = name;
    _data['last_view_time'] = lastViewTime;
    _data['last_view_chapter_id'] = lastViewChapterId;
    _data['last_view_page'] = lastViewPage;
    return _data;
  }
}

class GamePage {
  GamePage({
    required this.games,
    required this.gamesTotal,
    required this.categories,
    required this.hotGames,
  });

  late final List<Game> games;
  late final String gamesTotal;
  late final List<GameCategory> categories;
  late final List<Game> hotGames;

  GamePage.fromJson(Map<String, dynamic> json) {
    games = List.from(json['games']).map((e) => Game.fromJson(e)).toList();
    gamesTotal = json['games_total'];
    categories = List.from(
      json['categories'],
    ).map((e) => GameCategory.fromJson(e)).toList();
    hotGames = List.from(
      json['hot_games'],
    ).map((e) => Game.fromJson(e)).toList();
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['games'] = games.map((e) => e.toJson()).toList();
    _data['games_total'] = gamesTotal;
    _data['categories'] = categories.map((e) => e.toJson()).toList();
    _data['hot_games'] = hotGames.map((e) => e.toJson()).toList();
    return _data;
  }
}

class Game {
  Game({
    required this.gid,
    required this.title,
    required this.description,
    required this.tags,
    required this.link,
    required this.linkTitle,
    required this.photo,
    required this.type,
    required this.categories,
    required this.updateAt,
    required this.totalClicks,
    required this.orderRank,
    required this.status,
    required this.showLang,
  });

  late final int gid;
  late final String title;
  late final String description;
  late final String tags;
  late final String link;
  late final String linkTitle;
  late final String photo;
  late final List<String> type;
  late final GameCategory categories;
  late final int updateAt;
  late final int totalClicks;
  late final int orderRank;
  late final int status;
  late final List<String> showLang;

  Game.fromJson(Map<String, dynamic> json) {
    gid = json['gid'];
    title = json['title'];
    description = json['description'];
    tags = json['tags'];
    link = json['link'];
    linkTitle = json['link_title'];
    photo = json['photo'];
    type = List.castFrom<dynamic, String>(json['type']);
    categories = GameCategory.fromJson(json['categories']);
    updateAt = json['update_at'];
    totalClicks = json['total_clicks'];
    orderRank = json['order_rank'];
    status = json['status'];
    showLang = List.castFrom<dynamic, String>(json['show_lang']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['gid'] = gid;
    _data['title'] = title;
    _data['description'] = description;
    _data['tags'] = tags;
    _data['link'] = link;
    _data['link_title'] = linkTitle;
    _data['photo'] = photo;
    _data['type'] = type;
    _data['categories'] = categories.toJson();
    _data['update_at'] = updateAt;
    _data['total_clicks'] = totalClicks;
    _data['order_rank'] = orderRank;
    _data['status'] = status;
    _data['show_lang'] = showLang;
    return _data;
  }
}

class GameCategory {
  GameCategory({this.name, this.slug});

  late final String? name;
  late final String? slug;

  GameCategory.fromJson(Map<String, dynamic> json) {
    name = null;
    slug = null;
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['name'] = name;
    _data['slug'] = slug;
    return _data;
  }
}

class SearchHistory {
  SearchHistory({required this.searchQuery, required this.lastSearchTime});

  late final String searchQuery;
  late final int lastSearchTime;

  SearchHistory.fromJson(Map<String, dynamic> json) {
    // 搜索历史会参与本地分片存储和旧备份导入，实体层兜底可避免历史页崩溃。
    searchQuery = "${json['search_query'] ?? ''}";
    lastSearchTime = _toInt(json['last_search_time']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['search_query'] = searchQuery;
    _data['last_search_time'] = lastSearchTime;
    return _data;
  }
}

class DownloadCreate {
  DownloadCreate({required this.album, required this.chapters});

  late final DownloadCreateAlbum album;
  late final List<DownloadCreateChapter> chapters;
  late final Map<int, DownloadCreateChapter> _chapterByIdMap =
      _indexChaptersById(chapters);
  late final List<Series> _readerSeries = List.unmodifiable(
    chapters.map((e) => Series(id: e.id, name: e.name, sort: e.sort)),
  );

  bool get hasChapters => chapters.isNotEmpty;

  /// 阅读器入口使用的首个章节 ID；兼容旧下载数据中章节列表为空的情况。
  int get initialChapterId => hasChapters ? chapters.first.id : album.id;

  /// 历史阅读记录恢复前需要确认章节仍属于当前下载任务。
  bool containsChapterId(int chapterId) =>
      _chapterByIdMap.containsKey(chapterId);

  /// 统一章节查找逻辑，避免详情页和阅读器加载时分别手写遍历并遗漏空列表边界。
  DownloadCreateChapter? chapterById(int chapterId) =>
      _chapterByIdMap[chapterId];

  /// 阅读器只需要轻量章节索引；缓存后可被详情页入口和章节加载回调重复复用。
  /// 返回不可变列表，防止页面层误改实体缓存后影响章节跳转和本地加载回调。
  /// 保持下载创建时的章节顺序，避免重复 ID 的兼容策略影响阅读器左右翻页顺序。
  List<Series> get readerSeries => _readerSeries;

  DownloadCreate.fromJson(Map<String, dynamic> json) {
    album = DownloadCreateAlbum.fromJson(_toStringDynamicMap(json['album']));
    chapters = _toIterable(json['chapters'])
        .whereType<Map>()
        .map((e) => DownloadCreateChapter.fromJson(_toStringDynamicMap(e)))
        .toList();
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['album'] = album.toJson();
    _data['chapters'] = chapters.map((e) => e.toJson()).toList();
    return _data;
  }
}

class DownloadCreateAlbum {
  DownloadCreateAlbum({
    required this.id,
    required this.name,
    required this.author,
    required this.tags,
    required this.works,
    required this.description,
  });

  late final int id;
  late final String name;
  late final List<String> author;
  late final List<String> tags;
  late final List<String> works;
  late final String description;

  DownloadCreateAlbum.fromJson(Map<String, dynamic> json) {
    id = _toInt(json['id']);
    name = "${json['name'] ?? ''}";
    author = _downloadMetadataList(json['author']);
    tags = _downloadMetadataList(json['tags']);
    works = _downloadMetadataList(json['works']);
    description = "${json['description'] ?? ''}";
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['description'] = description;
    return _data;
  }
}

class DownloadCreateChapter {
  DownloadCreateChapter({
    required this.id,
    required this.name,
    required this.sort,
  });

  late final int id;
  late final String name;
  late final String sort;

  DownloadCreateChapter.fromJson(Map<String, dynamic> json) {
    id = _toInt(json['id']);
    name = "${json['name'] ?? ''}";
    sort = "${json['sort'] ?? ''}";
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['sort'] = sort;
    return _data;
  }
}

class DownloadAlbum {
  DownloadAlbum({
    required this.id,
    required this.name,
    required this.author,
    required this.tags,
    required this.works,
    required this.description,
    required this.dlSquareCoverStatus,
    required this.dl_3x4CoverStatus,
    required this.dlStatus,
    required this.imageCount,
    required this.dledImageCount,
  });

  late final int id;
  late final String name;
  late final String author;
  late final String tags;
  late final String works;
  late final String description;
  late final int dlSquareCoverStatus;
  late final int dl_3x4CoverStatus;
  late final int dlStatus;
  late final int imageCount;
  late final int dledImageCount;
  late final List<String> _authorList =
      List.unmodifiable(_downloadMetadataList(author));
  late final List<String> _tagList =
      List.unmodifiable(_downloadMetadataList(tags));
  late final List<String> _workList =
      List.unmodifiable(_downloadMetadataList(works));
  late final String _authorLabel = _authorList.join(", ");

  /// 下载任务状态由后端持久化并驱动列表/详情页刷新策略，前端只做只读解释。
  bool get isQueuedOrDownloading => dlStatus == 0;
  bool get isDownloaded => dlStatus == 1;
  bool get isFailed => dlStatus == 2;
  bool get isDeleting => dlStatus == 3;
  bool get shouldAutoRefreshStatus => isQueuedOrDownloading || isDeleting;

  /// 作者/标签/作品在历史库中可能是纯文本，新后端则可能返回 JSON 字符串或数组。
  /// 列表页会频繁读取这些字段，实体内缓存一次并返回不可变视图，避免重复 JSON 解析和外部误改。
  List<String> get authorList => _authorList;
  List<String> get tagList => _tagList;
  List<String> get workList => _workList;
  String get authorLabel => _authorLabel;

  double? get downloadProgress {
    if (imageCount <= 0) {
      return null;
    }
    final value = dledImageCount / imageCount;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  DownloadAlbum.fromJson(Map<String, dynamic> json) {
    id = _toInt(json['id']);
    name = "${json['name'] ?? ''}";
    author = _downloadMetadataWireValue(json['author']);
    tags = _downloadMetadataWireValue(json['tags']);
    works = _downloadMetadataWireValue(json['works']);
    description = "${json['description'] ?? ''}";
    dlSquareCoverStatus = _toInt(json['dl_square_cover_status']);
    dl_3x4CoverStatus = _toInt(json['dl_3x4_cover_status']);
    dlStatus = _toInt(json['dl_status']);
    imageCount = _toInt(json['image_count']);
    dledImageCount = _toInt(json['dled_image_count']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['id'] = id;
    _data['name'] = name;
    _data['author'] = author;
    _data['tags'] = tags;
    _data['works'] = works;
    _data['description'] = description;
    _data['dl_square_cover_status'] = dlSquareCoverStatus;
    _data['dl_3x4_cover_status'] = dl_3x4CoverStatus;
    _data['dl_status'] = dlStatus;
    _data['image_count'] = imageCount;
    _data['dled_image_count'] = dledImageCount;
    return _data;
  }
}

String _downloadMetadataWireValue(dynamic value) {
  if (value == null) {
    return "";
  }
  if (value is String) {
    return value;
  }
  if (value is Iterable) {
    return jsonEncode(_downloadMetadataList(value));
  }
  return "$value";
}

/// 下载元数据跨过 Rust 桥接、旧 JSON 备份和前端导入流程，可能是数组、JSON 字符串或纯文本。
/// 这里统一过滤空项，保证卡片展示和导出逻辑拿到稳定的字符串列表。
List<String> _downloadMetadataList(dynamic value) {
  if (value == null) {
    return [];
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded == null) {
        return [];
      }
      if (decoded is Iterable) {
        return _downloadMetadataList(decoded);
      }
      if (decoded is String || decoded is num || decoded is bool) {
        return _downloadMetadataList(decoded);
      }
    } catch (_) {
      // 兼容旧下载库：历史版本可能直接存储纯文本作者/标签，而不是 JSON 数组。
    }
    return [trimmed];
  }
  if (value is Iterable) {
    return value
        .map((item) => "${item ?? ""}".trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
  final item = "$value".trim();
  return item.isEmpty ? [] : [item];
}

class DlImage {
  DlImage({
    required this.albumId,
    required this.chapterId,
    required this.imageIndex,
    required this.name,
    required this.key,
    required this.dlStatus,
    required this.width,
    required this.height,
  });

  late final int albumId;
  late final int chapterId;
  late final int imageIndex;
  late final String name;
  late final String key;
  late final int dlStatus;
  late final int width;
  late final int height;

  DlImage.fromJson(Map<String, dynamic> json) {
    // WebDAV/导入恢复可能把数字字段转成字符串；图片列表进入阅读器前先做宽松解析。
    albumId = _toInt(json['album_id']);
    chapterId = _toInt(json['chapter_id']);
    imageIndex = _toInt(json['image_index']);
    name = "${json['name'] ?? ''}";
    key = "${json['key'] ?? ''}";
    dlStatus = _toInt(json['dl_status']);
    width = _toInt(json['width']);
    height = _toInt(json['height']);
  }

  Map<String, dynamic> toJson() {
    final _data = <String, dynamic>{};
    _data['album_id'] = albumId;
    _data['chapter_id'] = chapterId;
    _data['image_index'] = imageIndex;
    _data['name'] = name;
    _data['key'] = key;
    _data['dl_status'] = dlStatus;
    _data['width'] = width;
    _data['height'] = height;
    return _data;
  }
}

ComicBasic albumToSimple(AlbumResponse album) {
  return ComicBasic(
    id: album.id,
    description: album.description,
    name: album.name,
    author: album.author.join(" / "),
    image: album.images.isEmpty ? '' : album.images[0],
    updateAt: album.updateAt,
    addtime: album.addtime,
  );
}

class IsPro {
  late bool isPro;
  late int expire;

  IsPro.fromJson(Map<String, dynamic> json) {
    isPro = json["is_pro"];
    this.expire = json["expire"];
  }
}

class ProInfoAll {
  late ProInfoAf proInfoAf;
  late ProInfoPat proInfoPat;

  ProInfoAll.fromJson(Map<String, dynamic> json) {
    proInfoAf = ProInfoAf.fromJson(json["pro_info_af"]);
    proInfoPat = ProInfoPat.fromJson(json["pro_info_pat"]);
  }
}

class ProInfoAf {
  late bool isPro;
  late int expire;

  ProInfoAf.fromJson(Map<String, dynamic> json) {
    isPro = json["is_pro"];
    expire = json["expire"];
  }
}

class ProInfoPat {
  late bool isPro;
  late String patId;
  late String bindUid;
  late int requestDelete;
  late int reBind;
  late int errorType;
  late String errorMsg;
  late String accessKey;

  ProInfoPat.fromJson(Map<String, dynamic> json) {
    isPro = json["is_pro"];
    patId = json["pat_id"] ?? "";
    bindUid = json["bind_uid"] ?? "";
    requestDelete = json["request_delete"] ?? 0;
    reBind = json["re_bind"] ?? 0;
    errorType = json["error_type"] ?? 0;
    errorMsg = json["error_msg"] ?? "";
    accessKey = json["access_key"] ?? "";
  }
}

class WeekData {
  late List<WeekCategory> categories;
  late List<WeekType> types;

  WeekData.fromJson(Map<String, dynamic> json) {
    categories = List.from(
      json['categories'],
    ).map((e) => WeekCategory.fromJson(e)).toList();
    types = List.from(json['type']).map((e) => WeekType.fromJson(e)).toList();
  }
}

class WeekCategory {
  late String id;
  late String time;
  late String title;

  WeekCategory.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    time = json['time'];
    title = json['title'];
  }
}

class WeekType {
  late String id;
  late String title;

  WeekType.fromJson(Map<String, dynamic> json) {
    id = json['id'];
    title = json['title'];
  }
}

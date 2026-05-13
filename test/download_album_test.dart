import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/method_response_decoder.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/android_display_mode.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/app_locale.dart';
import 'package:jmcomic3/configs/app_orientation.dart';
import 'package:jmcomic3/configs/auto_clean.dart';
import 'package:jmcomic3/configs/bool_property.dart';
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/configs/display_jmcode.dart';
import 'package:jmcomic3/configs/enum_property.dart';
import 'package:jmcomic3/configs/int_property.dart';
import 'package:jmcomic3/configs/network_api_host.dart';
import 'package:jmcomic3/configs/network_cdn_host.dart';
import 'package:jmcomic3/configs/network_host.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/configs/proxy.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/recommend_links.dart';
import 'package:jmcomic3/configs/search_title_words.dart';
import 'package:jmcomic3/configs/string_property.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/web_dav_password.dart';
import 'package:jmcomic3/configs/web_dav_url.dart';
import 'package:jmcomic3/configs/web_dav_username.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';
import 'package:jmcomic3/screens/comic_download_shared.dart';
import 'package:jmcomic3/screens/download_import_shared.dart';
import 'package:jmcomic3/screens/downloads_export_shared.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/components/search_history_shared.dart';

DownloadAlbum _downloadAlbumForTest(int id, {int status = 1}) {
  return DownloadAlbum.fromJson({
    'id': id,
    'name': 'download $id',
    'author': <String>[],
    'tags': <String>[],
    'works': <String>[],
    'description': '',
    'dl_square_cover_status': 0,
    'dl_3x4_cover_status': 0,
    'dl_status': status,
    'image_count': 0,
    'dled_image_count': 0,
  });
}

AlbumResponse _albumResponseForTest(List<Map<String, dynamic>> series) {
  return AlbumResponse.fromJson({
    'id': 20,
    'name': 'album',
    'author': <String>['alice'],
    'images': <String>[],
    'description': '',
    'total_views': 0,
    'likes': 0,
    'series': series,
    'series_id': 20,
    'comment_total': 0,
    'tags': <String>[],
    'works': <String>[],
    'related_list': <Map<String, dynamic>>[],
    'liked': false,
    'is_favorite': false,
  });
}

Categories _categoryForTest(int id) {
  return Categories(
    id: id,
    name: 'category $id',
    slug: 'category-$id',
    totalAlbums: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DownloadAlbum normalizes JSON and legacy metadata fields', () {
    final album = DownloadAlbum.fromJson({
      'id': 1,
      'name': 'download',
      'author': '["alice","bob"]',
      'tags': 'legacy tag',
      'works': ['series', 2, null],
      'description': '',
      'dl_square_cover_status': 0,
      'dl_3x4_cover_status': 0,
      'dl_status': 0,
      'image_count': 10,
      'dled_image_count': 3,
    });

    expect(album.authorList, ['alice', 'bob']);
    expect(album.authorLabel, 'alice, bob');
    expect(album.tagList, ['legacy tag']);
    expect(album.workList, ['series', '2']);
    expect(album.downloadProgress, .3);
  });

  test('DownloadAlbum caches metadata lists as immutable values', () {
    final album = DownloadAlbum.fromJson({
      'id': 12,
      'name': 'download',
      'author': '["alice","bob"]',
      'tags': '["tag"]',
      'works': '["series"]',
      'description': '',
      'dl_square_cover_status': 0,
      'dl_3x4_cover_status': 0,
      'dl_status': 0,
      'image_count': 0,
      'dled_image_count': 0,
    });

    // 下载列表卡片会重复读取元数据；缓存列表既减少解析，也避免调用方误改实体状态。
    expect(identical(album.authorList, album.authorList), isTrue);
    expect(() => album.authorList.add('charlie'), throwsUnsupportedError);
  });

  test('DownloadAlbum tolerates string numbers and scalar JSON metadata', () {
    final album = DownloadAlbum.fromJson({
      'id': '2',
      'name': null,
      'author': '"solo"',
      'tags': '["tag", "", null]',
      'works': 'null',
      'description': null,
      'dl_square_cover_status': '1',
      'dl_3x4_cover_status': '2',
      'dl_status': '1',
      'image_count': '4',
      'dled_image_count': '9',
    });

    expect(album.id, 2);
    expect(album.name, '');
    expect(album.authorList, ['solo']);
    expect(album.tagList, ['tag']);
    expect(album.workList, isEmpty);
    expect(album.description, '');
    expect(album.dlSquareCoverStatus, 1);
    expect(album.dl_3x4CoverStatus, 2);
    expect(album.isDownloaded, isTrue);
    expect(album.downloadProgress, 1);
  });

  test('DownloadAlbum decodes nested JSON metadata lists', () {
    final album = DownloadAlbum.fromJson({
      'id': 3,
      'name': 'nested metadata',
      'author': jsonEncode(jsonEncode(['alice', 'bob'])),
      'tags': jsonEncode([' tag ', '', null, 7]),
      'works': 'plain work',
      'description': '',
      'dl_square_cover_status': 0,
      'dl_3x4_cover_status': 0,
      'dl_status': 0,
      'image_count': 0,
      'dled_image_count': 0,
    });

    // 旧 WebDAV/导入链路可能把列表字段多包一层 JSON 字符串；普通文本仍保持单项。
    expect(album.authorList, ['alice', 'bob']);
    expect(album.tagList, ['tag', '7']);
    expect(album.workList, ['plain work']);
  });

  test('DownloadCreate reader helpers tolerate empty chapter list', () {
    final create = DownloadCreate.fromJson({
      'album': {
        'id': 7,
        'name': 'empty',
        'author': <String>[],
        'tags': <String>[],
        'works': <String>[],
        'description': '',
      },
      'chapters': <Map<String, dynamic>>[],
    });

    expect(create.hasChapters, isFalse);
    expect(create.initialChapterId, 7);
    expect(create.containsChapterId(7), isFalse);
    expect(create.chapterById(7), isNull);
    expect(create.readerSeries, isEmpty);
  });

  test('DownloadCreate reader helpers reuse chapter lookup semantics', () {
    final create = DownloadCreate.fromJson({
      'album': {
        'id': 9,
        'name': 'download',
        'author': <String>[],
        'tags': <String>[],
        'works': <String>[],
        'description': '',
      },
      'chapters': [
        {'id': 91, 'name': 'first', 'sort': '1'},
        {'id': 92, 'name': 'second', 'sort': '2'},
      ],
    });

    expect(create.hasChapters, isTrue);
    expect(create.initialChapterId, 91);
    expect(create.containsChapterId(92), isTrue);
    expect(create.chapterById(92)?.name, 'second');
    expect(create.readerSeries.map((e) => e.id), [91, 92]);
    expect(identical(create.readerSeries, create.readerSeries), isTrue);
    expect(
      () => create.readerSeries[0] = Series(id: 93, name: 'mutated', sort: '3'),
      throwsUnsupportedError,
    );
  });

  test('DownloadCreate chapter lookup keeps first duplicate chapter', () {
    final create = DownloadCreate.fromJson({
      'album': {
        'id': 10,
        'name': 'download',
        'author': <String>[],
        'tags': <String>[],
        'works': <String>[],
        'description': '',
      },
      'chapters': [
        {'id': 101, 'name': 'first copy', 'sort': '1'},
        {'id': 101, 'name': 'second copy', 'sort': '2'},
      ],
    });

    expect(create.containsChapterId(101), isTrue);
    expect(create.chapterById(101)?.name, 'first copy');
    expect(
        create.readerSeries.map((e) => e.name), ['first copy', 'second copy']);
  });

  test('DownloadCreate normalizes imported loose album and chapter fields', () {
    final create = DownloadCreate.fromJson({
      'album': {
        'id': '11',
        'name': null,
        'author': '["alice", "", null]',
        'tags': ['tag', 3, null],
        'works': 'legacy work',
        'description': null,
      },
      'chapters': [
        {'id': '111', 'name': null, 'sort': 1},
        'invalid chapter',
      ],
    });

    expect(create.album.id, 11);
    expect(create.album.name, '');
    expect(create.album.author, ['alice']);
    expect(create.album.tags, ['tag', '3']);
    expect(create.album.works, ['legacy work']);
    expect(create.album.description, '');
    expect(create.chapters.length, 1);
    expect(create.chapters.single.id, 111);
    expect(create.chapters.single.name, '');
    expect(create.chapters.single.sort, '1');
  });

  test('DownloadCreate treats missing album and chapters as empty values', () {
    final create = DownloadCreate.fromJson({});

    expect(create.album.id, 0);
    expect(create.album.name, '');
    expect(create.album.author, isEmpty);
    expect(create.chapters, isEmpty);
    expect(create.initialChapterId, 0);
  });

  test('AlbumResponse chooses initial readable chapter without reordering', () {
    final album = _albumResponseForTest([
      {'id': '202', 'name': null, 'sort': '2'},
      {'id': 201, 'name': 'first', 'sort': 1},
      {'id': 203, 'name': 'legacy', 'sort': 'legacy'},
    ]);

    // 在线详情页从头阅读时按 sort 选择首章，但不能改变章节按钮的后端原始顺序。
    expect(album.initialReadableChapterId, 201);
    expect(album.series.map((e) => e.id), [202, 201, 203]);
    expect(album.series.first.name, '');
  });

  test('DlImage tolerates string numbers and empty text fields', () {
    final image = DlImage.fromJson({
      'album_id': '20',
      'chapter_id': 201,
      'image_index': '3',
      'name': null,
      'key': 404,
      'dl_status': '1',
      'width': '800',
      'height': null,
    });

    expect(image.albumId, 20);
    expect(image.chapterId, 201);
    expect(image.imageIndex, 3);
    expect(image.name, '');
    expect(image.key, '404');
    expect(image.dlStatus, 1);
    expect(image.width, 800);
    expect(image.height, 0);
  });

  test('ImageSize tolerates string numbers from bridge responses', () {
    final size = ImageSize.fromJson({'w': '800', 'h': '1200'});

    expect(size.w, 800);
    expect(size.h, 1200);
  });

  test('page image true size cache shares in-flight bridge request', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var imageSizeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'image_size') {
        imageSizeCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode({'w': 800, 'h': 1200}),
        });
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() {
      clearAllImageMemoryCaches();
      messenger.setMockMethodCallHandler(channel, null);
    });
    clearAllImageMemoryCaches();

    final sizes = await Future.wait([
      cachedPageImageTrueSizeForTest(20, '001.jpg', r'D:\cache\001.jpg'),
      cachedPageImageTrueSizeForTest(20, '001.jpg', r'D:\cache\001.jpg'),
    ]);

    // 双页/预加载可能并发询问同一图片尺寸；缓存 Future 后只需一次跨端调用。
    expect(sizes.map((size) => [size.width, size.height]), [
      [800.0, 1200.0],
      [800.0, 1200.0],
    ]);
    expect(imageSizeCalls, 1);

    final cached = await cachedPageImageTrueSizeForTest(
        20, '001.jpg', r'D:\cache\001.jpg');
    expect(cached.width, 800);
    expect(imageSizeCalls, 1);

    await cachedPageImageTrueSizeForTest(
      20,
      '001.jpg',
      r'D:\cache\001.jpg',
      forceRefresh: true,
    );
    expect(imageSizeCalls, 2);
  });

  test('ViewLog and SearchHistory tolerate legacy loose JSON fields', () {
    final viewLog = ViewLog.fromJson({
      'id': '30',
      'author': null,
      'description': null,
      'name': 123,
      'last_view_time': '456',
      'last_view_chapter_id': '301',
      'last_view_page': null,
    });
    final searchHistory = SearchHistory.fromJson({
      'search_query': null,
      'last_search_time': '789',
    });

    expect(viewLog.id, 30);
    expect(viewLog.author, '');
    expect(viewLog.name, '123');
    expect(viewLog.lastViewTime, 456);
    expect(viewLog.lastViewChapterId, 301);
    expect(viewLog.lastViewPage, 0);
    expect(searchHistory.searchQuery, '');
    expect(searchHistory.lastSearchTime, 789);
  });

  test('search history panel normalizes blank and duplicate queries', () {
    final histories = normalizeSearchHistoriesForPanel(
      [
        SearchHistory(searchQuery: ' alpha ', lastSearchTime: 10),
        SearchHistory(searchQuery: '', lastSearchTime: 99),
        SearchHistory(searchQuery: 'beta', lastSearchTime: 20),
        SearchHistory(searchQuery: 'alpha', lastSearchTime: 30),
      ],
      limit: 2,
    );

    // 搜索面板只展示可点击查询词；重复词保留最新时间，并按后端列表顺序规则排序。
    expect(histories.map((e) => e.searchQuery), ['alpha', 'beta']);
    expect(histories.map((e) => e.lastSearchTime), [30, 20]);
    expect(
        () => histories.add(SearchHistory(searchQuery: 'x', lastSearchTime: 1)),
        throwsUnsupportedError);
  });

  test('search panel query normalization rejects blank submissions', () {
    expect(normalizeSearchPanelQuery('  alpha  '), 'alpha');
    expect(normalizeSearchPanelQuery(''), isNull);
    expect(normalizeSearchPanelQuery('   '), isNull);
  });

  test('method response decoder normalizes map list payloads', () {
    final list = decodeMapListResponse(
      '[{"id":"1","name":"a"},{"id":2}]',
      'all_downloads',
    );
    expect(list.length, 2);
    expect(list[0]['id'], '1');
    expect(list[1]['id'], 2);
    expect(() => list.add({'id': 3}), throwsUnsupportedError);
    expect(() => list[0]['id'] = 9, throwsUnsupportedError);
  });

  test('method response decoder can skip item immutability for hot paths', () {
    final list = decodeMapListResponse(
      '[{"id":"1","name":"a"}]',
      'all_downloads',
      immutableItems: false,
    );

    // 下载列表/图片列表会立即转实体；这条路径允许跳过每项只读包装以减少解码分配。
    list[0]['id'] = 2;
    expect(list[0]['id'], 2);
    expect(() => list.add({'id': 3}), throwsUnsupportedError);
  });

  test('method response decoder maps entities in one pass', () {
    final histories = decodeEntityListResponse(
      '[{"search_query":"alpha","last_search_time":"1"},{"search_query":"beta","last_search_time":2}]',
      'last_search_histories',
      SearchHistory.fromJson,
    );

    expect(histories.map((e) => e.searchQuery), ['alpha', 'beta']);
    expect(histories.map((e) => e.lastSearchTime), [1, 2]);
    expect(
      () => histories.add(SearchHistory(searchQuery: 'x', lastSearchTime: 3)),
      throwsUnsupportedError,
    );
    expect(
      () => decodeEntityListResponse(
        '[{"search_query":"ok","last_search_time":1}, 2]',
        'last_search_histories',
        SearchHistory.fromJson,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('method response decoder treats null list as empty', () {
    final list = decodeMapListResponse('null', 'last_search_histories');
    expect(list, isEmpty);
  });

  test('method response decoder unwraps nested JSON list payloads', () {
    final list = decodeMapListResponse(
      jsonEncode('[{"id":"8","name":"nested"}]'),
      'all_downloads',
    );

    // 部分旧桥接会把 response_data 再编码成 JSON 字符串；结构合法时应恢复为列表。
    expect(list.single['id'], '8');
    expect(list.single['name'], 'nested');
  });

  test('method response decoder unwraps double encoded JSON list payloads', () {
    final list = decodeMapListResponse(
      jsonEncode(jsonEncode('[{"id":"9","name":"double"}]')),
      'all_downloads',
    );

    // 手工脚本或旧桥接可能重复编码响应；限制拆包深度可兼容脏数据且避免无限递归。
    expect(list.single['id'], '9');
    expect(list.single['name'], 'double');
  });

  test('method response decoder rejects invalid map list entries', () {
    expect(
      () => decodeMapListResponse('[{"id":1}, 2]', 'all_downloads'),
      throwsA(isA<FormatException>()),
    );
  });

  test('method response decoder handles nullable map payloads', () {
    expect(decodeNullableMapResponse('null', 'download_by_id'), isNull);
    expect(
      decodeNullableMapResponse('{"id":"7"}', 'download_by_id')?['id'],
      '7',
    );
    expect(
      () => decodeNullableMapResponse('[]', 'download_by_id'),
      throwsA(isA<FormatException>()),
    );
  });

  test('method response decoder maps nullable entity payloads', () {
    expect(
      decodeNullableEntityResponse(
        'null',
        'find_view_log',
        ViewLog.fromJson,
      ),
      isNull,
    );
    final entity = decodeNullableEntityResponse(
      '{"id":"7","author":"","description":"","name":"book","last_view_time":"1","last_view_chapter_id":"2","last_view_page":"3"}',
      'find_view_log',
      ViewLog.fromJson,
    );
    expect(entity?.id, 7);
    expect(entity?.lastViewPage, 3);
    expect(
      () => decodeNullableEntityResponse(
        '[]',
        'find_view_log',
        ViewLog.fromJson,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('method response decoder maps required entity payloads', () {
    final data = decodeEntityResponse(
      '{"id":"7","author":"","description":"","name":"book","last_view_time":"1","last_view_chapter_id":"2","last_view_page":"3"}',
      'find_view_log',
      ViewLog.fromJson,
    );

    expect(data.id, 7);
    expect(data.lastViewChapterId, 2);
    expect(
      () => decodeEntityResponse(
        'null',
        'find_view_log',
        ViewLog.fromJson,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeEntityResponse(
        '[]',
        'find_view_log',
        ViewLog.fromJson,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('method response decoder normalizes map payload with dynamic keys', () {
    final map = decodeMapResponse(
      '{"1":"one","name":"alpha","nullable":null}',
      'app_config',
    );

    expect(map['1'], 'one');
    expect(map['name'], 'alpha');
    expect(map['nullable'], isNull);
    expect(
      () => decodeMapResponse('[]', 'app_config'),
      throwsA(isA<FormatException>()),
    );
    expect(
      decodeMapResponse('null', 'app_config', nullAsEmpty: true),
      isEmpty,
    );
  });

  test('method response decoder unwraps nested JSON map payloads', () {
    final map = decodeMapResponse(
      jsonEncode('{"1":"one","host":"cdn"}'),
      'app_config',
    );

    expect(map, {'1': 'one', 'host': 'cdn'});
  });

  test('method response decoder unwraps double encoded JSON map payloads', () {
    final map = decodeMapResponse(
      jsonEncode(jsonEncode('{"1":"one","host":"cdn2"}')),
      'app_config',
    );

    expect(map, {'1': 'one', 'host': 'cdn2'});
  });

  test('method response decoder converts map response to string map', () {
    final map = decodeStringMapResponse(
      '{"1":"one","host":2,"empty":null}',
      'config_links',
    );

    expect(map, {'1': 'one', 'host': '2', 'empty': ''});
    expect(() => map['next'] = 'x', throwsUnsupportedError);
  });

  test('recommend links normalize labels and protect global state', () {
    final links = normalizeRecommendLinksForDisplay({
      ' 频道 ': ' https://old.example/channel ',
      ' 关注频道入口 ': 'https://old.example/follow',
      '官网 ': ' https://example.com ',
      '空链接': '   ',
      '   ': 'https://blank-label.example',
    });

    expect(links['频道'], 'https://qm.qq.com/q/h3p372R200');
    expect(links['关注频道入口'], 'https://qm.qq.com/q/h3p372R200');
    expect(links['官网'], 'https://example.com');
    expect(links.containsKey('空链接'), isFalse);
    expect(
        () => links['新链接'] = 'https://example.com/new', throwsUnsupportedError);
  });

  test('comic info ignores JM id placeholder from local view history', () {
    final placeholder = ComicBasic(
      id: 123,
      author: '',
      description: '',
      name: 'JM123',
      image: '',
    );
    final spacedPlaceholder = ComicBasic(
      id: 123,
      author: '',
      description: '',
      name: 'JM # 123',
      image: '',
    );
    final real = ComicBasic(
      id: 123,
      author: 'author',
      description: '',
      name: '真实标题',
      image: '',
    );

    // 本地浏览记录兜底名不能锁住详情页标题；有真实标题的列表入口仍直接复用 simple。
    expect(effectiveComicInfoSimple(placeholder, 123), isNull);
    expect(effectiveComicInfoSimple(spacedPlaceholder, 123), isNull);
    expect(identical(effectiveComicInfoSimple(real, 123), real), isTrue);
  });

  test('settings parsers tolerate corrupt persisted values', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final properties = <String, String>{
      'FontSizeAdjustType.fontSizeAdjustCommentContent': '99',
      'pager_column_number': '-3',
      'categoriesSort': '[3," 2 ",2,0,"bad",1.0]',
      'auto_clean': jsonEncode('0.0'),
      'displayJmcode': ' "FALSE" ',
      'searchTitleWords': '1.0',
      'WebDavUrl': jsonEncode(' https://webdav.example/.jmtt2mic.history '),
      'WebDavUserName': jsonEncode(jsonEncode(' alice ')),
      'WebDavPassword': jsonEncode('  secret  '),
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property') {
        final key = payload['params']?.toString() ?? '';
        return jsonEncode(
            {'error_message': '', 'response_data': properties[key] ?? ''});
      }
      if (payload['method'] == 'get_proxy') {
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode(' socks5://127.0.0.1:1080/ '),
        });
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initFontSizeAdjust();
    await initPagerColumnCount();
    await initCategoriesSort();
    await initAutoClean();
    await initDisplayJmcode();
    await initSearchTitleWords();
    await initWebDavUrl();
    await initWebDavUserName();
    await initWebDavPassword();
    await initProxy();

    // 启动配置来自本地持久化，旧缓存损坏时应裁剪/过滤，而不是让初始化流程抛异常。
    expect(
      currentFontSizeAdjust(FontSizeAdjustType.fontSizeAdjustCommentContent),
      5,
    );
    expect(pagerColumnNumber, 1);
    expect(getCategoriesSort(), [3, 2, 1]);
    expect(autoCleanName(), 'off');
    expect(currentDisplayJmcode(), isFalse);
    expect(currentSearchTitleWords(), isTrue);
    expect(currentWebDavUrl, 'https://webdav.example/.jmtt2mic.history');
    expect(currentWebUserName, 'alice');
    expect(currentWebDavPassword, '  secret  ');
  });

  test('integer property parser accepts integer-like persisted values', () {
    // 本地配置可能来自旧桥接、WebDAV 快照或手工迁移；整数小数字符串应兼容，真小数仍回退。
    expect(
      parseBoundedIntPropertyValue('"3.0"', fallback: 0, min: -5, max: 5),
      3,
    );
    expect(
      parseBoundedIntPropertyValue('99.0', fallback: 0, min: 1, max: 10),
      10,
    );
    expect(
      parseBoundedIntPropertyValue('2.5', fallback: 4, min: 1, max: 10),
      4,
    );
    expect(
      parseBoundedIntPropertyValue(
        jsonEncode(jsonEncode('3.0')),
        fallback: 0,
        min: 1,
        max: 10,
      ),
      3,
    );
    expect(
      parseBoundedIntPropertyValue(
        jsonEncode(jsonEncode(jsonEncode('3.0'))),
        fallback: 4,
        min: 1,
        max: 10,
      ),
      4,
    );
  });

  test('auto clean parser keeps only supported intervals', () {
    // 自动清理周期需要和设置页档位保持一致；JSON 包装可兼容，未知/负数不能被当成有效周期。
    expect(normalizeAutoCleanValue(jsonEncode('0.0')), '0');
    expect(normalizeAutoCleanValue(jsonEncode(jsonEncode('43200'))), '43200');
    expect(normalizeAutoCleanValue('123'), '${3600 * 24 * 7}');
    expect(normalizeAutoCleanValue('-1'), '${3600 * 24 * 7}');
    expect(normalizeAutoCleanValue('bad'), '${3600 * 24 * 7}');
  });

  test('boolean property parser accepts loose persisted values', () {
    // 布尔配置由多个开关共用；只接受明确布尔语义，损坏值继续走默认值。
    expect(parseBoolPropertyValue('"TRUE"', fallback: false), isTrue);
    expect(parseBoolPropertyValue(' off ', fallback: true), isFalse);
    expect(parseBoolPropertyValue('1.0', fallback: false), isTrue);
    expect(parseBoolPropertyValue('2', fallback: false), isFalse);
    expect(
      parseBoolPropertyValue(jsonEncode(jsonEncode('on')), fallback: false),
      isTrue,
    );
    expect(
      parseBoolPropertyValue(
        jsonEncode(jsonEncode(jsonEncode('on'))),
        fallback: false,
      ),
      isFalse,
    );
  });

  test('enum property parser accepts bare and full saved names', () {
    // 枚举配置来自本地属性、WebDAV 快照和旧迁移脚本；兼容裸名称/JSON 包装可避免同步后回退默认值。
    expect(
      parseEnumPropertyValue(
        jsonEncode(' LANDSCAPE '),
        AppOrientation.values,
        AppOrientation.normal,
      ),
      AppOrientation.landscape,
    );
    expect(
      parseEnumPropertyValue(
        jsonEncode(jsonEncode('ReaderType.twoPageGallery')),
        ReaderType.values,
        ReaderType.webtoon,
      ),
      ReaderType.twoPageGallery,
    );
    expect(
      parseEnumPropertyValue(
        'bad-mode',
        PagerViewMode.values,
        PagerViewMode.cover,
      ),
      PagerViewMode.cover,
    );
  });

  test('locale and theme property parsers accept legacy aliases', () {
    // 语言和主题是启动早期配置；旧缓存里夹带 Locale tag/主题别名时应归一到当前协议值。
    expect(normalizeAppLocaleCode(jsonEncode(' EN_us ')), 'en');
    expect(normalizeAppLocaleCode(jsonEncode(jsonEncode('zh-Hans-CN'))), 'zh');
    expect(normalizeAppLocaleCode('bad-locale'), 'system');
    expect(normalizeThemeCode(jsonEncode(' DARK ')), '2');
    expect(normalizeThemeCode(jsonEncode(jsonEncode('light'))), '1');
    expect(normalizeThemeCode('bad-theme'), '0');
  });

  test('string property parser unwraps only JSON string layers', () {
    // 字符串配置可能被旧桥接双层编码；密码等敏感字段仍要保留有效空白。
    expect(
      parseStringPropertyValue(jsonEncode(' https://example '), trim: true),
      'https://example',
    );
    expect(
      parseStringPropertyValue(jsonEncode(jsonEncode(' alice ')), trim: true),
      'alice',
    );
    expect(
      parseStringPropertyValue(jsonEncode('  secret  ')),
      '  secret  ',
    );
    expect(
      parseStringPropertyValue('"   "', fallback: 'fallback', trim: true),
      'fallback',
    );
  });

  test('android display mode accepts only current device modes', () {
    const modes = ['60.000', '90.000', '120.000'];

    expect(
      normalizeAndroidDisplayModeValue(jsonEncode(' 120.000 '), modes),
      '120.000',
    );
    expect(
      normalizeAndroidDisplayModeValue(jsonEncode(jsonEncode('90.000')), modes),
      '90.000',
    );
    expect(normalizeAndroidDisplayModeValue('144.000', modes), '');
  });

  test('sortCategories uses saved order without repeated index scans',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property' &&
          payload['params'] == 'categoriesSort') {
        return '{"error_message":"","response_data":"[3,1]"}';
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initCategoriesSort();
    final categories = [
      _categoryForTest(1),
      _categoryForTest(2),
      _categoryForTest(3),
      _categoryForTest(4),
    ];

    sortCategories(categories);

    // 已保存排序优先，未命中的分类仍保持原始相对顺序。
    expect(categories.map((item) => item.id), [3, 1, 2, 4]);
  });

  test('categories sort decodes nested json array property', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'load_property' &&
          payload['params'] == 'categoriesSort') {
        return jsonEncode({
          'error_message': '',
          'response_data': jsonEncode(jsonEncode([4, ' 2 ', 4, 0, 'bad', 1])),
        });
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initCategoriesSort();

    // WebDAV 或手工脚本可能把数组多包 JSON 字符串；仍保留用户排序并过滤脏 ID。
    expect(getCategoriesSort(), [4, 2, 1]);
  });

  test('categories sort selection filters stale ids before saving', () async {
    final categories = [
      _categoryForTest(1),
      _categoryForTest(2),
      _categoryForTest(3),
    ];
    expect(
      restoreCategoriesSortSelection([3, 3, 99, 1], categories),
      [3, 1],
    );

    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<String, dynamic>? savedParams;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      if (payload['method'] == 'save_property') {
        savedParams = Map<String, dynamic>.from(
          jsonDecode(payload['params'] as String) as Map,
        );
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final source = [3, 3, 0, 2, -1];
    await saveCategoriesSort(source);
    source.add(1);

    // 保存路径会收敛旧缓存/拖拽异常产生的重复和非法 ID，并隔离调用方后续修改。
    expect(getCategoriesSort(), [3, 2]);
    expect(() => getCategoriesSort().add(4), throwsUnsupportedError);
    expect(savedParams, {'k': 'categoriesSort', 'v': '[3,2]'});
  });

  test('method response decoder normalizes string list payloads', () {
    final list = decodeStringListResponse(
      '[" host-a ", "", null, "host-b", 3, "host-a"]',
      'load_api_host_list',
      dedupe: true,
    );

    expect(list, ['host-a', 'host-b', '3']);
    expect(() => list.add('x'), throwsUnsupportedError);
  });

  test('method response decoder keeps duplicates when dedupe disabled', () {
    final list = decodeStringListResponse(
      '["a","a","b"]',
      'load_api_host_list',
    );

    expect(list, ['a', 'a', 'b']);
  });

  test('API host init normalizes persisted URL-like values', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final savedHosts = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      switch (payload['method']) {
        case 'load_api_host_list':
          return jsonEncode({
            'error_message': '',
            'response_data': jsonEncode([
              ' https://API.example.com/path ',
              'api.example.com',
              'cdn.example.com/sub-path',
            ]),
          });
        case 'load_api_host':
          return jsonEncode({
            'error_message': '',
            'response_data':
                jsonEncode(' https://API.example.com/path?from=legacy '),
          });
        case 'save_api_host':
          savedHosts.add(payload['params'] as String);
          return '{"error_message":"","response_data":""}';
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initApiHost();

    // 手动配置和旧缓存可能保存完整 URL；当前会话也应立即收敛成后端需要的 host[:port]。
    expect(currentApiHostName, 'API.example.com');
    expect(savedHosts, ['API.example.com']);
    expect(
      normalizeApiHostCandidate(' http://cdn.example.com:8080/a#frag '),
      'cdn.example.com:8080',
    );
    expect(
      normalizeApiHostCandidate(' //user:pass@api.example.com:9443/a '),
      'api.example.com:9443',
    );
    expect(
      normalizeApiHostCandidate(
        jsonEncode(jsonEncode(' https://wrapped.example.com/a ')),
      ),
      'wrapped.example.com',
    );
    expect(normalizeApiHostCandidate(' /empty ', fallback: 'fallback'),
        'fallback');
  });

  test('CDN host init normalizes URL-like values before saving', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final savedHosts = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      switch (payload['method']) {
        case 'load_cdn_host':
          return jsonEncode({
            'error_message': '',
            'response_data': ' //user:pass@CDN.example.com:9443/path?x=1 ',
          });
        case 'save_cdn_host':
          savedHosts.add(payload['params'] as String);
          return '{"error_message":"","response_data":""}';
      }
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await initCdnHost();

    // CDN 和 API 使用同一 host 归一化规则；旧缓存里的 URL/userinfo 不应进入测速或保存。
    expect(currentCdnHostName, 'CDN.example.com:9443');
    expect(savedHosts, ['CDN.example.com:9443']);
    expect(
      normalizeNetworkHostCandidate('https://user:pass@[::1]:9443/ping'),
      '[::1]:9443',
    );
    expect(
      normalizeNetworkHostCandidate(jsonEncode(' //cdn-wrap.example.com/a ')),
      'cdn-wrap.example.com',
    );
  });

  test('download export selection toggles and restores by live ids', () {
    final selected = <int>{};

    toggleSelectedDownloadId(selected, 3);
    toggleSelectedDownloadId(selected, 1);
    toggleSelectedDownloadId(selected, 3);
    toggleSelectedDownloadId(selected, 2);

    expect(selected.toList(), [1, 2]);

    // 导出完成后刷新列表时，只保留仍然可导出的下载项，并保留用户选择顺序。
    final restored = restoreSelectedIdSet(
      <int>{3, 1, 2},
      [_downloadAlbumForTest(2), _downloadAlbumForTest(1)],
    );

    expect(restored.toList(), [1, 2]);
    expect(
      restoreSelectedIds([3, 1, 2], [_downloadAlbumForTest(1)]),
      [1],
    );
  });

  test('download import archive detection only accepts backend formats', () {
    expect(
      detectDownloadImportArchiveKind(r'C:\exports\book.jm.zip'),
      DownloadImportArchiveKind.jmZip,
    );
    expect(
      detectDownloadImportArchiveKind('/tmp/book.JMI '),
      DownloadImportArchiveKind.jmi,
    );
    expect(detectDownloadImportArchiveKind('/tmp/book.zip'), isNull);
    expect(detectDownloadImportArchiveKind('/tmp/book.jm.zip.tmp'), isNull);
  });

  test('comic download selection helpers keep order and skip tasked ids', () {
    final album = _albumResponseForTest([
      {'id': 301, 'name': 'downloaded', 'sort': '1'},
      {'id': 302, 'name': 'second', 'sort': '2'},
      {'id': 303, 'name': 'third', 'sort': '3'},
    ]);
    final series = downloadSeriesForAlbum(album);
    final tasked = <int>{301};
    final selected = selectableDownloadChapterIds(series, tasked);

    expect(selected.toList(), [302, 303]);

    toggleSelectedDownloadChapterId(selected, tasked, 302);
    toggleSelectedDownloadChapterId(selected, tasked, 301);
    toggleSelectedDownloadChapterId(selected, tasked, 302);

    // 已下载章节不会被加入；提交章节按原始 series 顺序，而不是按点击顺序。
    expect(selected.toList(), [303, 302]);
    expect(selectedDownloadChapters(series, selected).map((e) => e.id), [
      302,
      303,
    ]);
  });

  test('comic download visual state keeps tasked priority', () {
    final tasked = <int>{301};
    final selected = <int>{301, 302};

    // 已下载章节必须优先展示下载完成态，不能被“已选中”覆盖。
    expect(
      downloadChapterVisualState(tasked, selected, 301),
      DownloadChapterVisualState.tasked,
    );
    expect(
      downloadChapterVisualState(tasked, selected, 302),
      DownloadChapterVisualState.selected,
    );
    expect(
      downloadChapterVisualState(tasked, selected, 999),
      DownloadChapterVisualState.idle,
    );
  });

  test('comic download series helper falls back for single chapter album', () {
    final fallback = downloadSeriesForAlbum(_albumResponseForTest([]));

    expect(fallback.single.id, 20);
    expect(fallback.single.name, 'album');
    expect(fallback.single.sort, '1');
  });

  test('Methods.loadAndroidModes normalizes mixed payload safely', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidGetModes') {
        return [' 60Hz ', 120, '', null, '120', '60Hz'];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final modes = await methods.loadAndroidModes();

    // 通道返回混合类型时仍应稳定解析，避免设置页因为脏值直接抛错。
    expect(modes, ['60Hz', '120']);
  });

  test('Methods.loadAndroidModes supports object payload with modes list',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidGetModes') {
        return {
          'modes': [' 60Hz ', null, '120Hz', '60Hz']
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final modes = await methods.loadAndroidModes();

    expect(modes, ['60Hz', '120Hz']);
  });

  test('Methods.loadAndroidModes supports object payload with json list string',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidGetModes') {
        return {
          'mode_list': '[" 90Hz ","120Hz","90Hz"]',
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final modes = await methods.loadAndroidModes();

    expect(modes, ['90Hz', '120Hz']);
  });

  test('Methods.loadAndroidModes falls back on platform exceptions', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidGetModes') {
        throw PlatformException(
            code: 'unavailable', message: 'no display mode');
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final modes = await methods.loadAndroidModes();

    expect(modes, isEmpty);
  });

  test('Methods.setAndroidMode trims mode before invoking channel', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? modeArg;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'androidSetMode') {
        final payload = call.arguments as Map<dynamic, dynamic>;
        modeArg = payload['mode']?.toString();
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await methods.setAndroidMode(' 120Hz ');

    expect(modeArg, '120Hz');
  });

  test('Methods.set_download_thread clamps invalid thread count', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? invokedParams;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      final payload = jsonDecode(call.arguments as String);
      invokedParams = payload['params']?.toString();
      return '{"error_message":"","response_data":""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await methods.set_download_thread(99);

    // 前端先做边界归一化，避免无效值反复跨端并触发后端存储写入。
    expect(invokedParams, '5');
  });

  test('Methods.load_download_thread falls back when payload is invalid',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      return '{"error_message":"","response_data":"invalid-int"}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final value = await methods.load_download_thread();

    // 历史配置损坏时回退到最小线程数，避免 UI 初始化阶段直接抛异常。
    expect(value, 1);
  });

  test('Methods.load_download_thread clamps out-of-range payload', () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      return '{"error_message":"","response_data":"99"}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final value = await methods.load_download_thread();

    // 旧后端或异常缓存给出越界线程值时，前端应保持与当前协议上限一致。
    expect(value, 5);
  });

  test('Methods.load_download_thread accepts nested json string payload',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      return '{"error_message":"","response_data":"\\"4\\""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final value = await methods.load_download_thread();

    // 兼容旧桥接把数字包成 JSON 字符串的情况，避免初始化时误回退到默认值。
    expect(value, 4);
  });

  test('Methods.load_download_thread accepts nested decimal string payload',
      () async {
    const channel = MethodChannel('methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'invoke') {
        return null;
      }
      return '{"error_message":"","response_data":"\\"4.0\\""}';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final value = await methods.load_download_thread();

    // 某些旧桥接会把整数写成字符串小数，兼容解析可避免线程配置被错误回退。
    expect(value, 4);
  });
}

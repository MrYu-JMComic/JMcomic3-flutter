import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/method_response_decoder.dart';
import 'package:jmcomic3/screens/comic_download_shared.dart';
import 'package:jmcomic3/screens/download_import_shared.dart';
import 'package:jmcomic3/screens/downloads_export_shared.dart';
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

void main() {
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

  test('method response decoder converts map response to string map', () {
    final map = decodeStringMapResponse(
      '{"1":"one","host":2,"empty":null}',
      'config_links',
    );

    expect(map, {'1': 'one', 'host': '2', 'empty': ''});
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
}

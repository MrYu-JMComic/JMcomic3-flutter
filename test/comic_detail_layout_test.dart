import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/methods.dart' as native;
import 'package:jmcomic3/basic/navigator.dart';
import 'package:jmcomic3/configs/display_jmcode.dart';
import 'package:jmcomic3/configs/ignore_view_log.dart';
import 'package:jmcomic3/configs/login.dart' as login;
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/configs/reader_controller_type.dart';
import 'package:jmcomic3/configs/reader_direction.dart';
import 'package:jmcomic3/configs/reader_slider_position.dart';
import 'package:jmcomic3/configs/reader_type.dart';
import 'package:jmcomic3/configs/search_title_words.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_download_screen.dart';
import 'package:jmcomic3/screens/comic_info_screen.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';
import 'package:jmcomic3/screens/components/comic_comments_list.dart';
import 'package:jmcomic3/screens/components/comic_detail_chapters.dart';
import 'package:jmcomic3/screens/components/comic_detail_header.dart';
import 'package:jmcomic3/screens/components/images.dart';

const _channel = MethodChannel('methods');
const _previewKey = ValueKey('comic-detail-preview');
const _albumId = 81230;
const _firstChapterId = 81231;
const _secondChapterId = 81232;
const _longTitle =
    '山海之间 · A Journey Beyond the Horizon — Stories from the coast, '
    'the quiet forest and a city after rain [Digital edition]';
const _longDescription = '少年与朋友踏上寻找故乡的旅途，穿过春日的山谷与雨后的海岸。'
    '一本记录四季变化、友情与自然风景的冒险漫画。'
    '沿途的每一次相遇，都让他们重新理解归途的意义。'
    'The story follows a group of friends through changing seasons, '
    'quiet forests and coastal towns. Their journey brings new friendships '
    'and unexpected discoveries, with each chapter exploring a different '
    'landscape. This deliberately long description also verifies that '
    'expanding a synopsis does not hide the fixed reading controls.';
const _tags = [
  '远行',
  '山川',
  '冒险',
  '友情',
  '海岸',
  '自然',
  '城市',
  '星光',
  '归途',
  '冬日',
  '回忆',
];
final _saveScreenshots = Platform.environment['DETAIL_SCREENSHOTS'] == '1';

AlbumResponse _album({
  int id = _albumId,
  String name = _longTitle,
  String description = _longDescription,
  List<String> tags = _tags,
  List<Series>? series,
  bool favorite = false,
}) =>
    AlbumResponse(
      id: id,
      name: name,
      author: ['山间工作室'],
      images: const [],
      description: description,
      totalViews: 17820,
      likes: 240,
      series: series ??
          [
            Series(id: _secondChapterId, name: '海岸的约定', sort: '2'),
            Series(id: _firstChapterId, name: '春山的来信', sort: '1'),
          ],
      seriesId: id,
      commentTotal: 0,
      tags: tags,
      works: ['山海之间'],
      relatedList: [
        ComicBasic(
          id: 81300,
          author: 'Illustration studio',
          description: '',
          name: 'The forest after rain',
          image: '',
        ),
      ],
      liked: false,
      isFavorite: favorite,
      updateAt: 1791442800,
      addtime: 1788764400,
    );

ViewLog _viewLog({
  int id = _albumId,
  int chapter = _secondChapterId,
  int page = 14,
}) =>
    ViewLog(
      id: id,
      author: 'Old author metadata',
      description: '',
      name: 'Old title metadata',
      lastViewTime: 1791442800,
      lastViewChapterId: chapter,
      lastViewPage: page,
    );

ComicSimple _simple() => ComicSimple(
      id: _albumId,
      author: 'Stale cached author',
      description: '',
      name: 'Stale cached title',
      image: '',
      category: ComicSimpleCategory(title: '中文'),
      categorySub: ComicSimpleCategory(title: '冒险'),
    );

String _response(Object? data, {String error = ''}) => jsonEncode({
      'error_message': error,
      'response_data': data is String ? data : jsonEncode(data),
    });

class _Fixture {
  AlbumResponse album = _album();
  ViewLog? viewLog;
  bool signedIn = false;
  int albumFailures = 0;
  String? favoriteError;
  String favoriteType = 'add';
  Completer<void>? favoriteGate;
  Completer<void>? viewLogGate;
  String? coverPath;
  final requests = <Map<String, dynamic>>[];
  final _pendingCover = Completer<String>();
  final properties = <String, String>{
    'guest_mode': 'true',
    'pager_view_mode': PagerViewMode.titleAndCover.toString(),
    'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
    'pager_column_number': '3',
  };

  List<Map<String, dynamic>> calls(String method) =>
      requests.where((request) => request['method'] == method).toList();

  Future<String> handle(MethodCall call) async {
    final request = Map<String, dynamic>.from(
      jsonDecode(call.arguments as String) as Map,
    );
    requests.add(request);
    final method = request['method'];
    final params = request['params'] as String;
    switch (method) {
      case 'load_property':
        return _response(properties[params] ?? '');
      case 'save_property':
        final values = jsonDecode(params) as Map;
        properties[values['k'] as String] = values['v'] as String;
        return _response('');
      case 'logout':
      case 'clean_all_cache':
        return _response('');
      case 'pre_login':
        return _response({
          'pre_set': signedIn,
          'pre_login': signedIn,
          'message': '',
          'self_info': signedIn
              ? {
                  'uid': 42,
                  'username': 'Detail reader',
                  'email': 'reader@example.invalid',
                  'emailverified': 'yes',
                  'photo': '?v=0?v=',
                  'fname': 'Reader',
                  'gender': '',
                  'message': '',
                  'coin': 0,
                  'album_favorites': 0,
                  's': '',
                  'level_name': 'Reader',
                  'level': 1,
                  'nextLevelExp': 100,
                  'exp': '0',
                  'expPercent': 0.0,
                  'badges': <Object>[],
                  'album_favorites_max': 100,
                }
              : null,
        });
      case 'favorite':
        return _response({
          'total': 0,
          'count': 0,
          'list': <Object>[],
          'folder_list': <Object>[],
        });
      case 'pro_info_all':
        return _response({
          'pro_info_af': {'is_pro': true, 'expire': 4102444800},
          'pro_info_pat': {'is_pro': true},
        });
      case 'album':
        if (albumFailures > 0) {
          albumFailures--;
          return _response('', error: 'network unavailable');
        }
        return _response(album.toJson());
      case 'find_view_log':
        if (viewLogGate != null) await viewLogGate!.future;
        return _response(viewLog?.toJson());
      case 'forum':
        return _response({'list': <Object>[], 'total': 0});
      case 'download_by_id':
        return _response(null);
      case 'chapter':
        return _response({
          'id': int.parse(params),
          'series': album.series.map((chapter) => chapter.toJson()).toList(),
          'tags': '',
          'name': 'Reader entry fixture',
          'images': <Object>[],
          'series_id': album.id,
          'is_favorite': false,
          'liked': false,
        });
      case 'set_favorite':
        if (favoriteGate != null) await favoriteGate!.future;
        if (favoriteError != null) {
          return _response('', error: favoriteError!);
        }
        return _response({'status': 'ok', 'msg': '', 'type': favoriteType});
      case 'jm_3x4_cover':
      case 'jm_square_cover':
        if (coverPath != null) return _response(coverPath!);
        return _pendingCover.future;
      default:
        throw StateError('Unexpected detail method: $method');
    }
  }

  Future<void> createCover() async {
    // A self-contained illustration keeps screenshots deterministic and avoids
    // using real comic pages or a remote network image in layout tests.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 240, 320),
        Paint()..color = const Color(0xFFAFD6D7));
    canvas.drawCircle(
        const Offset(174, 73), 32, Paint()..color = const Color(0xFFFFF4CC));
    final distantHill = Path()
      ..moveTo(0, 188)
      ..quadraticBezierTo(58, 100, 130, 194)
      ..quadraticBezierTo(190, 118, 240, 185)
      ..lineTo(240, 320)
      ..lineTo(0, 320)
      ..close();
    canvas.drawPath(distantHill, Paint()..color = const Color(0xFF6A9F98));
    final frontHill = Path()
      ..moveTo(0, 245)
      ..quadraticBezierTo(80, 150, 172, 254)
      ..quadraticBezierTo(211, 211, 240, 232)
      ..lineTo(240, 320)
      ..lineTo(0, 320)
      ..close();
    canvas.drawPath(frontHill, Paint()..color = const Color(0xFF235D57));
    canvas.drawPath(
      Path()
        ..moveTo(83, 320)
        ..quadraticBezierTo(105, 249, 148, 254),
      Paint()
        ..color = const Color(0xFFE3C99C)
        ..strokeWidth = 16
        ..style = PaintingStyle.stroke,
    );
    final picture = recorder.endRecording();
    final bitmap = await picture.toImage(240, 320);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/detail-redesign/fixture-cover.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    coverPath = file.absolute.path;
    bitmap.dispose();
    picture.dispose();
  }
}

Widget _host(
  Widget child, {
  double textScale = 1,
  bool dark = false,
  Locale locale = const Locale('en'),
}) {
  final base = dark ? app_theme.darkTheme : app_theme.lightTheme;
  final theme = _saveScreenshots
      ? base.copyWith(
          textTheme: base.textTheme.apply(fontFamily: 'DetailPreview'),
          primaryTextTheme:
              base.primaryTextTheme.apply(fontFamily: 'DetailPreview'),
        )
      : base;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [routeObserver],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(key: _previewKey, child: child!),
    ),
    home: child,
  );
}

Future<void> _previewFonts(WidgetTester tester) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    final candidates = [
      File('C:/Windows/Fonts/msyh.ttc'),
      File('C:/Windows/Fonts/segoeui.ttf'),
    ];
    for (final font in candidates) {
      if (!await font.exists()) continue;
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['DetailPreview', 'Roboto']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
      break;
    }
    final config =
        jsonDecode(await File('.dart_tool/package_config.json').readAsString())
            as Map;
    final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
    final icons = File(
        '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });
}

Future<_Fixture> _prepare(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  bool signedIn = false,
}) async {
  final fixture = _Fixture()..signedIn = signedIn;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, fixture.handle);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    if (fixture.favoriteGate != null && !fixture.favoriteGate!.isCompleted) {
      fixture.favoriteGate!.complete();
    }
    if (fixture.viewLogGate != null && !fixture.viewLogGate!.isCompleted) {
      fixture.viewLogGate!.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    messenger.setMockMethodCallHandler(_channel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await native.methods.logout();
  clearAllImageMemoryCaches();
  await initIgnoreVewLog();
  await initSearchTitleWords();
  await initDisplayJmcode();
  await initPagerViewMode();
  await initPagerCoverRate();
  await initPagerColumnCount();
  await initReaderType();
  await initReaderDirection();
  await initReaderControllerType();
  await initReaderSliderPosition();
  await initTwoPageDirection();
  await initVolumeKeyControl();
  await initNoAnimation();
  await _previewFonts(tester);
  if (_saveScreenshots) {
    await tester.runAsync(fixture.createCover);
  }
  await tester.pumpWidget(_host(const Scaffold(
    body: SizedBox(key: ValueKey('detail-login-context')),
  )));
  await login.initLogin(
    tester.element(find.byKey(const ValueKey('detail-login-context'))),
  );
  await tester.pumpAndSettle();
  expect(login.loginStatus,
      signedIn ? login.LoginStatus.loginSuccess : login.LoginStatus.guest);
  return fixture;
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double textScale = 1,
  bool dark = false,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(_host(
    ComicInfoScreen(fixture.album.id, _simple()),
    textScale: textScale,
    dark: dark,
    locale: locale,
  ));
  await tester.pumpAndSettle();
}

Finder _key(String name) => find.byKey(ValueKey('comic-detail-$name'));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    for (var frame = 0; frame < 8; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/detail-redesign/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

void _expectFilledChapterRows(
  WidgetTester tester,
  List<Series> chapters,
) {
  final panel = tester.getRect(find.byType(ComicDetailChapters));
  final rows = <double, List<Rect>>{};
  for (final chapter in chapters) {
    final rect = tester.getRect(_key('chapter-${chapter.id}'));
    rows.putIfAbsent(rect.top, () => []).add(rect);
  }
  for (final row in rows.values) {
    expect(row.first.left, closeTo(panel.left + 12, .001));
    expect(row.last.right, closeTo(panel.right - 12, .001));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detail reading target', () {
    test('new readers start at the first sorted chapter without reordering it',
        () {
      final album = _album();
      final target = comicDetailReadingTarget(album, null);
      expect(target, (chapterId: _firstChapterId, page: 0, continuing: false));
      expect(album.series.map((chapter) => chapter.id),
          [_secondChapterId, _firstChapterId]);
    });

    test('matching history resumes its chapter and zero-based page', () {
      expect(comicDetailReadingTarget(_album(), _viewLog()),
          (chapterId: _secondChapterId, page: 14, continuing: true));
      expect(comicDetailReadingTarget(_album(), _viewLog(page: -3)),
          (chapterId: _secondChapterId, page: 0, continuing: true));
    });

    test('foreign or removed chapters fall back to the first readable chapter',
        () {
      for (final history in [
        _viewLog(id: 99999),
        _viewLog(chapter: 99999),
        _viewLog(chapter: 0),
      ]) {
        expect(comicDetailReadingTarget(_album(), history),
            (chapterId: _firstChapterId, page: 0, continuing: false));
      }
    });

    test('a single-album reader accepts only history for that album chapter',
        () {
      final album = _album(series: []);
      expect(comicDetailReadingTarget(album, null),
          (chapterId: _albumId, page: 0, continuing: false));
      expect(comicDetailReadingTarget(album, _viewLog(chapter: _albumId)),
          (chapterId: _albumId, page: 14, continuing: true));
      expect(comicDetailReadingTarget(album, _viewLog()),
          (chapterId: _albumId, page: 0, continuing: false));
    });
  });

  for (final layout in [
    (
      name: 'detail-mobile-light',
      size: const Size(390, 844),
      scale: 1.0,
      dark: false
    ),
    (
      name: 'detail-mobile-dark',
      size: const Size(390, 844),
      scale: 1.0,
      dark: true
    ),
    (
      name: 'detail-desktop-light',
      size: const Size(1000, 800),
      scale: 1.0,
      dark: false
    ),
    (
      name: 'detail-desktop-dark',
      size: const Size(1000, 800),
      scale: 1.0,
      dark: true
    ),
    (
      name: 'detail-compact-large-text',
      size: const Size(320, 700),
      scale: 2.0,
      dark: true
    ),
  ]) {
    testWidgets('${layout.name} keeps content and reading actions in bounds',
        (tester) async {
      final fixture = await _prepare(tester, size: layout.size);
      await _mount(tester, fixture,
          textScale: layout.scale,
          dark: layout.dark,
          locale: const Locale('zh', 'CN'));
      final title = tester.widget<Text>(_key('title'));
      expect(title.textSpan!.toPlainText(), _longTitle);
      expect(title.maxLines, 2);
      expect(find.text('Stale cached title'), findsNothing);
      final cover = tester.widget<JM3x4Cover>(_key('cover'));
      expect(cover.width! / cover.height!, closeTo(3 / 4, .001));
      expect(cover.fit, BoxFit.cover);
      final pageColor =
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor!;
      final tagColors = <Color>{};
      // Adventure also appears as a category badge; inspect the unambiguous
      // tag labels here so the check targets the actual tag chips.
      for (final tag in _tags.take(7).where((tag) => tag != '冒险')) {
        final label = find.text(tag);
        final material =
            tester.element(label).findAncestorWidgetOfExactType<Material>()!;
        final visibleColor = Color.alphaBlend(material.color!, pageColor);
        tagColors.add(visibleColor);
        expect(visibleColor, isNot(pageColor),
            reason: 'Tag $tag has a visible fill');
        expect(tester.widget<Text>(label).style!.color, isNot(visibleColor));
        final border = (material.shape! as RoundedRectangleBorder).side;
        expect(border.style, BorderStyle.solid);
        expect(border.width, inInclusiveRange(0.1, 1.0));
        expect(border.color.a, greaterThan(0));
      }
      expect(tagColors.length, greaterThan(1));
      for (final action in ['download', 'favorite', 'read']) {
        final rect = tester.getRect(_key(action));
        expect(rect.left, greaterThanOrEqualTo(0), reason: action);
        expect(rect.right, lessThanOrEqualTo(layout.size.width),
            reason: action);
        expect(rect.bottom, lessThanOrEqualTo(layout.size.height),
            reason: action);
        expect(_key(action).hitTestable(), findsOneWidget, reason: action);
      }
      expect(tester.takeException(), isNull);
      await _capture(tester, layout.name);
      await tester.drag(_key('scroll'), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_key('read').hitTestable(), findsOneWidget);
    });
  }

  testWidgets('long title, tags and synopsis expand and collapse independently',
      (tester) async {
    final fixture = await _prepare(tester);
    await _mount(tester, fixture);
    expect(tester.widget<Text>(_key('title')).maxLines, 2);
    expect(tester.widget<Text>(_key('description')).maxLines, 3);
    expect(find.text('星光'), findsNothing);
    await _tapVisible(tester, _key('title-expand'));
    expect(tester.widget<Text>(_key('title')).maxLines, isNull);
    await _tapVisible(tester, _key('tags-expand'));
    expect(find.text('星光'), findsOneWidget);
    expect(find.text('回忆'), findsOneWidget);
    await _tapVisible(tester, _key('description-expand'));
    expect(tester.widget<Text>(_key('description')).maxLines, isNull);
    expect(tester.widget<Text>(_key('title')).maxLines, isNull);
    await _capture(tester, 'detail-expanded');
    await _tapVisible(tester, _key('description-expand'));
    expect(tester.widget<Text>(_key('description')).maxLines, 3);
    await _tapVisible(tester, _key('tags-expand'));
    expect(find.text('星光'), findsNothing);
    await _tapVisible(tester, _key('title-expand'));
    expect(tester.widget<Text>(_key('title')).maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English tabs align at 320px with double text scaling',
      (tester) async {
    final fixture = await _prepare(tester, size: const Size(320, 700));
    await _mount(tester, fixture, textScale: 2);
    await tester.ensureVisible(_key('tab-0'));
    await tester.pumpAndSettle();
    final first = tester.getRect(_key('tab-0'));
    for (final index in [1, 2]) {
      final rect = tester.getRect(_key('tab-$index'));
      expect(rect.top, closeTo(first.top, .001));
      expect(rect.height, closeTo(first.height, .001));
      expect(rect.bottom, closeTo(first.bottom, .001));
    }
    expect(tester.takeException(), isNull);
    await _capture(tester, 'detail-compact-english-tabs');
  });

  testWidgets(
      'header metadata searches use real values and respect JM preference',
      (tester) async {
    final fixture = await _prepare(tester);
    final searches = <String>[];
    fixture.properties['displayJmcode'] = 'false';
    await initDisplayJmcode();
    Widget header() => _host(Scaffold(
          body: SingleChildScrollView(
            child: ComicDetailHeader(
              album: fixture.album,
              simple: _simple(),
              onSearch: searches.add,
            ),
          ),
        ));
    await tester.pumpWidget(header());
    await tester.pumpAndSettle();
    final comicCode = find.byWidgetPredicate((widget) =>
        widget is Text &&
        widget.textSpan?.toPlainText().contains('JM$_albumId') == true);
    expect(comicCode, findsNothing);
    await _tapVisible(tester, find.text('Author: 山间工作室'));
    await _tapVisible(tester, find.text('Work: 山海之间'));
    await _tapVisible(tester, find.text('远行'));
    await _tapVisible(tester, find.text('中文'));
    expect(searches, ['山间工作室', '山海之间', '远行', '中文']);
    expect(find.text('Stale cached author'), findsNothing);
    fixture.properties['displayJmcode'] = 'true';
    await initDisplayJmcode();
    await tester.pumpWidget(header());
    await tester.pumpAndSettle();
    expect(comicCode, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'title keyword links preserve brackets and send the chosen keyword',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.album = _album(name: '[Nature] 山海之间 [Digital edition]');
    fixture.properties['searchTitleWords'] = 'true';
    await initSearchTitleWords();
    final searches = <String>[];
    Widget header() => _host(Scaffold(
          body: SingleChildScrollView(
            child: ComicDetailHeader(
              album: fixture.album,
              onSearch: searches.add,
            ),
          ),
        ));
    await tester.pumpWidget(header());
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(_key('title')).textSpan! as TextSpan;
    expect(title.toPlainText(), fixture.album.name);
    final links = title.children!
        .whereType<TextSpan>()
        .where((span) => span.recognizer is TapGestureRecognizer)
        .toList();
    expect(links.map((span) => span.text), ['Nature', 'Digital edition']);
    (links.first.recognizer! as TapGestureRecognizer).onTap!();
    (links.last.recognizer! as TapGestureRecognizer).onTap!();
    expect(searches, ['Nature', 'Digital edition']);
    fixture.properties['searchTitleWords'] = 'false';
    await initSearchTitleWords();
    await tester.pumpWidget(header());
    await tester.pumpAndSettle();
    final unlinked = tester.widget<Text>(_key('title')).textSpan! as TextSpan;
    expect(unlinked.toPlainText(), fixture.album.name);
    expect(
      unlinked.children!
          .whereType<TextSpan>()
          .where((span) => span.recognizer != null),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('short metadata has no unnecessary expansion controls',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.album = _album(
      name: '春山',
      description: 'A quiet journey.',
      tags: ['山川', '山川', '自然', ' ', '海岸'],
      series: [],
    );
    await _mount(tester, fixture);
    for (final name in ['title-expand', 'description-expand', 'tags-expand']) {
      expect(_key(name), findsNothing);
    }
    expect(find.text('山川'), findsOneWidget);
    expect(find.text(' '), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'detail-single-album');
  });

  testWidgets('reading controls stay fixed while the chapter list scrolls',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.album = _album(
      series: List.generate(
        30,
        (index) => Series(
            id: _firstChapterId + index,
            name: 'Chapter ${index + 1}',
            sort: '${index + 1}'),
      ),
    );
    await _mount(tester, fixture);
    final initial = tester.getRect(_key('read'));
    await tester.drag(_key('scroll'), const Offset(0, -1600));
    await tester.pumpAndSettle();
    expect(tester.getRect(_key('read')), initial);
    expect(_key('read').hitTestable(), findsOneWidget);
    expect(find.ancestor(of: _key('read'), matching: _key('scroll')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'short numbered chapters use at least four columns on a 320px phone',
      (tester) async {
    await _prepare(tester, size: const Size(320, 700));
    final chapters = List.generate(
      12,
      (index) => Series(id: 81400 + index, name: '', sort: '${index + 1}'),
    );
    final album = _album(series: chapters);
    final reads = <(int, int)>[];
    await tester.pumpWidget(_host(Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ComicDetailChapters(
            album: album,
            viewFuture: Future<ViewLog?>.value(null),
            onRead: (id, page) => reads.add((id, page)),
          ),
        ),
      ),
    )));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(ComicDetailChapters));
    final first = tester.getRect(_key('chapter-${chapters.first.id}'));
    for (final chapter in chapters.take(4)) {
      final rect = tester.getRect(_key('chapter-${chapter.id}'));
      expect(rect.top, closeTo(first.top, .001));
      expect(rect.width, lessThan(panel.width / 3));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(find.text(chapter.sort), findsOneWidget);
    }
    _expectFilledChapterRows(tester, chapters);
    await _tapVisible(tester, _key('chapter-${chapters[3].id}'));
    expect(reads, [(chapters[3].id, 0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long chapter names flow naturally without clipping or reordering',
      (tester) async {
    await _prepare(tester);
    final chapters = [
      Series(id: 81500, name: '', sort: '9'),
      Series(
        id: 81501,
        name: '山海之间的旅途与一个跨越春日山谷和雨后海岸的长篇故事，所有章节文字都应该完整显示',
        sort: '2',
      ),
      Series(id: 81502, name: '', sort: '1'),
      Series(id: 81503, name: '雨后', sort: '4'),
    ];
    final album = _album(series: chapters);
    final reads = <(int, int)>[];
    Widget component(double scale) => _host(
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ComicDetailChapters(
                  album: album,
                  viewFuture: Future<ViewLog?>.value(null),
                  onRead: (id, page) => reads.add((id, page)),
                ),
              ),
            ),
          ),
          textScale: scale,
        );
    await tester.pumpWidget(component(1));
    await tester.pumpAndSettle();
    final short = tester.getRect(_key('chapter-${chapters[2].id}'));
    final long = tester.getRect(_key('chapter-${chapters[1].id}'));
    final next = tester.getRect(_key('chapter-${chapters[2].id}'));
    expect(long.width, greaterThan(short.width));
    expect(next.top, greaterThan(long.bottom));
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(component(scale));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byType(ComicDetailChapters));
      expect(tester.getRect(_key('chapter-${chapters[1].id}')).width,
          closeTo(panel.width - 24, .001));
      _expectFilledChapterRows(tester, chapters);
      final rendered = tester.widgetList<OutlinedButton>(
        find.descendant(
            of: find.byType(ComicDetailChapters),
            matching: find.byType(OutlinedButton)),
      );
      expect(
          rendered.map((button) => button.key),
          chapters.map(
              (chapter) => ValueKey('comic-detail-chapter-${chapter.id}')));
      for (final chapter in chapters) {
        final rect = tester.getRect(_key('chapter-${chapter.id}'));
        final title = chapter.name.isEmpty
            ? chapter.sort
            : '${chapter.sort} - ${chapter.name}';
        expect(find.text(title), findsOneWidget);
        expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.left, greaterThanOrEqualTo(panel.left));
        expect(rect.right, lessThanOrEqualTo(panel.right));
      }
      expect(tester.takeException(), isNull);
    }
    await _tapVisible(tester, _key('chapter-${chapters[1].id}'));
    expect(reads, [(chapters[1].id, 0)]);
    expect(album.series, orderedEquals(chapters));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        '41 chapters flow in the complete ${dark ? 'dark' : 'light'} detail page',
        (tester) async {
      final fixture = await _prepare(tester);
      fixture.album = _album(
        name: '山海之间',
        description: '少年与朋友踏上寻找故乡的旅途，穿过春日的山谷与雨后的海岸。',
        tags: _tags.take(7).toList(),
        series: List.generate(
          41,
          (index) => Series(id: 81600 + index, name: '', sort: '${index + 1}'),
        ),
      );
      await _mount(tester, fixture,
          dark: dark, locale: const Locale('zh', 'CN'));
      final first = _key('chapter-81600');
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      final firstRowTop = tester.getRect(first).top;
      for (var index = 0; index < 4; index++) {
        expect(tester.getRect(_key('chapter-${81600 + index}')).top,
            closeTo(firstRowTop, .001));
      }
      _expectFilledChapterRows(tester, fixture.album.series);
      expect(
          tester.getRect(_key('directory-divider')).width, closeTo(390, .001));
      expect(tester.widget<Divider>(_key('directory-divider')).thickness,
          inInclusiveRange(.1, 1));
      expect(_key('read').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'detail-chapter-flow-${dark ? 'dark' : 'light'}');
      await tester.ensureVisible(_key('chapter-81640'));
      await tester.pumpAndSettle();
      expect(_key('chapter-81640').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'seven named chapters fill complete ${dark ? 'dark' : 'light'} detail rows',
        (tester) async {
      final fixture = await _prepare(tester);
      fixture.album = _album(
        name: '山海之间',
        description: '少年与朋友踏上寻找故乡的旅途，穿过春日的山谷与雨后的海岸。',
        tags: _tags.take(7).toList(),
        series: [
          for (final entry in const [
            '序章：雨后的山谷与一封来自远方的信',
            '穿越群山：寻找海岸边失落的灯塔与归途',
            '繁星之下：朋友们在夜晚的森林里交换心愿',
            '城市漫步：雨后的街道和重新相遇的故事',
            '四季流转：从春日的花田走到冬天的港湾',
            '在山海之间：关于陪伴、友情和重新出发',
            '终章：旅途尽头，我们找到了心里的故乡',
          ].indexed)
            Series(
                id: 81700 + entry.$1, name: entry.$2, sort: '${entry.$1 + 1}'),
        ],
      );
      await _mount(tester, fixture,
          dark: dark, locale: const Locale('zh', 'CN'));
      await tester.ensureVisible(_key('chapter-81700'));
      await tester.pumpAndSettle();
      _expectFilledChapterRows(tester, fixture.album.series);
      for (final chapter in fixture.album.series) {
        final title = '${chapter.sort} - ${chapter.name}';
        expect(find.text(title), findsOneWidget);
        expect(tester.widget<Text>(find.text(title)).maxLines, isNull);
      }
      expect(_key('directory-divider'), findsOneWidget);
      expect(_key('read').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(
          tester, 'detail-chapter-long-flow-${dark ? 'dark' : 'light'}');
    });
  }

  testWidgets('the read action waits for history before choosing an entry',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.viewLog = _viewLog();
    fixture.viewLogGate = Completer<void>();
    await _mount(tester, fixture);
    expect(tester.widget<FilledButton>(_key('read')).onPressed, isNull);
    fixture.viewLogGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_key('read')).onPressed, isNotNull);
    expect(
        find.descendant(
            of: _key('read'), matching: find.text('Continue reading')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('continue reading passes the real title, chapter and saved page',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.viewLog = _viewLog();
    await _mount(tester, fixture);
    await tester.tap(_key('read'));
    await tester.pumpAndSettle();
    final reader =
        tester.widget<ComicReaderScreen>(find.byType(ComicReaderScreen));
    expect(reader.comic.name, _longTitle);
    expect(reader.comic.id, _albumId);
    expect(reader.chapterId, _secondChapterId);
    expect(reader.initRank, 14);
    expect(fixture.calls('chapter').single['params'], '$_secondChapterId');
    fixture.viewLog = _viewLog(chapter: 99999);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(fixture.calls('find_view_log'), hasLength(2));
    expect(
        find.descendant(of: _key('read'), matching: find.text('Start reading')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removed chapter history starts from the first real chapter',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.viewLog = _viewLog(chapter: 99999);
    await _mount(tester, fixture);
    await tester.tap(_key('read'));
    await tester.pumpAndSettle();
    final reader =
        tester.widget<ComicReaderScreen>(find.byType(ComicReaderScreen));
    expect(reader.chapterId, _firstChapterId);
    expect(reader.initRank, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single-album reading and selected chapters remain accessible',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.album = _album(series: [], name: '春山');
    await _mount(tester, fixture);
    await tester.tap(_key('read'));
    await tester.pumpAndSettle();
    final reader =
        tester.widget<ComicReaderScreen>(find.byType(ComicReaderScreen));
    expect(reader.chapterId, _albumId);
    expect(reader.initRank, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chapter row opens the chosen chapter from page zero',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.viewLog = _viewLog(page: 14);
    await _mount(tester, fixture);
    await _tapVisible(tester, _key('chapter-$_firstChapterId'));
    final reader =
        tester.widget<ComicReaderScreen>(find.byType(ComicReaderScreen));
    expect(reader.chapterId, _firstChapterId);
    expect(reader.initRank, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fixed download action navigates with the loaded album',
      (tester) async {
    final fixture = await _prepare(tester);
    await _mount(tester, fixture);
    await tester.tap(_key('download'));
    await tester.pumpAndSettle();
    final download =
        tester.widget<ComicDownloadScreen>(find.byType(ComicDownloadScreen));
    expect(download.album.id, _albumId);
    expect(download.album.name, _longTitle);
    expect(download.album.series.map((chapter) => chapter.id),
        [_secondChapterId, _firstChapterId]);
    expect(fixture.calls('download_by_id').single['params'], '$_albumId');
    expect(tester.takeException(), isNull);
  });

  testWidgets('comments load on demand and retain state across tab switches',
      (tester) async {
    final fixture = await _prepare(tester);
    await _mount(tester, fixture);
    expect(fixture.calls('forum'), isEmpty);
    await _tapVisible(tester, _key('tab-1'));
    final commentState =
        tester.state(find.byType(ComicCommentsList, skipOffstage: false));
    expect(fixture.calls('forum'), hasLength(1));
    expect(jsonDecode(fixture.calls('forum').single['params'] as String), {
      'mode': 'manhua',
      'aid': _albumId,
      'uid': null,
      'page': 1,
    });
    await _tapVisible(tester, _key('tab-2'));
    await _capture(tester, 'detail-recommended');
    await _tapVisible(tester, _key('tab-0'));
    await _tapVisible(tester, _key('tab-1'));
    expect(fixture.calls('forum'), hasLength(1));
    expect(tester.state(find.byType(ComicCommentsList, skipOffstage: false)),
        same(commentState));
    expect(fixture.calls('album'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('album failures offer a working retry without duplicate requests',
      (tester) async {
    final fixture = await _prepare(tester);
    fixture.albumFailures = 1;
    await _mount(tester, fixture);
    expect(_key('retry'), findsOneWidget);
    expect(fixture.calls('album'), hasLength(1));
    await _tapVisible(tester, _key('retry'));
    expect(fixture.calls('album'), hasLength(2));
    expect(_key('title'), findsOneWidget);
    expect(_key('retry'), findsNothing);
    expect(tester.widget<FilledButton>(_key('read')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'favorite changes are single-flight and respect server add/remove',
      (tester) async {
    final fixture = await _prepare(tester, signedIn: true);
    fixture.favoriteGate = Completer<void>();
    await _mount(tester, fixture);
    await tester.tap(_key('favorite'));
    // Two taps before the disabled state is rebuilt also exercise the async
    // login/check guard, rather than merely relying on a disabled button.
    await tester.tap(_key('favorite'));
    await tester.pump();
    expect(fixture.calls('set_favorite'), hasLength(1));
    expect(tester.widget<TextButton>(_key('favorite')).onPressed, isNull);
    fixture.favoriteGate!.complete();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _key('favorite'), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    fixture.favoriteGate = null;
    fixture.favoriteType = 'remove';
    await tester.tap(_key('favorite'));
    await tester.pumpAndSettle();
    expect(fixture.calls('set_favorite'), hasLength(2));
    expect(
        find.descendant(
            of: _key('favorite'), matching: find.byIcon(Icons.bookmark_border)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh cannot replace the album during a favorite update',
      (tester) async {
    final fixture = await _prepare(tester, signedIn: true);
    fixture.favoriteGate = Completer<void>();
    await _mount(tester, fixture);
    // Clear only transport caches so a broken refresh would issue a visible
    // second request instead of silently constructing a new cached album.
    await native.methods.cleanAllCache();
    await tester.tap(_key('favorite'));
    await tester.pump();
    expect(fixture.calls('set_favorite'), hasLength(1));
    final indicator =
        tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator));
    final refreshing = indicator.show();
    await tester.pumpAndSettle();
    await refreshing;
    expect(fixture.calls('album'), hasLength(1));
    expect(fixture.calls('find_view_log'), hasLength(1));
    fixture.favoriteGate!.complete();
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: _key('favorite'), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed favorite request keeps state and can be retried',
      (tester) async {
    final fixture = await _prepare(tester, signedIn: true);
    fixture.favoriteError = 'network unavailable';
    await _mount(tester, fixture);
    await tester.tap(_key('favorite'));
    await tester.pumpAndSettle();
    expect(fixture.calls('set_favorite'), hasLength(1));
    expect(
        find.descendant(
            of: _key('favorite'), matching: find.byIcon(Icons.bookmark_border)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    fixture.favoriteError = null;
    await tester.tap(_key('favorite'));
    await tester.pumpAndSettle();
    expect(fixture.calls('set_favorite'), hasLength(2));
    expect(
        find.descendant(
            of: _key('favorite'), matching: find.byIcon(Icons.bookmark)),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('finishing a favorite after leaving the screen does not setState',
      (tester) async {
    final fixture = await _prepare(tester, signedIn: true);
    fixture.favoriteGate = Completer<void>();
    await _mount(tester, fixture);
    await tester.tap(_key('favorite'));
    await tester.pump();
    expect(fixture.calls('set_favorite'), hasLength(1));
    await tester.pumpWidget(_host(const Scaffold(body: Text('Left detail'))));
    await tester.pumpAndSettle();
    fixture.favoriteGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Left detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

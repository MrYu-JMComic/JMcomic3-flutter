import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/methods.dart' as native;
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/configs/login.dart' as login_config;
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/app_screen.dart';
import 'package:jmcomic3/screens/browser_screen.dart';
import 'package:jmcomic3/screens/comic_search_screen.dart';
import 'package:jmcomic3/screens/components/comic_floating_search_bar.dart';
import 'package:jmcomic3/screens/components/comic_pager.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/user_screen.dart';

const _channel = MethodChannel('methods');
const _previewKey = ValueKey('layout-preview');
const _searchHint = 'Search comics, authors or keywords';
final _saveScreenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';
var _versionInitialized = false;

class _Fixture {
  final requests = <Map<String, dynamic>>[];
  final properties = <String, String>{
    'guest_mode': 'true',
    'pager_controller_mode': PagerControllerMode.pager.toString(),
    'pager_view_mode': PagerViewMode.titleAndCover.toString(),
    'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
    'pager_column_number': '3',
    'categoriesSort': '[]',
    'latestVersionRepoCache': 'MrYu-JMComic/JMcomic3-flutter',
  };
  final _pendingCover = Completer<String>();
  final coverPaths = <int, String>{};

  List<Map<String, dynamic>> calls(String method) =>
      requests.where((request) => request['method'] == method).toList();

  Future<String> handle(MethodCall call) async {
    final request = Map<String, dynamic>.from(
      jsonDecode(call.arguments as String) as Map,
    );
    requests.add(request);
    final method = request['method'];
    final params = request['params'];
    Object response;
    switch (method) {
      case 'load_property':
        response = properties[params] ?? '';
        break;
      case 'save_property':
        final values = jsonDecode(params as String) as Map;
        properties[values['k'] as String] = values['v'] as String;
        response = '';
        break;
      case 'pre_login':
        response = {
          'pre_set': false,
          'pre_login': false,
          'self_info': null,
          'message': '',
        };
        break;
      case 'pro_info_all':
        response = {
          'pro_info_af': {'is_pro': true, 'expire': 4102444800},
          'pro_info_pat': {'is_pro': true},
        };
        break;
      case 'logout':
        response = '';
        break;
      case 'categories':
        response = {
          'categories': [
            for (final category in const [
              (1, 'Alpha', 'alpha'),
              (2, 'Beta', 'beta'),
              (3, 'Gamma', 'gamma'),
            ])
              {
                'id': category.$1,
                'name': category.$2,
                'slug': category.$3,
                'total_albums': 6,
              },
          ],
          'blocks': [
            {
              'title': 'Topics',
              'content': ['Adventure', 'Nature']
            },
          ],
        };
        break;
      case 'comics':
      case 'comic_search':
        response = {
          'total': 6,
          'content': [
            for (var index = 0; index < 6; index++)
              {
                'id': index + 7000,
                'name': const [
                  'A quiet forest',
                  'Beyond the horizon',
                  'The city after rain',
                  'A new beginning',
                  'Stories from the coast',
                  'Under the evening sky',
                ][index],
                'author': 'Layout fixture',
                'description': '',
                'image': '',
                'category': {'title': 'Adventure'},
                'category_sub': {'title': 'Illustration'},
              },
          ],
        };
        break;
      case 'last_search_histories':
        response = [
          {'search_query': 'quiet forest', 'last_search_time': 1770000000},
        ];
        break;
      case 'jm_3x4_cover':
        final id = int.parse(params as String);
        final path = coverPaths[id];
        if (path == null) return _pendingCover.future;
        response = path;
        break;
      default:
        throw StateError('Unexpected method: $method');
    }
    return jsonEncode({
      'error_message': '',
      'response_data': response is String ? response : jsonEncode(response),
    });
  }

  Future<void> createPreviewCovers() async {
    final directory = Directory('build/layout-validation/fixture-images');
    await directory.create(recursive: true);
    for (var index = 0; index < 6; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final base = Colors.primaries[index * 2 + 1];
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 240, 320), Paint()..color = base.shade200);
      canvas.drawCircle(const Offset(177, 72), 35,
          Paint()..color = Colors.white.withValues(alpha: .72));
      final hills = Path()
        ..moveTo(0, 215)
        ..quadraticBezierTo(80, 95, 170, 235)
        ..quadraticBezierTo(215, 140, 240, 185)
        ..lineTo(240, 320)
        ..lineTo(0, 320)
        ..close();
      canvas.drawPath(hills, Paint()..color = base.shade700);
      canvas.drawRect(const Rect.fromLTWH(20, 282, 118, 4),
          Paint()..color = Colors.white.withValues(alpha: .7));
      final picture = recorder.endRecording();
      final bitmap = await picture.toImage(240, 320);
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/cover_$index.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      coverPaths[index + 7000] = file.absolute.path;
      bitmap.dispose();
      picture.dispose();
    }
  }
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _saveScreenshots
          ? lightTheme.copyWith(
              textTheme:
                  lightTheme.textTheme.apply(fontFamily: 'LayoutPreview'),
              primaryTextTheme: lightTheme.primaryTextTheme
                  .apply(fontFamily: 'LayoutPreview'),
            )
          : lightTheme,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: _previewKey, child: child!),
      ),
      home: child,
    );

Future<_Fixture> _prepare(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool guest = true,
}) async {
  final fixture = _Fixture();
  fixture.properties['guest_mode'] = '$guest';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, fixture.handle);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    messenger.setMockMethodCallHandler(_channel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // Clear response caches through the same public path as ending a session.
  await native.methods.logout();
  clearAllImageMemoryCaches();
  if (!_versionInitialized) {
    await initVersion();
    _versionInitialized = true;
  }
  await initCategoriesSort();
  await initPagerControllerMode();
  await initPagerViewMode();
  await initPagerCoverRate();
  await initPagerColumnCount();
  if (_saveScreenshots) {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        final bytes = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['LayoutPreview', 'Roboto']) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
      }
      final config = jsonDecode(
          await File('.dart_tool/package_config.json').readAsString()) as Map;
      final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
      final icons = File(
          '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(await icons.readAsBytes()))))
            .load();
      }
      await fixture.createPreviewCovers();
    });
  }
  await tester.pumpWidget(_host(const Scaffold(
    body: SizedBox(key: ValueKey('login-context')),
  )));
  await login_config.initLogin(
    tester.element(find.byKey(const ValueKey('login-context'))),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Finder _chip(String title) => find.widgetWithText(ChoiceChip, title);

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    // Let local mock cover I/O finish before recording the actual widget tree.
    for (var frame = 0; frame < 10; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage();
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/layout-validation/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

void main() {
  testWidgets('rail breakpoint preserves active page and category state',
      (tester) async {
    final fixture = await _prepare(tester, size: const Size(839, 700));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.tap(find.widgetWithText(Tab, 'Beta'));
    await tester.pumpAndSettle();
    final browserState = tester.state(find.byType(BrowserScreen));
    expect(fixture.calls('comics').last['params'],
        jsonEncode({'categories_slug': 'beta', 'sort_by': '', 'page': 1}));
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.image_outlined),
    ));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    final libraryState = tester.state(find.byType(UserScreen));

    for (final width in [840.0, 1440.0, 839.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpAndSettle();
      if (width >= 840) {
        expect(find.byType(NavigationBar), findsNothing);
        expect(
            tester
                .widget<NavigationRail>(find.byType(NavigationRail))
                .selectedIndex,
            1);
      } else {
        expect(find.byType(NavigationRail), findsNothing);
        expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1);
      }
      expect(tester.state(find.byType(UserScreen)), same(libraryState));
      expect(tester.state(find.byType(BrowserScreen, skipOffstage: false)),
          same(browserState));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.menu_book_outlined),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    expect(tester.state(find.byType(BrowserScreen)), same(browserState));
    expect(fixture.calls('categories'), hasLength(1));
  });

  testWidgets('category sort and reorder retain the selected slug',
      (tester) async {
    final fixture = await _prepare(tester);
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    await tester.tap(_chip('Beta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();
    expect(fixture.calls('comics').last['params'],
        jsonEncode({'categories_slug': 'beta', 'sort_by': 'mr', 'page': 1}));

    await saveCategoriesSort([2, 1, 3]);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(_chip('Beta')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(_chip('Alpha')).selected, isFalse);
    expect(tester.getTopLeft(_chip('Beta')).dx,
        lessThan(tester.getTopLeft(_chip('Alpha')).dx));
    await tester.tap(_chip('Alpha'));
    await tester.pumpAndSettle();
    expect(fixture.calls('comics').last['params'],
        jsonEncode({'categories_slug': 'alpha', 'sort_by': 'mr', 'page': 1}));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'browse-desktop');
  });

  testWidgets('visible search loads history and opens a query result',
      (tester) async {
    final fixture = await _prepare(tester);
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    expect(find.text(_searchHint), findsOneWidget);
    await tester.tap(find.text(_searchHint));
    await tester.pumpAndSettle();
    expect(fixture.calls('last_search_histories').single['params'], '20');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('quiet forest'), findsOneWidget);
    await _capture(tester, 'search-desktop');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(_searchHint));
    await tester.pumpAndSettle();
    await tester.tap(find.text('quiet forest'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicSearchScreen), findsOneWidget);
    expect(fixture.calls('comic_search').single['params'],
        jsonEncode({'search_query': 'quiet forest', 'sort_by': '', 'page': 1}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile search tags do not add a second keyboard inset',
      (tester) async {
    await _prepare(tester, size: const Size(320, 640));
    await tester.pumpWidget(_host(const AppScreen(), textScale: 1.4));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    final history = find.text('quiet forest');
    expect(history, findsOneWidget);
    expect(tester.getRect(history).right, lessThanOrEqualTo(308));

    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final panel = tester.widget<ListView>(find.ancestor(
      of: history,
      matching: find.byType(ListView),
    ));
    expect(panel.padding, const EdgeInsets.all(10));
    expect(tester.getRect(history).right, lessThanOrEqualTo(308));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact browse and guest library fit large text',
      (tester) async {
    await _prepare(tester, size: const Size(320, 780));
    await tester.pumpWidget(_host(const AppScreen(), textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text(_searchHint), findsNothing);
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    final grid = tester.widget<GridView>(find.byType(GridView).first);
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, 'browse-compact-large-text');
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(Icons.image_outlined),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Guest Mode'), findsOneWidget);
    final user = find.byType(UserScreen);
    final scroll = find.descendant(
      of: user,
      matching: find.byType(SingleChildScrollView),
    );
    expect(
        tester.getRect(find.text('Guest Mode')).right, lessThanOrEqualTo(284));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-compact-large-text');
    await tester.drag(scroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Download List').hitTestable(), findsOneWidget);
    expect(find.text('Comments').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out library stays usable at 320px and desktop',
      (tester) async {
    await _prepare(tester, size: const Size(320, 780), guest: false);
    await tester.pumpWidget(_host(const UserScreen(), textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Login / Register'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-signed-out-compact-large-text');
    await tester.pumpWidget(_host(const UserScreen()));
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();
    final account = tester.getRect(find.text('Account'));
    final library = tester.getRect(find.text('Library'));
    expect(account.right, lessThan(library.left));
    final view = find.descendant(
      of: find.byType(UserScreen),
      matching: find.byWidgetPredicate((widget) =>
          widget is ConstrainedBox && widget.constraints.maxWidth == 1120),
    );
    expect(tester.getSize(view).width, 1120);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-desktop');
  });

  for (final columns in [3, 4]) {
    testWidgets('phone browse restores compact tabs and $columns saved columns',
        (tester) async {
      final fixture = await _prepare(tester, size: const Size(390, 780));
      fixture.properties['pager_column_number'] = '$columns';
      await initPagerColumnCount();
      await tester.pumpWidget(_host(const AppScreen()));
      await tester.pumpAndSettle();

      expect(find.text(_searchHint), findsNothing);
      final gridFinder = find.byType(GridView).first;
      final grid = tester.widget<GridView>(gridFinder);
      final delegate =
          grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, columns);
      expect(delegate.mainAxisSpacing, 0);
      expect(delegate.crossAxisSpacing, 0);
      expect(grid.padding, const EdgeInsets.all(10));
      expect(
        tester.getTopLeft(find.byType(ComicPager).first).dy -
            tester.getTopLeft(find.byType(BrowserScreen)).dy,
        lessThanOrEqualTo(kToolbarHeight + 56),
      );
      await tester.tap(find.widgetWithText(Tab, 'Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Newest'));
      await tester.pumpAndSettle();
      await saveCategoriesSort([2, 1, 3]);
      await tester.pumpAndSettle();
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.controller!.index, 0);
      expect((tabs.tabs.first as Tab).text, 'Beta');
      expect(fixture.calls('comics').last['params'],
          jsonEncode({'categories_slug': 'beta', 'sort_by': 'mr', 'page': 1}));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'browse-mobile-restored-$columns-columns');
    });
  }

  testWidgets('phone search restores small text-only tags and full labels',
      (tester) async {
    final fixture = await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    const longTag =
        'A long category label stays complete and wraps instead of being truncated';
    blockStore = [
      Block(title: 'Topics', content: ['Adventure', 'Nature', longTag]),
    ];
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history_rounded), findsNothing);
    expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
    expect(tester.widget<Text>(find.text(longTag)).maxLines, isNull);
    final history = find
        .ancestor(
          of: find.text('quiet forest'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.getSize(history).height, lessThan(40));
    expect(tester.getRect(find.text(longTag)).right, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'search-mobile-restored');
    await tester.tap(find.text('Nature'));
    await tester.pumpAndSettle();
    expect(find.byType(ComicSearchScreen), findsOneWidget);
    expect(fixture.calls('comic_search').single['params'],
        jsonEncode({'search_query': 'Nature', 'sort_by': '', 'page': 1}));
  });
}

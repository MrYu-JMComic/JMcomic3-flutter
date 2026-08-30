import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/comic_reader_screen.dart';

ComicBasic _comic() => ComicBasic(
      id: 1,
      author: 'author',
      description: '',
      name: 'Test comic',
      image: '',
    );

ChapterResponse _chapter({List<String> images = const []}) => ChapterResponse(
      id: 10,
      series: [Series(id: 10, name: 'Chapter', sort: '1')],
      tags: '',
      name: 'Chapter',
      images: images,
      seriesId: 10,
      isFavorite: false,
      liked: false,
    );

Widget _reader(Future<ChapterResponse> Function(int) loader, {int initRank = 0}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: ComicReaderScreen(
      comic: _comic(),
      series: const [],
      chapterId: 10,
      initRank: initRank,
      loadChapter: loader,
    ),
  );
}

void main() {
  testWidgets('Basic widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('JMcomic'),
        ),
      ),
    );

    expect(find.text('JMcomic'), findsOneWidget);
  });

  testWidgets('empty chapter renders a retry placeholder', (tester) async {
    await tester.pumpWidget(_reader((_) async => _chapter()));
    await tester.pumpAndSettle();

    expect(find.text('No content available'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('chapter loader errors render content error state', (tester) async {
    await tester.pumpWidget(_reader((_) async => throw StateError('offline')));
    await tester.pumpAndSettle();

    expect(find.byType(ComicReaderScreen), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });

  testWidgets('initial rank outside chapter bounds does not crash reader', (tester) async {
    await tester.pumpWidget(_reader((_) async => _chapter(images: const ['https://example.invalid/page.jpg']), initRank: 99));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}

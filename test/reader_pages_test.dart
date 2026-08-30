import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/reader_pages.dart';

void main() {
  test('online pages preserve order and mark empty/duplicate names', () {
    final pages = ReaderPageRepository.fromOnline(['a.jpg', '', 'a.jpg']);
    expect(pages.map((p) => p.position), [0, 1, 2]);
    expect(pages[1].hasName, isFalse);
    expect(pages[2].isDuplicateName, isTrue);
    expect(pages[0].isUsable, isTrue);
    expect(pages[2].isUsable, isTrue);
  });

  test('offline pages retain dimensions and key', () {
    final pages = ReaderPageRepository.fromOffline([
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 0,
        name: 'p.webp',
        key: 'k',
        dlStatus: 1,
        width: 100,
        height: 200,
      ),
    ]);
    expect(pages.single.width, 100);
    expect(pages.single.height, 200);
    expect(pages.single.key, 'k');
  });
}

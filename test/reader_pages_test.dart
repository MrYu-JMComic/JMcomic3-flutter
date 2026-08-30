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
    // Duplicate names remain readable; position/key is the stable identity.
    expect(pages[2].isUsable, isTrue);
  });

  test('offline pages retain dimensions and key', () {
    final pages = ReaderPageRepository.fromOffline([
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 2,
        name: 'p2.webp',
        key: 'k2',
        dlStatus: 1,
        width: 100,
        height: 200,
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 0,
        name: 'p0.webp',
        key: 'k0',
        dlStatus: 1,
        width: 10,
        height: 20,
      ),
    ]);
    expect(pages.map((p) => p.position), [0, 1]);
    expect(pages.map((p) => p.sourceIndex), [0, 2]);
    expect(pages.last.width, 100);
    expect(pages.last.height, 200);
    expect(pages.last.key, 'k2');
  });

  test('offline sparse or duplicate source indices keep ordinal positions', () {
    final pages = ReaderPageRepository.fromOffline([
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 5,
        name: 'p5.jpg',
        key: 'k5',
        dlStatus: 1,
        width: 50,
        height: 50,
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 1,
        name: 'p1.jpg',
        key: 'k1',
        dlStatus: 1,
        width: 10,
        height: 10,
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 1,
        name: 'p1b.jpg',
        key: 'k1b',
        dlStatus: 1,
        width: 11,
        height: 11,
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: -1,
        name: 'unknown.jpg',
        key: 'ku',
        dlStatus: 1,
        width: 12,
        height: 12,
      ),
    ]);
    expect(pages.map((p) => p.position), [0, 1, 2, 3]);
    expect(pages.map((p) => p.sourceIndex), [1, 1, 5, -1]);
    expect(pages.map((p) => p.name),
        ['p1.jpg', 'p1b.jpg', 'p5.jpg', 'unknown.jpg']);
  });

  test('local path availability is explicit', () {
    const page = PageDescriptor(position: 0, name: '1.jpg');
    expect(page.localPath, isNull);
    expect(page.localAvailable, isFalse);
    final resolved = page.copyWith(
      localPath: 'C:/cache/1.jpg',
      localAvailable: true,
    );
    expect(resolved.localPath, 'C:/cache/1.jpg');
    expect(resolved.localAvailable, isTrue);
  });

  test('offline empty local path is metadata-only even when flagged available',
      () {
    final pages = ReaderPageRepository.fromOffline([
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 0,
        name: '1.jpg',
        key: 'k1',
        dlStatus: 1,
        width: 10,
        height: 10,
        localPath: '   ',
        localAvailable: true,
      ),
    ]);
    expect(pages.single.localAvailable, isFalse);
  });

  test('duplicate names remain distinct by source position', () {
    final pages = ReaderPageRepository.fromOnline(['same.jpg', 'same.jpg']);
    expect(pages.map((p) => p.position), [0, 1]);
    expect(pages.first.isDuplicateName, isFalse);
    expect(pages.last.isDuplicateName, isTrue);
  });

  test(
      'availability probe clears stale paths and matches duplicate tuples FIFO',
      () {
    final base = [
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 3,
        name: 'same.jpg',
        key: 'first',
        dlStatus: 1,
        width: 10,
        height: 10,
        localPath: 'C:/stale/first.jpg',
        localAvailable: true,
        localState: 'available',
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 3,
        name: 'same.jpg',
        key: 'second',
        dlStatus: 1,
        width: 10,
        height: 10,
        localPath: 'C:/stale/second.jpg',
        localAvailable: true,
        localState: 'available',
      ),
    ];
    final probe = [
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 3,
        name: 'same.jpg',
        key: 'probe-1',
        dlStatus: 1,
        width: 10,
        height: 10,
        localPath: 'C:/offline/first.jpg',
        localAvailable: true,
        localState: 'available',
      ),
      DlImage(
        albumId: 1,
        chapterId: 2,
        imageIndex: 3,
        name: 'same.jpg',
        key: 'probe-2',
        dlStatus: 1,
        width: 10,
        height: 10,
        localAvailable: false,
        localState: 'missing',
      ),
    ];

    final merged = ReaderPageRepository.mergeLocalAvailability(base, probe);
    expect(merged[0].localPath, 'C:/offline/first.jpg');
    expect(merged[0].localAvailable, isTrue);
    expect(merged[1].localPath, isNull);
    expect(merged[1].localAvailable, isFalse);
    expect(merged[1].localState, 'missing');
  });

  test('empty availability response preserves compatibility metadata', () {
    final base = DlImage(
      albumId: 1,
      chapterId: 2,
      imageIndex: 0,
      name: 'page.jpg',
      key: 'k',
      dlStatus: 1,
      width: 1,
      height: 1,
      localPath: 'C:/known/page.jpg',
      localAvailable: true,
      localState: 'available',
    );
    final merged = ReaderPageRepository.mergeLocalAvailability([base], []);
    expect(merged.single.localPath, base.localPath);
    expect(merged.single.localAvailable, isTrue);
  });
}

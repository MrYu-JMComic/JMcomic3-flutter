import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decode target is bounded to stable buckets', () {
    expect(decodeTargetExtentForTest(100, 1), 256);
    expect(decodeTargetExtentForTest(500, 1), 512);
    expect(decodeTargetExtentForTest(900, 2), 2048);
    expect(decodeTargetExtentForTest(null, 2), isNull);
    expect(decodeTargetExtentForTest(0, 2), isNull);
    expect(decodeTargetExtentForTest(10000, 4), 4096);
    expect(decodeTargetExtentForTest(double.infinity, 1), isNull);
    expect(decodeTargetExtentForTest(100, double.nan), isNull);
  });

  test('page provider key includes bounded codec targets', () {
    final small = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 100,
      height: 200,
    );
    final same = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 101,
      height: 201,
    );
    final different = readerPageImageProviderForTest(
      id: 1,
      imageName: 'page.jpg',
      width: 500,
      height: 200,
    );

    expect(small.cacheWidth, 256);
    // Width/height bounds are fit targets; both dimensions are never passed
    // as an exact codec pair, avoiding aspect-ratio distortion.
    expect(small.cacheHeight, 256);
    expect(small, same);
    expect(small, isNot(different));
    expect(small.hashCode, same.hashCode);
  });

  test('reader target uses stable fit buckets without exact distortion', () {
    final bounded = readerPageImageProviderForTest(
      id: 9,
      imageName: 'portrait.jpg',
      width: 300,
      height: 400,
    );
    // Cache keys remain bucketed and deterministic. The codec callback
    // computes the aspect-preserving fit dimensions from these bounds.
    expect(bounded.cacheWidth, 512);
    expect(bounded.cacheHeight, 512);
  });

  test('duplicate source pages keep distinct provider identities', () {
    final first = readerPageImageProviderForTest(
      id: 1,
      imageName: 'same.jpg',
      pageIndex: 0,
      width: 400,
    );
    final second = readerPageImageProviderForTest(
      id: 1,
      imageName: 'same.jpg',
      pageIndex: 1,
      width: 400,
    );

    expect(first, isNot(second));
    expect(first.hashCode, isNot(second.hashCode));
  });

  test(
    'local-only provider rejects missing availability without bridge call',
    () async {
      final provider = readerPageImageProviderForTest(
        id: 1,
        imageName: 'missing.jpg',
        localOnly: true,
      );

      await expectLater(
        provider.loadCodecForTest(),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('local-only provider treats blank local path as unavailable', () async {
    final provider = readerPageImageProviderForTest(
      id: 2,
      imageName: 'blank.jpg',
      localPath: '   ',
      localOnly: true,
    );

    expect(provider.localPath, isNull);
    await expectLater(provider.loadCodecForTest(), throwsA(isA<StateError>()));
  });
}

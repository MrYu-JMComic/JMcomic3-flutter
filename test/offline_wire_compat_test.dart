import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';

void main() {
  test('legacy DlImage JSON defaults local availability safely', () {
    final image = DlImage.fromJson({
      'album_id': 1,
      'chapter_id': 2,
      'image_index': 0,
      'name': 'a.jpg',
      'key': 'k',
      'dl_status': 1,
      'width': 10,
      'height': 20
    });
    expect(image.localPath, isNull);
    expect(image.localAvailable, isFalse);
    expect(image.localState, isNull);
  });

  test('explicit local wire fields round-trip without inferring paths', () {
    final image = DlImage.fromJson({
      'album_id': 1,
      'chapter_id': 2,
      'image_index': 0,
      'name': 'a.jpg',
      'key': 'k',
      'dl_status': 1,
      'width': 10,
      'height': 20,
      'local_path': ' C:/cache/a.jpg ',
      'local_available': true,
      'local_state': 'available'
    });
    expect(image.localPath, 'C:/cache/a.jpg');
    expect(image.localAvailable, isTrue);
    expect(image.toJson()['local_path'], 'C:/cache/a.jpg');
  });
}

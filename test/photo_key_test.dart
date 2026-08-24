import 'package:flutter_test/flutter_test.dart';

import 'package:photo_application/core/utils/photo_key.dart';

void main() {
  group('derivePhotoKey', () {
    String key({
      String fileName = 'IMG_0001.jpg',
      int createdMs = 1700000000000,
      int width = 4032,
      int height = 3024,
    }) =>
        derivePhotoKey(
          fileName: fileName,
          createdMs: createdMs,
          width: width,
          height: height,
        );

    test('같은 사진이면 항상 같은 키가 나온다', () {
      expect(key(), key());
    });

    test('sha1 16진수 40자다', () {
      expect(key(), matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('파일명의 대소문자와 앞뒤 공백은 무시한다', () {
      // 기기·전송 경로에 따라 확장자 대소문자가 바뀌는 일이 흔한데,
      // 그때마다 메모가 끊기면 안 된다.
      expect(key(fileName: 'IMG_0001.JPG'), key(fileName: 'img_0001.jpg'));
      expect(key(fileName: '  IMG_0001.jpg  '), key());
    });

    test('파일명·촬영시각·해상도가 다르면 키가 달라진다', () {
      expect(key(fileName: 'IMG_0002.jpg'), isNot(key()));
      expect(key(createdMs: 1700000000001), isNot(key()));
      expect(key(width: 4033), isNot(key()));
      expect(key(height: 3025), isNot(key()));
    });

    test('가로세로가 뒤바뀐 사진은 다른 키다', () {
      expect(key(width: 3024, height: 4032), isNot(key()));
    });
  });
}

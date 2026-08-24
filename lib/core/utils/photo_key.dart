import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 사진의 **기기 간 안정 식별키**를 만듭니다.
///
/// 왜 MediaStore 의 asset id 를 그대로 쓰지 않는가:
/// asset id 는 기기 내부의 행 번호라서 기기를 바꾸거나, 사진을 SD 카드로
/// 옮기거나, OS 가 미디어 DB 를 재구축하면 값이 달라집니다. 그 위에 메모를
/// 매달아 두면 어느 순간 메모가 통째로 미아가 됩니다.
///
/// 그래서 파일 자체의 성질에서 키를 유도합니다:
///   파일명 + 촬영시각(ms) + 가로x세로
///
/// 파일 내용 해시를 쓰지 않는 이유는 비용입니다. 수만 장의 원본을 전부 읽으면
/// 최초 스캔이 수 분 단위로 늘어납니다. 위 세 값은 MediaStore 가 이미 들고
/// 있어서 파일 I/O 없이 즉시 얻을 수 있습니다.
///
/// 알려진 트레이드오프: 완전히 동일한 사진의 **복사본**(같은 파일명·시각·해상도)은
/// 같은 키를 갖습니다. 즉 복사본끼리 메모와 태그를 공유합니다. 갤러리에는 둘 다
/// 정상적으로 표시되며(사진 목록은 asset id 기준), 동일 사진이라는 점에서
/// 메타데이터 공유는 대체로 바람직한 동작이라 의도적으로 허용했습니다.
String derivePhotoKey({
  required String fileName,
  required int createdMs,
  required int width,
  required int height,
}) {
  final basis = [
    fileName.trim().toLowerCase(),
    createdMs.toString(),
    '${width}x$height',
  ].join('|');
  return sha1.convert(utf8.encode(basis)).toString();
}

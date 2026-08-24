import 'package:photo_manager/photo_manager.dart';

/// 갤러리 사진 한 장 — `photos` 테이블의 한 행.
class PhotoItem {
  const PhotoItem({
    required this.assetId,
    required this.photoKey,
    required this.fileName,
    required this.createdMs,
    required this.width,
    required this.height,
  });

  /// MediaStore 행 번호. 기기 내부에서만 유효합니다.
  final String assetId;

  /// 메모·태그·폴더가 매달리는 기기 간 안정 키.
  final String photoKey;

  final String fileName;
  final int createdMs;
  final int width;
  final int height;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdMs);

  /// photo_manager 용 엔티티를 **동기적으로** 만들어 냅니다.
  ///
  /// `AssetEntity.fromId` 는 비동기라 그리드 타일마다 FutureBuilder 가 붙어
  /// 스크롤이 끊깁니다. 썸네일을 그리는 데 실제로 필요한 값(id·해상도)은
  /// 이미 DB 에 있으므로 직접 생성해 그 왕복을 없앱니다.
  AssetEntity toEntity() => AssetEntity(
        id: assetId,
        typeInt: AssetType.image.index,
        width: width,
        height: height,
        title: fileName,
        createDateSecond: createdMs ~/ 1000,
      );

  factory PhotoItem.fromRow(Map<String, Object?> row) => PhotoItem(
        assetId: row['asset_id'] as String,
        photoKey: row['photo_key'] as String,
        fileName: (row['file_name'] as String?) ?? '',
        createdMs: (row['created_ms'] as int?) ?? 0,
        width: (row['width'] as int?) ?? 0,
        height: (row['height'] as int?) ?? 0,
      );
}

/// 사용자가 만든 **가상 폴더**.
///
/// 기기의 실제 사진 폴더(DCIM/Camera 등)와는 완전히 별개입니다. 사진 파일을
/// 옮기거나 복사하지 않고, "이 사진은 이 폴더에 속한다"는 관계만 앱이 기억합니다.
/// 그래서 폴더를 아무리 만들어도 기기 저장 공간은 늘지 않고, 폴더를 지워도
/// 사진은 사라지지 않습니다.
class PhotoFolder {
  const PhotoFolder({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.photoCount = 0,
  });

  final String id;
  final String name;
  final int sortOrder;

  /// 이 폴더에 들어 있는 (기기에 실제로 존재하는) 사진 수.
  final int photoCount;

  factory PhotoFolder.fromRow(Map<String, Object?> row) => PhotoFolder(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        sortOrder: (row['sort_order'] as int?) ?? 0,
        photoCount: (row['photo_count'] as int?) ?? 0,
      );
}

/// 사용자가 만든 태그.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.photoCount = 0,
  });

  final String id;
  final String name;

  /// 이 태그가 달린 (기기에 실제로 존재하는) 사진 수.
  final int photoCount;

  factory Tag.fromRow(Map<String, Object?> row) => Tag(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        photoCount: (row['photo_count'] as int?) ?? 0,
      );
}

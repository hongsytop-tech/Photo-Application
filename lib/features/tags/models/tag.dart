/// 사용자가 만든 태그.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.groupId = '',
    this.photoCount = 0,
  });

  final String id;
  final String name;

  /// 이 태그가 속한 분류. 빈 문자열이면 미분류입니다.
  final String groupId;

  /// 이 태그가 달린 (기기에 실제로 존재하는) 사진 수.
  final int photoCount;

  factory Tag.fromRow(Map<String, Object?> row) => Tag(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        groupId: (row['group_id'] as String?) ?? '',
        photoCount: (row['photo_count'] as int?) ?? 0,
      );
}

/// 태그를 묶는 분류.
///
/// 폴더가 사진을 담는다면 분류는 **태그**를 담습니다. 태그가 수십 개로
/// 늘어나면 한 줄 목록에서 원하는 것을 찾기 어려워지므로, 그 위에 서랍을
/// 하나 둡니다. 어느 분류에도 넣지 않은 태그는 "미분류"로 모입니다.
class TagGroup {
  const TagGroup({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.tagCount = 0,
  });

  /// 미분류를 가리키는 값. 태그의 `group_id` 가 빈 문자열이면 어느 분류에도
  /// 속하지 않았다는 뜻입니다.
  static const none = '';

  final String id;
  final String name;
  final int sortOrder;

  /// 이 분류에 들어 있는 태그 수.
  final int tagCount;

  factory TagGroup.fromRow(Map<String, Object?> row) => TagGroup(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        sortOrder: (row['sort_order'] as int?) ?? 0,
        tagCount: (row['tag_count'] as int?) ?? 0,
      );
}

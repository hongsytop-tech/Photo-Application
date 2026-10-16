/// 사용자가 만든 **가상 폴더**.
///
/// 기기의 실제 사진 폴더(DCIM/Camera 등)와는 완전히 별개입니다. 사진 파일을
/// 옮기거나 복사하지 않고, "이 사진은 이 폴더에 속한다"는 관계만 앱이 기억합니다.
/// 그래서 폴더를 아무리 만들어도 기기 저장 공간은 늘지 않고, 폴더를 지워도
/// 사진은 사라지지 않습니다.
///
/// 폴더는 폴더를 품을 수 있습니다 ([parentId]). 뿌리 폴더는 parentId 가
/// 빈 문자열입니다 — null 이 아니라 '' 인 이유는 동기화에서 "값이 없음"과
/// "뿌리"를 구분해야 하기 때문입니다.
class PhotoFolder {
  const PhotoFolder({
    required this.id,
    required this.name,
    this.parentId = '',
    this.sortOrder = 0,
    this.photoCount = 0,
    this.subfolderCount = 0,
  });

  final String id;
  final String name;

  /// 품고 있는 폴더의 id. 뿌리면 ''.
  final String parentId;

  final int sortOrder;

  /// 이 폴더에 **직접** 들어 있는 (기기에 실제로 존재하는) 사진 수.
  /// 하위 폴더의 사진은 세지 않습니다.
  final int photoCount;

  /// 바로 아래 하위 폴더 수.
  final int subfolderCount;

  bool get isRoot => parentId.isEmpty;

  factory PhotoFolder.fromRow(Map<String, Object?> row) => PhotoFolder(
        id: row['id'] as String,
        name: (row['name'] as String?) ?? '',
        parentId: (row['parent_id'] as String?) ?? '',
        sortOrder: (row['sort_order'] as int?) ?? 0,
        photoCount: (row['photo_count'] as int?) ?? 0,
        subfolderCount: (row['subfolder_count'] as int?) ?? 0,
      );
}

/// 트리를 화면에 뿌리기 좋게 펼친 한 줄.
class FolderNode {
  const FolderNode({required this.folder, required this.depth});

  final PhotoFolder folder;

  /// 뿌리는 0, 그 아래는 1, …
  final int depth;

  bool get hasChildren => folder.subfolderCount > 0;
}

/// 평평한 폴더 목록을 트리 순서(부모 바로 다음에 그 자식들)로 펼칩니다.
///
/// [expanded] 에 든 폴더의 자식만 따라 내려갑니다. null 을 주면 전부 펼칩니다
/// (폴더 고르기 시트처럼 한눈에 다 보여줘야 하는 곳).
///
/// 부모가 사라진 폴더와 **고리(cycle)를 이룬 폴더는 뿌리로 올려** 반드시
/// 한 번은 나오게 합니다. 고리는 두 기기가 서로 모르는 채 X 를 Y 아래로,
/// Y 를 X 아래로 옮긴 뒤 동기화되면 실제로 만들어질 수 있습니다. 그때
/// 그 폴더들이 화면에서 사라지면 사용자는 폴더를 잃은 것처럼 느끼고,
/// 되돌릴 방법도 없습니다.
List<FolderNode> buildFolderTree(
  List<PhotoFolder> folders, {
  Set<String>? expanded,
}) {
  final byParent = <String, List<PhotoFolder>>{};
  final ids = folders.map((f) => f.id).toSet();

  for (final folder in folders) {
    final parent = _effectiveParent(folder, folders, ids);
    (byParent[parent] ??= []).add(folder);
  }

  final out = <FolderNode>[];

  void walk(String parentId, int depth) {
    for (final folder in byParent[parentId] ?? const <PhotoFolder>[]) {
      out.add(FolderNode(folder: folder, depth: depth));
      if (expanded == null || expanded.contains(folder.id)) {
        walk(folder.id, depth + 1);
      }
    }
  }

  walk('', 0);
  return out;
}

/// 실제로 매달 부모. 부모가 없거나 고리에 걸리면 뿌리('')로 봅니다.
String _effectiveParent(
  PhotoFolder folder,
  List<PhotoFolder> folders,
  Set<String> ids,
) {
  if (folder.parentId.isEmpty) return '';
  if (!ids.contains(folder.parentId)) return '';

  // 조상을 거슬러 올라가며 자기 자신을 다시 만나면 고리입니다.
  final parents = {for (final f in folders) f.id: f.parentId};
  final seen = <String>{folder.id};
  var cursor = folder.parentId;
  while (cursor.isNotEmpty) {
    if (!seen.add(cursor)) return '';
    cursor = parents[cursor] ?? '';
  }
  return folder.parentId;
}

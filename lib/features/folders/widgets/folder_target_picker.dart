import 'package:flutter/material.dart';

import 'package:photo_application/features/folders/models/photo_folder.dart';

/// 폴더를 옮겨 넣을 곳을 고르는 창.
///
/// 돌려주는 값: null 이면 취소, 빈 문자열이면 "뿌리로 올리기", 그 밖에는
/// 그 폴더의 id.
///
/// [excludeIds] 에는 옮길 폴더 자신과 그 하위 폴더를 넣습니다. 자기 안으로
/// 들어가면 그 가지가 트리에서 떨어져 나가 화면에 영원히 나오지 않습니다.
/// 아예 목록에 띄우지 않아, 고를 수 없는 것을 눌러 보고 아무 일도 안 일어나는
/// 상황을 만들지 않습니다.
Future<String?> showFolderTargetPicker(
  BuildContext context, {
  required String title,
  required List<PhotoFolder> folders,
  required Set<String> excludeIds,
  String rootLabel = '뿌리로 올리기',
}) {
  final nodes = buildFolderTree(folders)
      .where((n) => !excludeIds.contains(n.folder.id))
      .toList();

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SizedBox(
        width: 320,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.north_outlined),
              title: Text(rootLabel),
              onTap: () => Navigator.of(context).pop(''),
            ),
            if (nodes.isNotEmpty) const Divider(height: 1),
            for (final node in nodes)
              ListTile(
                contentPadding: EdgeInsets.only(
                  left: 16 + node.depth * 16.0,
                  right: 16,
                ),
                leading: Icon(
                  node.hasChildren
                      ? Icons.folder_copy_outlined
                      : Icons.folder_outlined,
                ),
                title: Text(node.folder.name),
                onTap: () => Navigator.of(context).pop(node.folder.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ],
    ),
  );
}

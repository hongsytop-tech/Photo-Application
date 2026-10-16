import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';

/// 폴더 하나의 속을 보여 줍니다 — 하위 폴더 줄 + 그 폴더에 **직접** 든 사진.
///
/// 하위 폴더의 사진은 섞어 보여 주지 않습니다. 섞으면 "이 폴더에 몇 장이
/// 있나"와 "여기서 고른 사진을 어디서 빼야 하나"가 둘 다 흐려집니다.
/// 하위 폴더는 위쪽 줄에서 눌러 들어갑니다.
class FolderDetailScreen extends ConsumerWidget {
  const FolderDetailScreen({
    super.key,
    required this.folderId,
    required this.name,
  });

  final String folderId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhotoBrowserScreen(
      title: name,
      query: PhotoQuery(scope: PhotoScope.folder, folderId: folderId),
      header: _SubfolderStrip(parentId: folderId),
      actions: [
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () => _createChild(context, ref),
          tooltip: '하위 폴더 만들기',
        ),
      ],
      emptyMessage: '이 폴더에 넣은 사진이 없습니다.\n\n'
          '사진 탭에서 사진을 고른 뒤 폴더 아이콘을 누르면 '
          '한 번에 넣을 수 있습니다.',
    );
  }

  Future<void> _createChild(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final childName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"$name" 안에 새 폴더'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '이름'),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    if (childName == null || childName.isEmpty) return;

    await ref.read(folderServiceProvider).create(childName, parentId: folderId);
    ref.bumpDataRevision();
  }
}

/// 사진 위에 함께 스크롤되는 하위 폴더 줄. 하위가 없으면 자리를 차지하지
/// 않습니다.
class _SubfolderStrip extends ConsumerWidget {
  const _SubfolderStrip({required this.parentId});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(allFoldersProvider).valueOrNull;
    if (folders == null) return const SizedBox.shrink();

    final children =
        folders.where((f) => f.parentId == parentId).toList(growable: false);
    if (children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '하위 폴더 ${children.length}개',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final folder in children)
                _SubfolderChip(folder: folder),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _SubfolderChip extends StatelessWidget {
  const _SubfolderChip({required this.folder});

  final PhotoFolder folder;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        folder.subfolderCount > 0
            ? Icons.folder_copy_outlined
            : Icons.folder_outlined,
        size: 18,
      ),
      label: Text('${folder.name} (${folder.photoCount})'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FolderDetailScreen(
            folderId: folder.id,
            name: folder.name,
          ),
        ),
      ),
    );
  }
}

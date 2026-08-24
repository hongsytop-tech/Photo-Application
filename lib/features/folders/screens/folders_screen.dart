import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';

/// "폴더" 탭 — 내가 만든 가상 폴더들.
///
/// 기기의 실제 사진 폴더와는 별개입니다. 사진을 옮기지 않고 소속만 기억하므로
/// 폴더를 지워도 사진은 사라지지 않고 "미지정"으로 돌아갑니다.
class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  void _openFolder(PhotoFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoBrowserScreen(
          title: folder.name,
          query: PhotoQuery(scope: PhotoScope.folder, folderId: folder.id),
          emptyMessage: '이 폴더에 넣은 사진이 없습니다.\n\n'
              '사진 탭에서 사진을 길게 눌러 여러 장을 고른 뒤 '
              '폴더 아이콘을 누르면 한 번에 넣을 수 있습니다.',
        ),
      ),
    );
  }

  void _openUnassigned() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PhotoBrowserScreen(
          title: '미지정 사진',
          subtitle: '아직 어떤 폴더에도 넣지 않은 사진',
          query: PhotoQuery(scope: PhotoScope.unassigned),
          emptyMessage: '모든 사진이 폴더에 들어가 있습니다.',
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = await _promptName(context, title: '새 폴더');
    if (name == null || name.isEmpty) return;
    await ref.read(folderServiceProvider).create(name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _rename(PhotoFolder folder) async {
    final name = await _promptName(
      context,
      title: '폴더 이름 바꾸기',
      initial: folder.name,
    );
    if (name == null || name.isEmpty) return;
    await ref.read(folderServiceProvider).rename(folder.id, name);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _delete(PhotoFolder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${folder.name}" 폴더를 지울까요?'),
        content: const Text(
          '사진은 지워지지 않습니다. 이 폴더에 있던 사진은 "미지정"으로 돌아갑니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    await ref.read(folderServiceProvider).delete(folder.id);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _reorder(List<PhotoFolder> folders, int from, int to) async {
    final ordered = [...folders];
    final moved = ordered.removeAt(from);
    ordered.insert(from < to ? to - 1 : to, moved);
    await ref
        .read(folderServiceProvider)
        .reorder(ordered.map((f) => f.id).toList());
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(allFoldersProvider);
    final unassignedAsync = ref.watch(unassignedCountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('폴더')),
      floatingActionButton: FloatingActionButton(
        onPressed: _create,
        tooltip: '폴더 만들기',
        child: const Icon(Icons.create_new_folder_outlined),
      ),
      body: foldersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (folders) => Column(
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('미지정 사진'),
              subtitle: Text(
                '사진 ${unassignedAsync.valueOrNull ?? 0}장 · 아직 폴더에 넣지 않음',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openUnassigned,
            ),
            const Divider(height: 1),
            Expanded(
              child: folders.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '아직 만든 폴더가 없습니다.\n\n'
                          '오른쪽 아래 버튼으로 폴더를 만들고,\n'
                          '사진을 길게 눌러 골라 담아 보세요.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: folders.length,
                      onReorder: (from, to) => _reorder(folders, from, to),
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return ListTile(
                          key: ValueKey(folder.id),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text('사진 ${folder.photoCount}장'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'rename') _rename(folder);
                                  if (value == 'delete') _delete(folder);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text('이름 바꾸기'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('지우기'),
                                  ),
                                ],
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _openFolder(folder),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
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
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

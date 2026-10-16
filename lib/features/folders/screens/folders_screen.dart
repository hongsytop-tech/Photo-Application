import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/folders/screens/folder_detail_screen.dart';
import 'package:photo_application/features/folders/services/folder_service.dart';
import 'package:photo_application/features/folders/widgets/folder_target_picker.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_browser_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';

/// "폴더" 탭 — 내가 만든 가상 폴더들, 트리로.
///
/// 기기의 실제 사진 폴더와는 별개입니다. 사진을 옮기지 않고 소속만 기억하므로
/// 폴더를 지워도 사진은 사라지지 않고 "미지정"으로 돌아갑니다.
///
/// 폴더는 폴더를 품을 수 있습니다. 하위가 있는 폴더는 왼쪽 화살표로 펼치고
/// 접습니다. 줄 자체를 누르면 그 폴더의 사진을 봅니다.
class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  /// 펼쳐 둔 폴더들. 화면 상태라 저장하지 않습니다 — 탭을 다시 열면 접힙니다.
  final Set<String> _expanded = {};

  void _openFolder(PhotoFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FolderDetailScreen(folderId: folder.id, name: folder.name),
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

  Future<void> _create({String parentId = '', String? parentName}) async {
    final name = await _promptName(
      context,
      title: parentName == null ? '새 폴더' : '"$parentName" 안에 새 폴더',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(folderServiceProvider).create(name, parentId: parentId);
    if (!mounted) return;
    // 방금 만든 하위 폴더가 접힌 채로 숨어 있으면 만들어진 줄 모릅니다.
    if (parentId.isNotEmpty) setState(() => _expanded.add(parentId));
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

  /// 폴더를 다른 폴더 아래로 옮깁니다.
  Future<void> _moveFolder(PhotoFolder folder, List<PhotoFolder> all) async {
    final service = ref.read(folderServiceProvider);

    // 자기 자신과 하위 폴더는 고를 수 없게 아예 뺍니다.
    final exclude = await service.subtreeIds(folder.id);
    if (!mounted) return;

    final target = await showFolderTargetPicker(
      context,
      title: '"${folder.name}" 을 어디로?',
      folders: all,
      excludeIds: exclude,
    );
    if (target == null || !mounted) return;
    if (target == folder.parentId) return;

    final result = await service.moveFolder(folder.id, target);
    if (!mounted) return;

    if (result == MoveFolderResult.cycle) {
      _say('자기 자신이나 하위 폴더 안으로는 옮길 수 없습니다.');
      return;
    }
    if (target.isNotEmpty) setState(() => _expanded.add(target));
    ref.bumpDataRevision();
  }

  Future<void> _nudge(PhotoFolder folder, {required bool up}) async {
    await ref.read(folderServiceProvider).nudge(folder.id, up: up);
    if (!mounted) return;
    ref.bumpDataRevision();
  }

  Future<void> _delete(PhotoFolder folder) async {
    final hasChildren = folder.subfolderCount > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${folder.name}" 폴더를 지울까요?'),
        content: Text(
          hasChildren
              ? '안에 있는 하위 폴더도 함께 지워집니다.\n\n'
                  '사진은 지워지지 않습니다. 이 폴더와 하위 폴더에 있던 사진은 '
                  '다른 폴더에도 들어 있지 않다면 "미지정"으로 돌아갑니다.'
              : '사진은 지워지지 않습니다. 이 폴더에 있던 사진은 다른 폴더에도 '
                  '들어 있지 않다면 "미지정"으로 돌아갑니다.',
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

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        data: (folders) {
          final nodes = buildFolderTree(folders, expanded: _expanded);

          return Column(
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
                            '사진을 골라 담아 보세요.\n\n'
                            '폴더 안에 또 폴더를 만들 수 있습니다.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: nodes.length,
                        itemBuilder: (context, index) => _FolderRow(
                          node: nodes[index],
                          expanded: _expanded.contains(nodes[index].folder.id),
                          onToggleExpand: () => setState(() {
                            final id = nodes[index].folder.id;
                            if (!_expanded.remove(id)) _expanded.add(id);
                          }),
                          onOpen: () => _openFolder(nodes[index].folder),
                          onAction: (action) {
                            final folder = nodes[index].folder;
                            switch (action) {
                              case _FolderAction.addChild:
                                _create(
                                  parentId: folder.id,
                                  parentName: folder.name,
                                );
                              case _FolderAction.rename:
                                _rename(folder);
                              case _FolderAction.move:
                                _moveFolder(folder, folders);
                              case _FolderAction.up:
                                _nudge(folder, up: true);
                              case _FolderAction.down:
                                _nudge(folder, up: false);
                              case _FolderAction.delete:
                                _delete(folder);
                            }
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _FolderAction { addChild, rename, move, up, down, delete }

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.node,
    required this.expanded,
    required this.onToggleExpand,
    required this.onOpen,
    required this.onAction,
  });

  final FolderNode node;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onOpen;
  final void Function(_FolderAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final folder = node.folder;

    return ListTile(
      key: ValueKey(folder.id),
      contentPadding: EdgeInsets.only(left: 4 + node.depth * 20.0, right: 4),
      leading: SizedBox(
        width: 72,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 하위가 없으면 화살표 자리만 비웁니다. 그래야 이름이 같은
            // 세로선에 맞춰 떨어집니다.
            if (node.hasChildren)
              IconButton(
                icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
                onPressed: onToggleExpand,
                tooltip: expanded ? '접기' : '펼치기',
                visualDensity: VisualDensity.compact,
              )
            else
              const SizedBox(width: 40),
            Icon(
              node.hasChildren
                  ? Icons.folder_copy_outlined
                  : Icons.folder_outlined,
            ),
          ],
        ),
      ),
      title: Text(folder.name),
      subtitle: Text(
        '사진 ${folder.photoCount}장'
        '${folder.subfolderCount > 0 ? ' · 하위 ${folder.subfolderCount}개' : ''}',
      ),
      trailing: PopupMenuButton<_FolderAction>(
        onSelected: onAction,
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _FolderAction.addChild,
            child: Text('하위 폴더 만들기'),
          ),
          PopupMenuItem(value: _FolderAction.rename, child: Text('이름 바꾸기')),
          PopupMenuItem(value: _FolderAction.move, child: Text('다른 폴더로 옮기기')),
          PopupMenuDivider(),
          PopupMenuItem(value: _FolderAction.up, child: Text('위로')),
          PopupMenuItem(value: _FolderAction.down, child: Text('아래로')),
          PopupMenuDivider(),
          PopupMenuItem(value: _FolderAction.delete, child: Text('지우기')),
        ],
      ),
      onTap: onOpen,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';

/// 사진을 어떤 가상 폴더에 넣을지 고르는 바텀시트.
///
/// 사진 한 장이면 현재 소속이 체크되어 있고 체크를 풀면 빼냅니다.
/// 여러 장이면 고른 폴더에 **추가**만 합니다.
class FolderPickerSheet extends ConsumerStatefulWidget {
  const FolderPickerSheet({super.key, required this.photoKeys});

  final List<String> photoKeys;

  static Future<bool?> show(BuildContext context, List<String> photoKeys) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolderPickerSheet(photoKeys: photoKeys),
    );
  }

  @override
  ConsumerState<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<FolderPickerSheet> {
  final _newFolder = TextEditingController();
  Set<String> _checked = {};
  Set<String> _initial = {};
  bool _ready = false;

  bool get _isSingle => widget.photoKeys.length == 1;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _newFolder.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (_isSingle) {
      final ids = await ref
          .read(folderServiceProvider)
          .folderIdsOf(widget.photoKeys.first);
      if (!mounted) return;
      setState(() {
        _initial = ids;
        _checked = {...ids};
        _ready = true;
      });
    } else {
      setState(() => _ready = true);
    }
  }

  Future<void> _createFolder() async {
    final name = _newFolder.text.trim();
    if (name.isEmpty) return;
    final folder = await ref.read(folderServiceProvider).create(name);
    if (!mounted) return;
    _newFolder.clear();
    setState(() => _checked = {..._checked, folder.id});
    ref.bumpDataRevision();
  }

  Future<void> _save() async {
    final service = ref.read(folderServiceProvider);

    if (_isSingle) {
      await service.setFoldersOf(widget.photoKeys.first, _checked);
    } else {
      for (final id in _checked) {
        await service.addMany(id, widget.photoKeys);
      }
    }

    if (!mounted) return;
    ref.bumpDataRevision();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(allFoldersProvider);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Text(
              _isSingle
                  ? '폴더 지정'
                  : '폴더에 넣기 — 사진 ${widget.photoKeys.length}장',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                _isSingle
                    ? '체크를 풀면 그 폴더에서 빠집니다. 어디에도 없으면 "미지정"이 됩니다.'
                    : '고른 폴더에 선택한 사진이 추가됩니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newFolder,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        hintText: '새 폴더 이름',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _createFolder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _createFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    tooltip: '폴더 만들기',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : foldersAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(child: Text('$error')),
                      data: (folders) => folders.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  '아직 폴더가 없습니다.\n위에서 첫 폴더를 만들어 보세요.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: folders.length,
                              itemBuilder: (context, index) {
                                final PhotoFolder folder = folders[index];
                                return CheckboxListTile(
                                  value: _checked.contains(folder.id),
                                  title: Text(folder.name),
                                  subtitle: Text('사진 ${folder.photoCount}장'),
                                  secondary:
                                      const Icon(Icons.folder_outlined),
                                  onChanged: (checked) => setState(() {
                                    if (checked ?? false) {
                                      _checked = {..._checked, folder.id};
                                    } else {
                                      _checked = {..._checked}
                                        ..remove(folder.id);
                                    }
                                  }),
                                );
                              },
                            ),
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _ready ? _save : null,
                        child: const Text('저장'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

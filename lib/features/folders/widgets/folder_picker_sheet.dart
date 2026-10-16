import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';

/// 폴더 고르기를 끝낸 결과.
class FolderPickOutcome {
  const FolderPickOutcome({
    required this.action,
    required this.photoCount,
    required this.folderCount,
  });

  final FolderPickAction action;
  final int photoCount;
  final int folderCount;

  /// 사용자에게 보여 줄 한 줄.
  String get message {
    switch (action) {
      case FolderPickAction.copied:
        return '사진 $photoCount장을 폴더 $folderCount곳에 넣었습니다.';
      case FolderPickAction.moved:
        return '사진 $photoCount장을 옮겼습니다.';
      case FolderPickAction.saved:
        return '폴더를 지정했습니다.';
    }
  }
}

enum FolderPickAction {
  /// 지금 소속을 그대로 두고 고른 폴더에 더 넣었음.
  copied,

  /// 보고 있던 폴더에서 빼고 고른 폴더로 옮겼음.
  moved,

  /// 사진 한 장의 소속을 통째로 지정했음.
  saved,
}

/// 사진을 어떤 가상 폴더에 넣을지 고르는 바텀시트.
///
/// 세 가지 쓰임이 한 시트에 있습니다.
/// * **사진 한 장** (뷰어) — 현재 소속이 체크되어 있고, 체크를 풀면 빼냅니다.
///   저장하면 소속이 고른 그대로가 됩니다.
/// * **여러 장, 폴더 밖에서** (사진 탭·태그 상세·미지정) — **복사**만
///   할 수 있습니다. 출처가 없으니 "이동"은 뜻이 서지 않습니다.
/// * **여러 장, 폴더 안에서** (폴더 상세) — **복사**와 **이동**을 가릅니다.
///   이동은 보고 있던 폴더에서만 빼고 다른 폴더 소속은 건드리지 않습니다.
///   한 사진이 여러 폴더에 들어갈 수 있는 구조라, 이동을 "소속 전체 교체"로
///   해석하면 보고 있지도 않은 폴더에서 사진이 조용히 빠집니다.
class FolderPickerSheet extends ConsumerStatefulWidget {
  const FolderPickerSheet({
    super.key,
    required this.photoKeys,
    this.sourceFolderId,
    this.sourceFolderName,
  });

  final List<String> photoKeys;

  /// 어느 폴더를 보다가 열었는지. 있으면 "이동"을 쓸 수 있습니다.
  final String? sourceFolderId;
  final String? sourceFolderName;

  static Future<FolderPickOutcome?> show(
    BuildContext context,
    List<String> photoKeys, {
    String? sourceFolderId,
    String? sourceFolderName,
  }) {
    return showModalBottomSheet<FolderPickOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolderPickerSheet(
        photoKeys: photoKeys,
        sourceFolderId: sourceFolderId,
        sourceFolderName: sourceFolderName,
      ),
    );
  }

  @override
  ConsumerState<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends ConsumerState<FolderPickerSheet> {
  final _newFolder = TextEditingController();
  Set<String> _checked = {};
  bool _ready = false;
  bool _busy = false;

  bool get _isSingle => widget.photoKeys.length == 1;
  bool get _canMove => !_isSingle && widget.sourceFolderId != null;

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

  /// 고를 수 있는 폴더가 하나라도 체크되었는지.
  ///
  /// 출처 폴더는 체크해도 넣을 곳이 되지 않으므로 세지 않습니다. 그걸
  /// 세면 출처만 고른 채 버튼이 켜지고, 눌러도 아무 일이 없습니다.
  Set<String> get _targets =>
      {..._checked}..remove(widget.sourceFolderId ?? '');

  Future<void> _finish(FolderPickAction action) async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = ref.read(folderServiceProvider);
    final targets = _targets;
    try {
      if (action == FolderPickAction.saved) {
        await service.setFoldersOf(widget.photoKeys.first, _checked);
      } else if (action == FolderPickAction.copied) {
        await service.copyPhotos(targets, widget.photoKeys);
      } else {
        await service.movePhotos(
          from: widget.sourceFolderId!,
          targetFolderIds: targets,
          photoKeys: widget.photoKeys,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('폴더를 바꾸지 못했습니다: $error')));
      return;
    }

    if (!mounted) return;
    ref.bumpDataRevision();
    Navigator.of(context).pop(
      FolderPickOutcome(
        action: action,
        photoCount: widget.photoKeys.length,
        folderCount: action == FolderPickAction.saved
            ? _checked.length
            : targets.length,
      ),
    );
  }

  String get _title {
    if (_isSingle) return '폴더 지정';
    return '폴더 — 사진 ${widget.photoKeys.length}장';
  }

  String get _hint {
    if (_isSingle) {
      return '체크를 풀면 그 폴더에서 빠집니다. 어디에도 없으면 "미지정"이 됩니다.';
    }
    if (_canMove) {
      return '넣을 폴더를 고른 뒤 아래에서 고르세요. '
          '복사하면 "${widget.sourceFolderName ?? '지금 폴더'}"에도 그대로 남고, '
          '이동하면 거기서는 빠집니다. 다른 폴더 소속은 건드리지 않습니다.';
    }
    return '고른 폴더에 선택한 사진이 추가됩니다. 지금 속한 폴더는 그대로 둡니다.';
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
            Text(_title, style: Theme.of(context).textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                _hint,
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
                      data: _buildList,
                    ),
            ),
            SafeArea(child: _buildActions()),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<PhotoFolder> folders) {
    if (folders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '아직 폴더가 없습니다.\n위에서 첫 폴더를 만들어 보세요.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // 전부 펼쳐서 보여 줍니다. 고르려고 연 시트인데 접혀 있으면 원하는
    // 폴더를 찾으려 또 펼쳐야 합니다.
    final nodes = buildFolderTree(folders);

    return ListView.builder(
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        final node = nodes[index];
        final folder = node.folder;

        // 출처 폴더는 넣을 곳이 될 수 없습니다. 목록에서 빼지 않고 잠그는
        // 이유는, 빼 버리면 그 아래 하위 폴더들이 부모를 잃어 트리 모양이
        // 어그러지기 때문입니다.
        final isSource = folder.id == widget.sourceFolderId;

        return CheckboxListTile(
          value: _checked.contains(folder.id),
          enabled: !isSource,
          title: Text(folder.name),
          subtitle: Text(
            isSource
                ? '지금 보고 있는 폴더'
                : '사진 ${folder.photoCount}장'
                    '${folder.subfolderCount > 0 ? ' · 하위 ${folder.subfolderCount}개' : ''}',
          ),
          secondary: Padding(
            // 깊이만큼 들여써서 트리 모양을 보여 줍니다.
            padding: EdgeInsets.only(left: node.depth * 16.0),
            child: Icon(
              node.hasChildren ? Icons.folder_copy_outlined : Icons.folder_outlined,
            ),
          ),
          onChanged: isSource
              ? null
              : (checked) => setState(() {
                    if (checked ?? false) {
                      _checked = {..._checked, folder.id};
                    } else {
                      _checked = {..._checked}..remove(folder.id);
                    }
                  }),
        );
      },
    );
  }

  Widget _buildActions() {
    final enabled = _ready && !_busy;
    final hasTarget = _targets.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
          ),
          const SizedBox(width: 12),
          if (_isSingle)
            Expanded(
              child: FilledButton(
                onPressed:
                    enabled ? () => _finish(FolderPickAction.saved) : null,
                child: const Text('저장'),
              ),
            )
          else ...[
            Expanded(
              child: _canMove
                  ? OutlinedButton.icon(
                      onPressed: enabled && hasTarget
                          ? () => _finish(FolderPickAction.copied)
                          : null,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('복사'),
                    )
                  : FilledButton.icon(
                      onPressed: enabled && hasTarget
                          ? () => _finish(FolderPickAction.copied)
                          : null,
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: const Text('복사'),
                    ),
            ),
            if (_canMove) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled && hasTarget
                      ? () => _finish(FolderPickAction.moved)
                      : null,
                  icon: const Icon(Icons.drive_file_move_outlined, size: 18),
                  label: const Text('이동'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

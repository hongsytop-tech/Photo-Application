import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/folders/widgets/folder_picker_sheet.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_viewer_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/gallery/widgets/photo_grid.dart';
import 'package:photo_application/features/tags/widgets/tag_picker_sheet.dart';

/// 조건이 정해진 사진 목록 화면 한 벌.
///
/// 갤러리 탭, 폴더 상세, 태그 상세가 전부 이 화면을 재사용합니다. 앱바의
/// 선택 버튼을 누르거나 사진을 길게 누르면 선택 모드로 들어가, 여러 장에
/// 태그를 달거나 폴더에 넣거나 한 번에 치울 수 있습니다.
class PhotoBrowserScreen extends ConsumerStatefulWidget {
  const PhotoBrowserScreen({
    super.key,
    required this.title,
    required this.query,
    this.subtitle,
    this.header,
    this.actions = const [],
    this.emptyMessage = '사진이 없습니다.',
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final PhotoQuery query;

  /// 그리드 위에 함께 스크롤되는 영역 (필터 칩 등).
  final Widget? header;

  /// 선택 모드가 아닐 때 앱바에 붙는 버튼들.
  final List<Widget> actions;

  final String emptyMessage;
  final bool showBack;

  @override
  ConsumerState<PhotoBrowserScreen> createState() => _PhotoBrowserScreenState();
}

class _PhotoBrowserScreenState extends ConsumerState<PhotoBrowserScreen> {
  /// 선택된 asset id 들. 화면에 보이는 단위가 사진(asset)이라 asset id 로 잡고,
  /// 실제 태그·폴더 작업 직전에 photo_key 로 바꿔 중복을 없앱니다.
  final Set<String> _selected = {};
  bool _selectionMode = false;

  /// 삭제가 도는 동안 버튼을 잠급니다. 시스템 확인 창이 떠 있는 사이 한 번 더
  /// 누르면 같은 사진을 두 번 지우려 들게 됩니다.
  bool _deleting = false;

  /// 선택 버튼으로 들어왔는지.
  ///
  /// 길게 눌러 들어온 선택 모드는 마지막 한 장을 풀면 알아서 빠져나갑니다.
  /// 버튼으로 들어온 경우까지 그러면, 방금 "선택"을 누른 사람이 고르기를
  /// 무르는 순간 선택 모드가 통째로 사라져 버립니다.
  bool _selectionPinned = false;

  void _startSelection(PhotoItem item) {
    setState(() {
      _selectionMode = true;
      _selectionPinned = false;
      _selected
        ..clear()
        ..add(item.assetId);
    });
  }

  /// 앱바 버튼으로 선택 모드를 켭니다. 고른 것 없이 시작해서, 사진을 눌러
  /// 담습니다. 길게 누르기는 그대로 둡니다 — 익숙한 쪽을 뺏지 않습니다.
  void _beginSelection() {
    setState(() {
      _selectionMode = true;
      _selectionPinned = true;
      _selected.clear();
    });
  }

  void _toggle(PhotoItem item) {
    setState(() {
      if (!_selected.remove(item.assetId)) {
        _selected.add(item.assetId);
      }
      if (_selected.isEmpty && !_selectionPinned) _selectionMode = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
      _selectionPinned = false;
      _selected.clear();
    });
  }

  void _selectAllLoaded() {
    final items = ref.read(photoListProvider(widget.query)).items;
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..addAll(items.map((e) => e.assetId));
    });
  }

  /// 선택된 asset 들의 photo_key 집합.
  ///
  /// 화면에 읽어온 항목만 훑지 않고 DB 에 물어봅니다. 선택이 어디서 왔든
  /// 키를 빠짐없이 모으기 위해서입니다 — 놓치면 태그·폴더가 고른 사진의
  /// 일부에만 붙습니다. 같은 사진의 복사본은 키가 겹치므로 조회 쪽에서
  /// DISTINCT 로 접힙니다.
  Future<List<String>> _selectedPhotoKeys() =>
      ref.read(photoQueryServiceProvider).photoKeysOf(_selected);

  Future<void> _bulkTag() async {
    final keys = await _selectedPhotoKeys();
    if (!mounted) return;
    if (keys.isEmpty) return;
    final saved = await TagPickerSheet.show(context, keys);
    if (saved ?? false) _clearSelection();
  }

  Future<void> _bulkFolder() async {
    final keys = await _selectedPhotoKeys();
    if (!mounted) return;
    if (keys.isEmpty) return;
    final saved = await FolderPickerSheet.show(context, keys);
    if (saved ?? false) _clearSelection();
  }

  /// 고른 사진을 기기에서 치웁니다 — 되도록 **휴지통으로** 보냅니다.
  ///
  /// 이 앱의 다른 모든 동작은 사진 파일을 읽기만 하는데 이것만 예외라서,
  /// 확인 창에서 무엇이 일어나는지 분명히 말합니다. 그 뒤에 안드로이드가
  /// 시스템 확인 창을 한 번 더 띄웁니다.
  Future<void> _bulkDelete() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('사진 ${ids.length}장을 휴지통으로 보낼까요?'),
        content: const Text(
          '기기의 휴지통으로 들어가며, 30일 안에는 갤러리에서 되살릴 수 '
          '있습니다. 휴지통이 없는 기기(안드로이드 10 이하)에서는 바로 '
          '지워집니다.\n\n'
          '메모와 태그는 지우지 않습니다. 같은 사진이 다른 기기에 남아 있을 수 '
          '있어서, 거기서는 그대로 보입니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('휴지통으로'),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;

    setState(() => _deleting = true);
    try {
      // 시스템 확인 창에서 거절당하면 빈 목록이 옵니다. 요청한 수가 아니라
      // 실제로 치워진 것만 인덱스에서 뺍니다.
      final removed = await ref.read(galleryServiceProvider).removeAssets(ids);
      await ref.read(photoIndexServiceProvider).forget(removed.ids);
      if (!mounted) return;

      ref.bumpDataRevision();
      _clearSelection();
      if (removed.isEmpty) {
        _say('아무것도 치우지 않았습니다.');
      } else if (removed.trashed) {
        _say('${removed.ids.length}장을 휴지통으로 보냈습니다.');
      } else {
        _say('${removed.ids.length}장을 기기에서 지웠습니다.');
      }
    } catch (error, stack) {
      debugPrint('사진 삭제 실패: $error\n$stack');
      if (mounted) _say('치우지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _open(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoViewerScreen(
          query: widget.query,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider(widget.query));

    return PopScope(
      // 선택 모드에서 뒤로 가기를 누르면 화면을 닫지 말고 선택만 해제합니다.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: Scaffold(
        appBar: _selectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                  tooltip: '선택 해제',
                ),
                title: Text(
                  _selected.isEmpty ? '사진 선택' : '${_selected.length}장 선택',
                ),
                // 아무것도 안 골랐을 때는 눌러도 할 일이 없으므로 잠급니다.
                // 눌리는데 아무 일도 안 일어나면 고장으로 보입니다.
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: _selectAllLoaded,
                    tooltip: '불러온 사진 모두 선택',
                  ),
                  IconButton(
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: _selected.isEmpty ? null : _bulkTag,
                    tooltip: '태그 달기',
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined),
                    onPressed: _selected.isEmpty ? null : _bulkFolder,
                    tooltip: '폴더에 넣기',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        _deleting || _selected.isEmpty ? null : _bulkDelete,
                    tooltip: '휴지통으로 보내기',
                  ),
                ],
              )
            : AppBar(
                automaticallyImplyLeading: widget.showBack,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title),
                    Text(
                      widget.subtitle ?? '${state.total}장',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    onPressed: state.items.isEmpty ? null : _beginSelection,
                    tooltip: '사진 여러 장 선택',
                  ),
                  ...widget.actions,
                ],
              ),
        body: PhotoGrid(
          query: widget.query,
          header: widget.header,
          emptyMessage: widget.emptyMessage,
          selection: _selected,
          selectionMode: _selectionMode,
          onOpen: _open,
          onToggleSelect: _toggle,
          onStartSelection: _startSelection,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/features/folders/widgets/folder_picker_sheet.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/screens/photo_viewer_screen.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/gallery/widgets/photo_grid.dart';
import 'package:photo_application/features/tags/widgets/tag_picker_sheet.dart';

/// 조건이 정해진 사진 목록 화면 한 벌.
///
/// 갤러리 탭, 폴더 상세, 태그 상세가 전부 이 화면을 재사용합니다. 길게 눌러
/// 선택 모드로 들어가면 여러 장에 태그를 달거나 폴더에 넣을 수 있습니다.
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

  void _startSelection(PhotoItem item) {
    setState(() {
      _selectionMode = true;
      _selected
        ..clear()
        ..add(item.assetId);
    });
  }

  void _toggle(PhotoItem item) {
    setState(() {
      if (!_selected.remove(item.assetId)) {
        _selected.add(item.assetId);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectionMode = false;
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

  /// 선택된 asset 들의 photo_key 집합. 같은 사진의 복사본이 함께 선택되면
  /// 키가 겹치므로 Set 으로 접습니다.
  List<String> _selectedPhotoKeys() {
    final items = ref.read(photoListProvider(widget.query)).items;
    return items
        .where((item) => _selected.contains(item.assetId))
        .map((item) => item.photoKey)
        .toSet()
        .toList();
  }

  Future<void> _bulkTag() async {
    final keys = _selectedPhotoKeys();
    if (keys.isEmpty) return;
    final saved = await TagPickerSheet.show(context, keys);
    if (saved ?? false) _clearSelection();
  }

  Future<void> _bulkFolder() async {
    final keys = _selectedPhotoKeys();
    if (keys.isEmpty) return;
    final saved = await FolderPickerSheet.show(context, keys);
    if (saved ?? false) _clearSelection();
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
                title: Text('${_selected.length}장 선택'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    onPressed: _selectAllLoaded,
                    tooltip: '불러온 사진 모두 선택',
                  ),
                  IconButton(
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: _bulkTag,
                    tooltip: '태그 달기',
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined),
                    onPressed: _bulkFolder,
                    tooltip: '폴더에 넣기',
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
                actions: widget.actions,
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

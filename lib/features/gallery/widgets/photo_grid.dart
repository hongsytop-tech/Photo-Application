import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/providers/grid_columns.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/gallery/widgets/photo_thumb.dart';
import 'package:photo_application/features/notes/widgets/note_dialog.dart';

/// 조건에 맞는 사진을 무한 스크롤 그리드로 보여줍니다.
///
/// 갤러리 탭, 폴더 상세, 태그 상세가 모두 이 위젯을 씁니다.
class PhotoGrid extends ConsumerStatefulWidget {
  const PhotoGrid({
    super.key,
    required this.query,
    required this.onOpen,
    this.selection = const <String>{},
    this.selectionMode = false,
    this.onToggleSelect,
    this.onStartSelection,
    this.header,
    this.emptyMessage = '사진이 없습니다.',
  });

  final PhotoQuery query;

  /// 사진을 눌렀을 때 (선택 모드가 아닐 때). 인자는 목록 내 위치입니다.
  final void Function(int index) onOpen;

  /// 선택된 asset id 집합.
  final Set<String> selection;
  final bool selectionMode;
  final void Function(PhotoItem item)? onToggleSelect;
  final void Function(PhotoItem item)? onStartSelection;

  /// 그리드 위에 함께 스크롤되는 영역 (필터 칩 등).
  final Widget? header;
  final String emptyMessage;

  @override
  ConsumerState<PhotoGrid> createState() => _PhotoGridState();
}

class _PhotoGridState extends ConsumerState<PhotoGrid> {
  final _controller = ScrollController();

  /// 메모 배지를 그리려면 어떤 사진에 메모가 있는지 알아야 합니다.
  /// 사진마다 따로 조회하면 스크롤 한 번에 수백 번 질의하게 되므로,
  /// 화면에 보이는 범위의 키만 모아 한 번에 물어봅니다.
  Set<String> _keysWithNote = const {};
  int _noteRevision = -1;

  /// 화면에 닿아 있는 손가락들. 두 개가 되면 그 사이 거리로 확대·축소를 봅니다.
  final _touches = <int, Offset>{};
  double? _spreadAtLastStep;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - 800) {
      ref.read(photoListProvider(widget.query).notifier).loadMore();
    }
  }

  // --- 손가락으로 크기 조절 ---------------------------------------------
  //
  // 제스처 인식기(GestureDetector) 대신 Listener 로 원시 포인터를 봅니다.
  // ScaleGestureRecognizer 는 손가락 하나로도 승부에 참여해서 그리드의 세로
  // 스크롤을 빼앗습니다. Listener 는 승부에 끼지 않고 지켜보기만 하므로
  // 한 손가락 스크롤은 그대로 두고 두 손가락일 때만 우리가 반응할 수 있습니다.

  double? _spread() {
    if (_touches.length < 2) return null;
    final points = _touches.values.toList();
    return (points[0] - points[1]).distance;
  }

  void _touchDown(PointerDownEvent event) {
    _touches[event.pointer] = event.position;
    _spreadAtLastStep = _spread();
  }

  void _touchMove(PointerMoveEvent event) {
    if (!_touches.containsKey(event.pointer)) return;
    _touches[event.pointer] = event.position;

    final spread = _spread();
    final base = _spreadAtLastStep;
    if (spread == null || base == null || base < 24) {
      _spreadAtLastStep = spread;
      return;
    }

    // 한 번 벌릴 때 한 칸씩만 움직입니다. 비율로 재고 단계마다 기준을 다시
    // 잡아야 손가락을 계속 벌려도 두 칸, 세 칸 연속으로 넘어갈 수 있습니다.
    final ratio = spread / base;
    if (ratio > 1.3) {
      ref.read(gridColumnsProvider.notifier).zoomIn();
      _spreadAtLastStep = spread;
    } else if (ratio < 0.77) {
      ref.read(gridColumnsProvider.notifier).zoomOut();
      _spreadAtLastStep = spread;
    }
  }

  void _touchEnd(PointerEvent event) {
    _touches.remove(event.pointer);
    _spreadAtLastStep = _spread();
  }

  Future<void> _refreshNoteBadges(int revision) async {
    if (revision == _noteRevision) return;
    _noteRevision = revision;
    final db = ref.read(appDatabaseProvider).db;
    final rows = await db.rawQuery(
      "SELECT DISTINCT photo_key FROM notes WHERE deleted = 0 AND TRIM(body) != ''",
    );
    if (!mounted) return;
    setState(() {
      _keysWithNote = rows.map((r) => r['photo_key'] as String).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider(widget.query));
    final revision = ref.watch(dataRevisionProvider);
    final columns = ref.watch(gridColumnsProvider);

    // 메모 배지 캐시는 목록 렌더와 독립적으로 갱신합니다.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshNoteBadges(revision),
    );

    final header = widget.header;

    if (state.isEmpty) {
      return RefreshIndicator(
        onRefresh: () =>
            ref.read(photoListProvider(widget.query).notifier).refresh(),
        child: ListView(
          controller: _controller,
          children: [
            if (header != null) header,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 96, horizontal: 32),
              child: Text(
                widget.emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return Listener(
      onPointerDown: _touchDown,
      onPointerMove: _touchMove,
      onPointerUp: _touchEnd,
      onPointerCancel: _touchEnd,
      child: RefreshIndicator(
        onRefresh: () =>
            ref.read(photoListProvider(widget.query).notifier).refresh(),
        child: CustomScrollView(
          controller: _controller,
          slivers: [
            if (header != null) SliverToBoxAdapter(child: header),
            SliverPadding(
              padding: const EdgeInsets.all(2),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return PhotoThumb(
                    key: ValueKey(item.assetId),
                    item: item,
                    selectionMode: widget.selectionMode,
                    selected: widget.selection.contains(item.assetId),
                    hasNote: _keysWithNote.contains(item.photoKey),
                    onTap: () {
                      if (widget.selectionMode) {
                        widget.onToggleSelect?.call(item);
                      } else {
                        widget.onOpen(index);
                      }
                    },
                    onLongPress: () => widget.selectionMode
                        ? widget.onToggleSelect?.call(item)
                        : widget.onStartSelection?.call(item),
                    // 선택 중에는 배지도 선택으로 동작해야 합니다. 그 상황에서만
                    // 메모 팝업이 열리면 고르려다 메모창이 뜨는 일이 생깁니다.
                    onNoteTap: widget.selectionMode
                        ? null
                        : () => showNoteDialog(context, ref, item.photoKey),
                  );
                },
              ),
            ),
            if (state.loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

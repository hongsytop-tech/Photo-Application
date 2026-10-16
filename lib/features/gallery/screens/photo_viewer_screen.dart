import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:photo_application/core/theme/app_theme.dart';
import 'package:photo_application/features/folders/widgets/folder_picker_sheet.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/gallery/widgets/trash_photos.dart';
import 'package:photo_application/features/gallery/widgets/zoomable_photo.dart';
import 'package:photo_application/features/notes/screens/note_edit_screen.dart';
import 'package:photo_application/features/tags/widgets/tag_picker_sheet.dart';

/// 사진 한 장을 크게 보고, 메모·태그·폴더를 붙이는 화면.
///
/// 목록과 같은 조건([query])을 그대로 들고 있어서 좌우로 넘기면 그 조건의
/// 다음/이전 사진으로 이동합니다. 두 손가락으로 벌리거나 두 번 눌러 확대할
/// 수 있고, 확대한 동안에는 페이지 넘김이 꺼집니다 (안 그러면 확대한 자리를
/// 끌어 볼 수 없습니다).
class PhotoViewerScreen extends ConsumerStatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.query,
    required this.initialIndex,
  });

  final PhotoQuery query;
  final int initialIndex;

  @override
  ConsumerState<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends ConsumerState<PhotoViewerScreen> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// 지금 보고 있는 사진이 확대되어 있는지. 확대 중에는 페이지를 넘기지
  /// 않습니다 — 넘김이 켜져 있으면 확대한 사진을 끌어 옮길 수 없습니다.
  bool _zoomed = false;

  /// 삭제가 도는 동안 버튼을 잠급니다. 시스템 확인 창이 떠 있는 사이 한 번
  /// 더 누르면 같은 사진을 두 번 지우려 들게 됩니다.
  bool _deleting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 보고 있는 사진을 휴지통으로 보냅니다.
  ///
  /// [index] 는 목록 안의 위치, [loaded] 는 지금 읽어 둔 사진 수입니다.
  /// 지운 뒤 목록이 줄어들기 때문에 둘 다 필요합니다.
  /// * 한 장뿐이었으면 화면을 닫습니다. 빈 화면에 남겨 두면 방금 지운
  ///   것이 아직 있는 것처럼 보입니다.
  /// * 맨 끝 사진을 지웠으면 한 칸 앞으로 물러납니다. 그대로 두면
  ///   `PageView` 가 없는 페이지를 가리켜 빈 화면이 됩니다.
  /// * 가운데 사진을 지웠으면 그 자리에 다음 사진이 들어오므로 그대로
  ///   둡니다.
  Future<void> _delete(
    PhotoItem item, {
    required int index,
    required int loaded,
  }) async {
    setState(() => _deleting = true);
    try {
      final removed = await confirmAndTrash(context, ref, [item.assetId]);
      if (!mounted || removed == null) return;

      final message = trashMessage(removed);
      if (removed.isEmpty) {
        _say(message);
        return;
      }
      if (loaded <= 1) {
        Navigator.of(context).pop();
        return;
      }
      if (index >= loaded - 1 && index > 0) {
        setState(() => _index = index - 1);
        _pageController.jumpToPage(_index);
      }
      _say(message);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoListProvider(widget.query));
    final items = state.items;

    if (items.isEmpty) {
      return const Scaffold(
        backgroundColor: AppTheme.canvas,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 목록이 줄어들어 현재 위치가 범위를 벗어날 수 있습니다 (사진 삭제 등).
    final index = _index.clamp(0, items.length - 1);
    final current = items[index];

    return Scaffold(
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          '${index + 1} / ${state.total}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleting
                ? null
                : () => _delete(current, index: index, loaded: items.length),
            tooltip: '휴지통으로 보내기',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              // 확대 중에는 넘김을 끕니다. 켜 두면 확대한 사진을 끌어
              // 옮기려는 손짓을 PageView 가 가로채 옆 사진으로 넘어갑니다.
              physics: _zoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              onPageChanged: (next) {
                setState(() => _index = next);
                // 끝에 가까워지면 다음 페이지를 미리 읽어 둡니다.
                if (next >= items.length - 5) {
                  ref
                      .read(photoListProvider(widget.query).notifier)
                      .loadMore();
                }
              },
              itemBuilder: (context, i) => ZoomablePhoto(
                key: ValueKey(items[i].assetId),
                item: items[i],
                onZoomChanged: (zoomed) {
                  if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                },
              ),
            ),
          ),
          _MetaPanel(item: current),
        ],
      ),
    );
  }
}

/// 사진 아래에 붙는 메타데이터 패널.
class _MetaPanel extends ConsumerWidget {
  const _MetaPanel({required this.item});

  final PhotoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteAsync = ref.watch(noteForPhotoProvider(item.photoKey));
    final tagsAsync = ref.watch(tagsForPhotoProvider(item.photoKey));
    final scheme = Theme.of(context).colorScheme;
    final note = noteAsync.valueOrNull;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                DateFormat('yyyy년 M월 d일 HH:mm').format(item.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),

              // --- 태그 ---
              tagsAsync.when(
                loading: () => const SizedBox(height: 8),
                error: (_, __) => const SizedBox(height: 8),
                data: (tags) => tags.isEmpty
                    ? const SizedBox(height: 8)
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in tags)
                              Chip(
                                label: Text(tag.name),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                      ),
              ),

              // --- 메모 미리보기 ---
              if (note != null && !note.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: InkWell(
                    onTap: () => _openNote(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        note.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Action(
                    icon: note != null && !note.isEmpty
                        ? Icons.sticky_note_2
                        : Icons.sticky_note_2_outlined,
                    label: note != null && !note.isEmpty ? '메모 편집' : '메모 쓰기',
                    onTap: () => _openNote(context),
                  ),
                  _Action(
                    icon: Icons.sell_outlined,
                    label: '태그',
                    onTap: () =>
                        TagPickerSheet.show(context, [item.photoKey]),
                  ),
                  _Action(
                    icon: Icons.folder_outlined,
                    label: '폴더',
                    onTap: () =>
                        FolderPickerSheet.show(context, [item.photoKey]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNote(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditScreen(
          photoKey: item.photoKey,
          photoName: item.fileName,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
    );
  }
}

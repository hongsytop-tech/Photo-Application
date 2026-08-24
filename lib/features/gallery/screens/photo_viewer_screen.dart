import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:photo_application/core/theme/app_theme.dart';
import 'package:photo_application/features/folders/widgets/folder_picker_sheet.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/notes/screens/note_edit_screen.dart';
import 'package:photo_application/features/tags/widgets/tag_picker_sheet.dart';

/// 사진 한 장을 크게 보고, 메모·태그·폴더를 붙이는 화면.
///
/// 목록과 같은 조건([query])을 그대로 들고 있어서 좌우로 넘기면 그 조건의
/// 다음/이전 사진으로 이동합니다.
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

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (next) {
                setState(() => _index = next);
                // 끝에 가까워지면 다음 페이지를 미리 읽어 둡니다.
                if (next >= items.length - 5) {
                  ref
                      .read(photoListProvider(widget.query).notifier)
                      .loadMore();
                }
              },
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image(
                    image: AssetEntityImageProvider(
                      items[i].toEntity(),
                      isOriginal: true,
                    ),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38,
                        size: 48,
                      ),
                    ),
                  ),
                ),
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

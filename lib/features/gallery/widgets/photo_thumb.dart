import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:photo_application/features/gallery/models/photo_item.dart';

/// 그리드 한 칸.
///
/// 원본이 아니라 MediaStore 가 만들어 둔 썸네일을 씁니다. 4000px 짜리 원본을
/// 100px 칸에 그리면 사진 몇십 장 만에 메모리가 바닥납니다.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.item,
    this.selected = false,
    this.selectionMode = false,
    this.hasNote = false,
    this.onTap,
    this.onLongPress,
    this.onNoteTap,
  });

  final PhotoItem item;
  final bool selected;
  final bool selectionMode;
  final bool hasNote;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 메모 배지를 눌렀을 때. null 이면 배지는 그냥 표시로만 남습니다.
  final VoidCallback? onNoteTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: AssetEntityImageProvider(
              item.toEntity(),
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(256),
            ),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(
                Icons.broken_image_outlined,
                color: scheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ),

          if (hasNote)
            Positioned(
              right: 0,
              bottom: 0,
              // 누를 수 있을 때만 GestureDetector 를 답니다. 눌러도 할 일이
              // 없는 상태(선택 중)에서 opaque 로 감싸 두면, 그 자리를 눌렀을 때
              // 아무 일도 일어나지 않아 사진 선택이 먹히지 않습니다.
              child: onNoteTap == null
                  ? const Padding(
                      padding: EdgeInsets.all(3),
                      child: _Badge(icon: Icons.sticky_note_2),
                    )
                  : GestureDetector(
                      onTap: onNoteTap,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        // 배지가 작아 손가락으로 정확히 누르기 어렵습니다.
                        // 눌리는 범위만 넓히고 보이는 크기는 그대로 둡니다.
                        padding: EdgeInsets.all(6),
                        child: _Badge(icon: Icons.sticky_note_2),
                      ),
                    ),
            ),

          if (selectionMode)
            Positioned(
              left: 3,
              top: 3,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? scheme.primary : Colors.white70,
                shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),

          if (selected)
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.28),
                border: Border.all(color: scheme.primary, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: Colors.white),
    );
  }
}

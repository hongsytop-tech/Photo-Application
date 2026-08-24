import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';

/// 사진 접근 권한이 있을 때만 [child] 를 보여주고, 없으면 안내 화면을 냅니다.
class PermissionGate extends ConsumerWidget {
  const PermissionGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessAsync = ref.watch(galleryAccessProvider);

    return accessAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _Message(
        icon: Icons.error_outline,
        title: '권한 상태를 확인하지 못했습니다',
        body: '$error',
        actionLabel: '다시 시도',
        onAction: () => ref.invalidate(galleryAccessProvider),
      ),
      data: (access) {
        switch (access) {
          case GalleryAccess.granted:
          case GalleryAccess.limited:
            return child;

          case GalleryAccess.unknown:
            return _Message(
              icon: Icons.photo_library_outlined,
              title: '사진에 접근할 수 있게 허용해 주세요',
              body: '이 앱은 폰에 있는 사진을 읽어서 목록을 만듭니다.\n'
                  '사진을 옮기거나 고치거나 어딘가로 보내지 않습니다.',
              actionLabel: '허용하기',
              onAction: () async {
                await ref.read(galleryServiceProvider).requestAccess();
                ref.invalidate(galleryAccessProvider);
                await ref.read(indexingProvider.notifier).run();
              },
            );

          case GalleryAccess.denied:
            return _Message(
              icon: Icons.lock_outline,
              title: '사진 권한이 꺼져 있습니다',
              body: '설정 앱에서 이 앱의 "사진 및 동영상" 권한을 켜야 사진 목록을 만들 수 있습니다.',
              actionLabel: '설정 열기',
              onAction: () => ref.read(galleryServiceProvider).openSettings(),
            );
        }
      },
    );
  }
}

/// "일부 사진만 허용" 상태에서 뜨는 안내 배너.
class LimitedAccessBanner extends ConsumerWidget {
  const LimitedAccessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(galleryAccessProvider).valueOrNull;
    if (access != GalleryAccess.limited) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '허용한 사진만 보이는 상태입니다.',
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(galleryServiceProvider).pickMorePhotos();
              ref.invalidate(galleryAccessProvider);
              await ref.read(indexingProvider.notifier).run();
            },
            child: const Text('더 고르기'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

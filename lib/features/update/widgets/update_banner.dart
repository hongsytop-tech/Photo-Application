import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/features/update/providers/update_providers.dart';

/// 새 버전이 있을 때 목록 위에 뜨는 띠.
///
/// 확인할 게 없으면 자리를 차지하지 않습니다.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    if (!state.shouldPrompt) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final release = state.release;
    final downloading = state.phase == UpdatePhase.downloading;
    final installing = state.phase == UpdatePhase.installing;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, size: 20, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  installing
                      ? '설치 화면을 여는 중…'
                      : downloading
                          ? '새 버전 받는 중…'
                          : '새 버전이 있습니다'
                            '${release == null ? '' : ' (${release.sizeLabel})'}',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ),
              if (!downloading && !installing) ...[
                TextButton(
                  onPressed: () => ref.read(updateProvider.notifier).dismiss(),
                  child: const Text('나중에'),
                ),
                FilledButton(
                  onPressed: () =>
                      ref.read(updateProvider.notifier).downloadAndInstall(),
                  child: const Text('업데이트'),
                ),
              ],
            ],
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 6),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
              ),
            ),
        ],
      ),
    );
  }
}

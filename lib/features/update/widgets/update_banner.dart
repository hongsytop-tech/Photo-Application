import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/features/update/providers/update_providers.dart';

/// 새 버전이 있을 때 목록 위에 뜨는 띠.
///
/// 확인할 게 없으면 자리를 차지하지 않습니다.
///
/// 업데이트는 두 걸음입니다. 먼저 설치 허용(갤럭시라면 자동 차단 해제)으로
/// 보내고, 허용이 끝난 뒤에야 내려받기 버튼을 내줍니다. 다 받아 놓고 설치
/// 화면에서 막히면 사용자는 몇십 MB 를 버린 채 이유도 알 수 없습니다.
class UpdateBanner extends ConsumerStatefulWidget {
  const UpdateBanner({super.key});

  @override
  ConsumerState<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<UpdateBanner> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 자동 차단은 우리가 연 화면이 아니라 시스템 설정에서 꺼야 할 때가
    // 있습니다. 껐다 돌아온 사용자에게 계속 "아직 허용되지 않았습니다"를
    // 보여 주지 않도록, 돌아올 때마다 다시 확인합니다.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(updateProvider.notifier).recheckPermission(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateProvider);
    if (!state.shouldPrompt) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final release = state.release;
    final phase = state.phase;
    final downloading = phase == UpdatePhase.downloading;
    final installing = phase == UpdatePhase.installing;
    final controller = ref.read(updateProvider.notifier);

    final String title;
    String? detail;
    Widget? action;

    // switch 대신 if 사슬입니다. 단계마다 세 가지(제목·설명·버튼)를 함께
    // 정해야 해서, 표현식 하나로 접기보다 이쪽이 읽기 낫습니다.
    if (phase == UpdatePhase.needsPermission) {
      title = '설치를 허용해야 합니다';
      detail = '스토어를 거치지 않는 앱이라 "이 출처의 앱 설치"를 켜 주셔야 합니다. '
          '갤럭시에서 스위치가 잠겨 있다면 설정 › 보안 및 개인정보 보호 › '
          '자동 차단을 먼저 꺼 주세요.';
      action = FilledButton.icon(
        onPressed: controller.openInstallSettings,
        icon: const Icon(Icons.lock_open, size: 18),
        label: const Text('설정 열기'),
      );
    } else if (phase == UpdatePhase.ready) {
      title = '설치가 허용되었습니다';
      detail = '이제 새 버전을 내려받을 수 있습니다'
          '${release == null ? '' : ' (${release.sizeLabel})'}.';
      action = FilledButton.icon(
        onPressed: controller.downloadAndInstall,
        icon: const Icon(Icons.download, size: 18),
        label: const Text('다운로드'),
      );
    } else if (downloading) {
      title = '새 버전 받는 중…';
    } else if (installing) {
      title = '설치 화면을 여는 중…';
    } else {
      title = '새 버전이 있습니다'
          '${release == null ? '' : ' (${release.sizeLabel})'}';
      action = FilledButton(
        onPressed: controller.start,
        child: const Text('업데이트'),
      );
    }

    // 지역 변수 승격에 기대지 않고 final 로 한 번 묶습니다.
    final detailText = detail;
    final actionButton = action;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                phase == UpdatePhase.needsPermission
                    ? Icons.lock_outline
                    : Icons.system_update,
                size: 20,
                color: scheme.onPrimaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (detailText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text(
                detailText,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.85),
                ),
              ),
            ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
              ),
            ),
          // 버튼은 아래 줄에 둡니다. 제목과 한 줄에 욱여넣으면 '설정 열기'
          // 처럼 긴 문구에서 좁은 화면이 넘칩니다.
          if (!downloading && !installing)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: controller.dismiss,
                    child: const Text('나중에'),
                  ),
                  const SizedBox(width: 4),
                  if (actionButton != null) actionButton,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

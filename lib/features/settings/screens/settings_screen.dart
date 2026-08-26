import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/core/supabase/supabase_service.dart';
import 'package:photo_application/features/auth/providers/auth_providers.dart';
import 'package:photo_application/features/auth/screens/login_screen.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/providers/photo_meta_providers.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/sync/providers/auto_sync.dart';
import 'package:photo_application/features/sync/providers/sync_providers.dart';
import 'package:photo_application/features/update/providers/update_providers.dart';

/// "설정" 탭 — 스캔, 계정/동기화, 권한, 데이터 초기화.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indexing = ref.watch(indexingProvider);
    final access = ref.watch(galleryAccessProvider).valueOrNull;
    final user = ref.watch(authStateProvider).valueOrNull;
    final sync = ref.watch(syncProvider);
    final update = ref.watch(updateProvider);
    final totalAsync = ref.watch(photoCountProvider(const PhotoQuery()));
    final tagsAsync = ref.watch(allTagsProvider);
    final foldersAsync = ref.watch(allFoldersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _SectionHeader('사진'),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('불러온 사진'),
            subtitle: Text('${totalAsync.valueOrNull ?? 0}장'),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('갤러리 다시 훑기'),
            subtitle: Text(
              indexing.running
                  ? '진행 중… ${indexing.done}/${indexing.total}'
                  : '새로 찍은 사진을 목록에 반영합니다.',
            ),
            trailing: indexing.running
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: indexing.running
                ? null
                : () => ref.read(indexingProvider.notifier).run(),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('사진 접근 권한'),
            subtitle: Text(_accessLabel(access)),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => ref.read(galleryServiceProvider).openSettings(),
          ),

          const _SectionHeader('내 데이터'),
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: const Text('태그'),
            subtitle: Text('${tagsAsync.valueOrNull?.length ?? 0}개'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('가상 폴더'),
            subtitle: Text('${foldersAsync.valueOrNull?.length ?? 0}개'),
          ),

          const _SectionHeader('동기화'),
          if (!SupabaseService.isConfigured)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('로컬 전용으로 동작 중'),
              subtitle: Text(
                '백엔드가 설정되지 않았습니다. 사진·메모·태그·폴더는 모두 정상 '
                '동작하며 이 폰에만 저장됩니다.',
              ),
            )
          else if (user == null)
            ListTile(
              leading: const Icon(Icons.cloud_queue),
              title: const Text('로그인'),
              subtitle: const Text(
                '메모·태그·폴더를 다른 기기와 맞춥니다. 사진 원본은 올라가지 않습니다.',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              ),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(user.email ?? '로그인됨'),
              subtitle: const Text('메모·태그·폴더만 동기화됩니다.'),
              trailing: TextButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('로그아웃'),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.autorenew),
              title: const Text('자동 동기화'),
              subtitle: const Text(
                '메모·태그·폴더를 고치면 잠시 뒤 알아서 올리고, 앱을 다시 열면 받아옵니다.',
              ),
              value: ref.watch(autoSyncEnabledProvider),
              onChanged: (value) =>
                  ref.read(autoSyncEnabledProvider.notifier).set(value),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('지금 동기화'),
              subtitle: Text(_syncLabel(sync)),
              trailing: sync.running
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: sync.running
                  ? null
                  : () => ref.read(syncProvider.notifier).run(),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('서버에서 전부 다시 받기'),
              subtitle: const Text('기기를 바꿨을 때 한 번 실행하세요.'),
              onTap: sync.running
                  ? null
                  : () => ref.read(syncProvider.notifier).resync(),
            ),
          ],

          const _SectionHeader('앱'),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('업데이트 확인'),
            subtitle: Text(_updateLabel(update)),
            trailing: update.busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: update.busy
                ? null
                : () => ref.read(updateProvider.notifier).check(),
          ),
          // 배너와 같은 두 걸음입니다. 허용 먼저, 내려받기는 그다음.
          if (update.phase == UpdatePhase.available)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.icon(
                onPressed: () => ref.read(updateProvider.notifier).start(),
                icon: const Icon(Icons.system_update),
                label: Text('지금 업데이트 (${update.release?.sizeLabel ?? ''})'),
              ),
            ),
          if (update.phase == UpdatePhase.needsPermission)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(updateProvider.notifier).openInstallSettings(),
                icon: const Icon(Icons.lock_open),
                label: const Text('설치 허용 설정 열기'),
              ),
            ),
          if (update.phase == UpdatePhase.ready)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FilledButton.icon(
                onPressed: () =>
                    ref.read(updateProvider.notifier).downloadAndInstall(),
                icon: const Icon(Icons.download),
                label: Text('다운로드 (${update.release?.sizeLabel ?? ''})'),
              ),
            ),

          const _SectionHeader('위험 구역'),
          ListTile(
            leading: Icon(
              Icons.delete_forever_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('메모·태그·폴더 전부 지우기'),
            subtitle: const Text('사진 파일은 지워지지 않습니다.'),
            onTap: () => _confirmWipe(context, ref),
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '이 앱은 사진을 읽기만 합니다. 사진을 고치거나 옮기거나 지우지 않고, '
              '어디로도 올리지 않습니다.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _accessLabel(GalleryAccess? access) {
    switch (access) {
      case GalleryAccess.granted:
        return '전체 허용';
      case GalleryAccess.limited:
        return '일부 사진만 허용';
      case GalleryAccess.denied:
        return '거부됨 — 눌러서 설정 열기';
      case GalleryAccess.unknown:
      case null:
        return '확인되지 않음';
    }
  }

  static String _updateLabel(UpdateState state) {
    switch (state.phase) {
      case UpdatePhase.idle:
        return '눌러서 새 버전이 있는지 확인합니다.';
      case UpdatePhase.checking:
        return '확인 중…';
      case UpdatePhase.upToDate:
        return '최신 버전입니다 (빌드 ${state.currentBuild}).';
      case UpdatePhase.available:
        return '새 버전 ${state.release?.buildNumber} 이 있습니다 '
            '(현재 ${state.currentBuild}).';
      case UpdatePhase.needsPermission:
        return '설치를 허용해야 합니다 — 아래 버튼으로 설정을 여세요.';
      case UpdatePhase.ready:
        return '설치 허용됨. 이제 내려받을 수 있습니다.';
      case UpdatePhase.downloading:
        return '받는 중 ${(state.progress * 100).toStringAsFixed(0)}%';
      case UpdatePhase.installing:
        return '설치 화면을 여는 중…';
      case UpdatePhase.error:
        return '확인 실패: ${state.error}';
    }
  }

  static String _syncLabel(SyncStatus status) {
    switch (status.phase) {
      case SyncPhase.idle:
        return '아직 동기화하지 않았습니다.';
      case SyncPhase.running:
        return '동기화 중…';
      case SyncPhase.done:
        final at = status.finishedAt;
        final result = status.result;
        final time = at == null ? '' : DateFormat('HH:mm').format(at);
        if (result == null || result.isEmpty) {
          return '$time 완료 — 바뀐 내용 없음';
        }
        return '$time 완료 — 받음 ${result.pulled}건, 보냄 ${result.pushed}건';
      case SyncPhase.error:
        return '실패: ${status.error}';
    }
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정말 전부 지울까요?'),
        content: const Text(
          '이 폰에 저장된 메모·태그·가상 폴더가 모두 사라집니다.\n'
          '사진 파일 자체는 아무 영향도 받지 않습니다.\n\n'
          '되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('전부 지우기'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;

    await ref.read(appDatabaseProvider).wipeUserData();
    ref.bumpDataRevision();
    await ref.read(indexingProvider.notifier).run();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

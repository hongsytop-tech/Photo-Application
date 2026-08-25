import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/core/theme/app_theme.dart';
import 'package:photo_application/features/auth/providers/auth_providers.dart';
import 'package:photo_application/features/gallery/providers/gallery_providers.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';
import 'package:photo_application/features/shell/main_shell.dart';
import 'package:photo_application/features/sync/providers/sync_providers.dart';
import 'package:photo_application/features/update/providers/update_providers.dart';

class PhotoApp extends ConsumerStatefulWidget {
  const PhotoApp({super.key});

  @override
  ConsumerState<PhotoApp> createState() => _PhotoAppState();
}

class _PhotoAppState extends ConsumerState<PhotoApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// 앱이 뜨자마자 할 일: 권한이 이미 있으면 갤러리를 훑고, 로그인되어 있으면
  /// 메타데이터를 맞춥니다. 권한이 없으면 아무것도 하지 않고 안내 화면에
  /// 맡깁니다 — 시작하자마자 권한 팝업을 띄우면 무슨 앱인지 모르는 채로
  /// 거절당하기 쉽습니다.
  Future<void> _bootstrap() async {
    final access = await ref.read(galleryServiceProvider).currentAccess();
    if (access == GalleryAccess.granted || access == GalleryAccess.limited) {
      await ref.read(indexingProvider.notifier).run();
    }
    if (!mounted) return;
    await ref.read(syncProvider.notifier).run();

    // 새 버전 확인은 맨 뒤에 둡니다. 사진 목록이 먼저 떠야 하고, 실패해도
    // 앱 사용에는 영향이 없어야 합니다.
    if (!mounted) return;
    await ref.read(updateProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    // 로그인 상태가 바뀌면 (로그인 직후) 한 번 맞춰 줍니다.
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user != null && previous?.valueOrNull == null) {
        ref.read(syncProvider.notifier).run();
      }
    });

    return MaterialApp(
      title: '사진 정리',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const MainShell(),
    );
  }
}

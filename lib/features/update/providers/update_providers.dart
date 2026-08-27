import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/features/update/models/app_release.dart';
import 'package:photo_application/features/update/services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>(
  (ref) => const UpdateService(),
);

enum UpdatePhase {
  /// 아직 확인 안 함.
  idle,
  checking,

  /// 최신 상태.
  upToDate,

  /// 새 버전이 있음.
  available,

  /// 설치 허용(자동 차단 해제)이 아직 안 됨 — 설정으로 보내야 하는 상태.
  needsPermission,

  /// 허용까지 끝나 이제 내려받기만 하면 되는 상태.
  ready,
  downloading,

  /// APK 가 기기에 있고 설치만 남은 상태. 설치가 막혀 돌아왔을 때도 여기로
  /// 되돌아옵니다 — 다시 받지 않고 다시 누를 수 있어야 합니다.
  readyToInstall,

  /// 방금 설치 화면을 띄운 상태. 잠깐 지나가는 단계입니다.
  installing,
  error,
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.currentBuild = 0,
    this.release,
    this.progress = 0,
    this.apk,
    this.installTried = false,
    this.error,
  });

  final UpdatePhase phase;
  final int currentBuild;
  final AppRelease? release;
  final double progress;

  /// 받아 둔 APK. 설치가 막혀도 버리지 않습니다.
  final File? apk;

  /// 설치 화면까지 갔다가 끝내지 못하고 돌아온 적이 있는지.
  ///
  /// 안내 문구를 가르는 데 씁니다. 처음이면 "설치하세요", 한 번 막혔으면
  /// "설치가 끝나지 않았습니다 — 허용한 뒤 다시".
  final bool installTried;

  final Object? error;

  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;

  /// 배너를 띄울지. 확인할 게 없으면 자리를 차지하지 않습니다.
  bool get shouldPrompt =>
      phase == UpdatePhase.available ||
      phase == UpdatePhase.needsPermission ||
      phase == UpdatePhase.ready ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.readyToInstall ||
      phase == UpdatePhase.installing;

  UpdateState copyWith({
    UpdatePhase? phase,
    int? currentBuild,
    AppRelease? release,
    double? progress,
    File? apk,
    bool? installTried,
    Object? error,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        currentBuild: currentBuild ?? this.currentBuild,
        release: release ?? this.release,
        progress: progress ?? this.progress,
        apk: apk ?? this.apk,
        installTried: installTried ?? this.installTried,
        error: error,
      );
}

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState()) {
    // 복귀 감지는 배너가 아니라 여기에 둡니다. 배너는 갤러리 탭에 있어서,
    // 다른 탭을 보는 중이거나 사진 뷰어를 열어 둔 채 설정에 다녀오면 그
    // 신호를 놓칩니다. 그러면 다시 멈춘 화면으로 돌아갑니다.
    _lifecycle = AppLifecycleListener(onResume: onResumed);
  }

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// 새 버전이 있는지 확인합니다. 조용히 실패합니다 — 업데이트 확인이
  /// 안 된다고 사용자를 방해할 이유는 없습니다.
  Future<void> check() async {
    if (state.busy) return;
    final service = _ref.read(updateServiceProvider);
    state = state.copyWith(phase: UpdatePhase.checking);
    try {
      final current = await service.currentBuildNumber();
      final latest = await service.fetchLatest();
      if (!mounted) return;

      // 조회 실패를 "최신"으로 뭉뚱그리면 안 됩니다. 업데이트가 오지 않는데
      // 화면에는 아무 문제 없어 보여서, 고장난 줄 모르고 지나가게 됩니다.
      if (latest == null) {
        state = UpdateState(
          phase: UpdatePhase.error,
          currentBuild: current,
          error: '릴리스 정보를 읽지 못했습니다. 잠시 후 다시 시도해 주세요.',
        );
        return;
      }

      if (latest.buildNumber <= current) {
        // 최신이라면 받아 둔 APK 는 이미 설치됐거나 쓸모가 없습니다.
        await service.cleanStaleApks();
        if (!mounted) return;
        state = UpdateState(phase: UpdatePhase.upToDate, currentBuild: current);
        return;
      }

      // 지난 릴리스의 APK 는 치우고 이번 것만 남깁니다.
      await service.cleanStaleApks(keep: latest);
      if (!mounted) return;
      state = UpdateState(
        phase: UpdatePhase.available,
        currentBuild: current,
        release: latest,
      );
    } catch (error, stack) {
      debugPrint('업데이트 확인 실패: $error\n$stack');
      if (mounted) state = UpdateState(phase: UpdatePhase.error, error: error);
    }
  }

  /// 업데이트 버튼. 내려받기 전에 설치 허용부터 받습니다.
  ///
  /// 안드로이드는 스토어를 거치지 않은 APK 설치를 앱별로 막아 둡니다.
  /// 갤럭시는 "자동 차단"이 한 겹 더 있어, 꺼 두지 않으면 다 받아 놓고
  /// 설치 화면에서 되돌려보내집니다. 몇십 MB 를 받은 뒤에야 막히면 왜
  /// 안 되는지 알기 어려우므로, 받기 전에 먼저 그 화면으로 보냅니다.
  Future<void> start() async {
    if (state.release == null || state.busy) return;

    final service = _ref.read(updateServiceProvider);
    final granted = await service.canInstallPackages();
    if (!mounted) return;

    if (granted) {
      await _afterPermission();
      return;
    }
    state = state.copyWith(phase: UpdatePhase.needsPermission);
    await openInstallSettings();
  }

  /// 허용이 끝난 뒤 어디로 갈지 정합니다.
  ///
  /// 이미 받아 둔 APK 가 있으면 내려받기를 건너뛰고 설치 단계로 바로 갑니다.
  /// 설치가 막혀 되돌아온 사람에게, 또는 앱을 껐다 켠 사람에게 같은 파일을
  /// 다시 받게 할 이유가 없습니다.
  Future<void> _afterPermission() async {
    final release = state.release;
    if (release == null) return;

    final service = _ref.read(updateServiceProvider);
    final cached = await service.cachedApk(release);
    if (!mounted) return;

    state = cached == null
        ? state.copyWith(phase: UpdatePhase.ready)
        : state.copyWith(phase: UpdatePhase.readyToInstall, apk: cached);
  }

  /// 설치 허용 화면을 열고, 돌아오면 다시 확인합니다.
  Future<void> openInstallSettings() async {
    if (state.release == null || state.busy) return;

    final service = _ref.read(updateServiceProvider);
    final granted = await service.requestInstallPermission();
    if (!mounted) return;

    if (granted) {
      await _afterPermission();
    } else {
      state = state.copyWith(phase: UpdatePhase.needsPermission);
    }
  }

  /// 앱으로 돌아왔을 때 상태를 되짚습니다.
  ///
  /// 여기가 없으면 두 가지가 막다른 길이 됩니다.
  /// * 시스템 설정 깊숙한 곳에서 자동 차단을 끄고 돌아왔는데 화면은 여전히
  ///   "아직 허용되지 않았습니다"인 경우.
  /// * 설치 화면이 보안 설정에 막혀 되돌아왔는데 화면이 "설치 화면을 여는
  ///   중…"에 멈춰, 앱을 껐다 켜서 처음부터 다시 하는 수밖에 없는 경우.
  Future<void> onResumed() async {
    final phase = state.phase;

    if (phase == UpdatePhase.needsPermission) {
      final service = _ref.read(updateServiceProvider);
      if (!await service.canInstallPackages()) return;
      if (!mounted || state.phase != UpdatePhase.needsPermission) return;
      await _afterPermission();
      return;
    }

    if (phase == UpdatePhase.installing) {
      // 설치가 끝났다면 이 앱은 새 버전으로 갈아치워지며 다시 시작합니다.
      // 그러니 여기로 돌아왔다는 것은 설치되지 않았다는 뜻입니다 — 보안
      // 설정에 막혔거나 사용자가 취소했거나. 받아 둔 파일은 그대로 두고
      // 다시 누를 수 있는 상태로 되돌립니다.
      state = state.copyWith(
        phase: UpdatePhase.readyToInstall,
        installTried: true,
      );
    }
  }

  /// 내려받고 이어서 설치 화면을 띄웁니다.
  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || state.busy) return;

    final service = _ref.read(updateServiceProvider);

    // 설정 화면에 다녀오는 사이 허용이 다시 꺼졌을 수 있습니다.
    if (!await service.canInstallPackages()) {
      if (!mounted) return;
      state = state.copyWith(phase: UpdatePhase.needsPermission);
      await openInstallSettings();
      return;
    }
    if (!mounted) return;

    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final file = await service.download(
        release,
        onProgress: (p) {
          if (mounted) state = state.copyWith(progress: p);
        },
      );
      if (!mounted) return;

      state = state.copyWith(
        phase: UpdatePhase.readyToInstall,
        apk: file,
        progress: 1,
      );
      await install();
    } catch (error, stack) {
      debugPrint('업데이트 내려받기 실패: $error\n$stack');
      if (mounted) {
        state = state.copyWith(phase: UpdatePhase.error, error: error);
      }
    }
  }

  /// 받아 둔 APK 로 설치 화면을 띄웁니다.
  ///
  /// 실패해도 [UpdatePhase.error] 로 보내지 않습니다. 오류 화면은 다시
  /// 누를 수단이 없어 앱을 껐다 켜는 수밖에 없는데, 정작 필요한 것은
  /// "허용하고 한 번 더"입니다.
  Future<void> install() async {
    final file = state.apk;
    if (file == null || state.busy) return;

    final service = _ref.read(updateServiceProvider);

    // 다시 누르는 경우, 그 사이 허용이 꺼졌을 수 있습니다.
    if (!await service.canInstallPackages()) {
      if (!mounted) return;
      state = state.copyWith(phase: UpdatePhase.needsPermission);
      await openInstallSettings();
      return;
    }
    if (!mounted) return;

    state = state.copyWith(phase: UpdatePhase.installing);
    try {
      final failure = await service.install(file);
      if (!mounted) return;
      if (failure != null) {
        state = state.copyWith(
          phase: UpdatePhase.readyToInstall,
          installTried: true,
          error: failure,
        );
      }
    } catch (error, stack) {
      debugPrint('설치 화면 열기 실패: $error\n$stack');
      if (mounted) {
        state = state.copyWith(
          phase: UpdatePhase.readyToInstall,
          installTried: true,
          error: error,
        );
      }
    }
  }

  /// 배너를 닫습니다 (이번 실행 동안만).
  void dismiss() => state = state.copyWith(phase: UpdatePhase.upToDate);
}

final updateProvider =
    StateNotifierProvider<UpdateController, UpdateState>(UpdateController.new);

import 'package:flutter/foundation.dart';
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
  downloading,

  /// 내려받기를 마치고 설치 화면을 띄운 상태.
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
    this.error,
  });

  final UpdatePhase phase;
  final int currentBuild;
  final AppRelease? release;
  final double progress;
  final Object? error;

  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;

  /// 배너를 띄울지. 새 버전이 있거나 받는 중일 때만.
  bool get shouldPrompt =>
      phase == UpdatePhase.available ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;

  UpdateState copyWith({
    UpdatePhase? phase,
    int? currentBuild,
    AppRelease? release,
    double? progress,
    Object? error,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        currentBuild: currentBuild ?? this.currentBuild,
        release: release ?? this.release,
        progress: progress ?? this.progress,
        error: error,
      );
}

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState());

  final Ref _ref;

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
        state = UpdateState(phase: UpdatePhase.upToDate, currentBuild: current);
        return;
      }
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

  /// 내려받고 설치 화면을 띄웁니다.
  Future<void> downloadAndInstall() async {
    final release = state.release;
    if (release == null || state.busy) return;

    final service = _ref.read(updateServiceProvider);
    state = state.copyWith(phase: UpdatePhase.downloading, progress: 0);
    try {
      final file = await service.download(
        release,
        onProgress: (p) {
          if (mounted) state = state.copyWith(progress: p);
        },
      );
      if (!mounted) return;

      state = state.copyWith(phase: UpdatePhase.installing, progress: 1);
      final failure = await service.install(file);
      if (!mounted) return;
      if (failure != null) {
        state = state.copyWith(phase: UpdatePhase.error, error: failure);
      }
    } catch (error, stack) {
      debugPrint('업데이트 설치 실패: $error\n$stack');
      if (mounted) {
        state = state.copyWith(phase: UpdatePhase.error, error: error);
      }
    }
  }

  /// 배너를 닫습니다 (이번 실행 동안만).
  void dismiss() => state = state.copyWith(phase: UpdatePhase.upToDate);
}

final updateProvider =
    StateNotifierProvider<UpdateController, UpdateState>(UpdateController.new);

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/sync/services/sync_remote.dart';
import 'package:photo_application/features/sync/services/sync_service.dart';

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(appDatabaseProvider), const SupabaseSyncRemote()),
);

enum SyncPhase { idle, running, done, error }

@immutable
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.result,
    this.error,
    this.finishedAt,
  });

  final SyncPhase phase;
  final SyncResult? result;
  final Object? error;
  final DateTime? finishedAt;

  bool get running => phase == SyncPhase.running;
}

class SyncController extends StateNotifier<SyncStatus> {
  SyncController(this._ref) : super(const SyncStatus());

  final Ref _ref;

  /// 동기화를 한 번 돕니다. 이미 돌고 있으면 무시합니다.
  Future<void> run() async {
    if (state.running) return;
    final service = _ref.read(syncServiceProvider);
    if (!service.canSync) return;

    state = const SyncStatus(phase: SyncPhase.running);
    try {
      final result = await service.sync();
      if (!mounted) return;
      state = SyncStatus(
        phase: SyncPhase.done,
        result: result,
        finishedAt: DateTime.now(),
      );
      // 서버에서 내려온 내용이 있으면 화면을 다시 그려야 합니다.
      if (result.pulled > 0) _ref.bumpDataRevisionFromSync();
    } catch (error, stack) {
      debugPrint('동기화 실패: $error\n$stack');
      if (mounted) {
        state = SyncStatus(phase: SyncPhase.error, error: error);
      }
    }
  }

  /// 서버 내용을 처음부터 다시 받아옵니다.
  Future<void> resync() async {
    await _ref.read(syncServiceProvider).resetWatermark();
    await run();
  }
}

final syncProvider =
    StateNotifierProvider<SyncController, SyncStatus>(SyncController.new);

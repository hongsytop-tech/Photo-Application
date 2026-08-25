import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';
import 'package:photo_application/features/sync/providers/sync_providers.dart';

/// 자동 동기화 켬/끔 설정. 기본값은 켬입니다.
class AutoSyncEnabled extends StateNotifier<bool> {
  AutoSyncEnabled(Ref ref)
      : _ref = ref,
        super(ref.read(localStorageProvider).getBool(_key, fallback: true));

  static const _key = 'auto_sync_enabled';

  final Ref _ref;

  Future<void> set(bool value) async {
    state = value;
    await _ref.read(localStorageProvider).setBool(_key, value);
  }
}

final autoSyncEnabledProvider =
    StateNotifierProvider<AutoSyncEnabled, bool>(AutoSyncEnabled.new);

/// 사용자가 무언가 바꾸면 알아서 동기화합니다.
///
/// 세 가지 계기를 봅니다.
/// * **편집** — 메모·태그·폴더가 바뀌면 [_idle] 만큼 조용해진 뒤 한 번 올립니다.
///   글자 하나 칠 때마다 네트워크를 치지 않게 마지막 변경 기준으로 미룹니다.
/// * **복귀** — 앱을 다시 열면 그 사이 다른 기기가 올린 것을 받아옵니다.
///   방금 맞췄으면 [_resumeCooldown] 동안은 건너뜁니다.
/// * (앱을 처음 켤 때와 로그인 직후는 `PhotoApp` 이 이미 한 번 돌립니다.)
///
/// 자동으로 돌더라도 설정 화면의 '지금 동기화'는 그대로 둡니다. 자동이 언제
/// 돌았는지 확인하고, 못 기다릴 때 손으로 당길 수단이 필요합니다.
class AutoSync {
  AutoSync(this._ref) {
    _ref.listen<int>(localEditRevisionProvider, (_, __) => _schedule());
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  static const _idle = Duration(seconds: 4);
  static const _resumeCooldown = Duration(minutes: 1);

  final Ref _ref;
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;

  bool get _enabled => _ref.read(autoSyncEnabledProvider);

  void _schedule() {
    if (!_enabled) return;
    _timer?.cancel();
    _timer = Timer(_idle, _run);
  }

  void _onResume() {
    if (!_enabled) return;
    final last = _ref.read(syncProvider).finishedAt;
    if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
      return;
    }
    _ref.read(syncProvider.notifier).run();
  }

  Future<void> _run() async {
    if (!_enabled) return;
    // 손으로 누른 동기화가 돌고 있으면 비켜 줍니다. 이번 변경은 다음 차례에.
    if (_ref.read(syncProvider).running) {
      _schedule();
      return;
    }

    final before = _ref.read(localEditRevisionProvider);
    await _ref.read(syncProvider.notifier).run();
    // 올리는 동안 또 고쳤다면 그 변경은 이번에 못 올라갔습니다.
    if (_ref.read(localEditRevisionProvider) != before) _schedule();
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
  }
}

/// `PhotoApp` 에서 watch 해야 실제로 만들어집니다 — provider 는 게으릅니다.
final autoSyncProvider = Provider<AutoSync>((ref) {
  final autoSync = AutoSync(ref);
  ref.onDispose(autoSync.dispose);
  return autoSync;
});

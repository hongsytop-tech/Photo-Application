import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/providers/core_providers.dart';

/// 그리드 한 줄에 몇 장을 놓을지. 손가락으로 벌리고 오므려 바꿉니다.
///
/// 화면에 남는 값이라 앱을 다시 열어도 유지합니다 — 매번 다시 맞추게 하면
/// 조절 기능이 있으나 마나입니다.
class GridColumns extends StateNotifier<int> {
  GridColumns(Ref ref)
      : _ref = ref,
        super(_restore(ref));

  static const minColumns = 2;
  static const maxColumns = 8;
  static const _key = 'grid_columns';
  static const _fallback = 3;

  final Ref _ref;

  static int _restore(Ref ref) {
    return _bounded(ref.read(localStorageProvider).getInt(_key) ?? _fallback);
  }

  /// clamp 대신 직접 자릅니다. num.clamp 는 정수만 넣어도 정적 타입이 num 이
  /// 되는 경우가 있어, 컴파일러 없이 고치는 이 저장소에서는 위험을 지웁니다.
  static int _bounded(int value) {
    if (value < minColumns) return minColumns;
    if (value > maxColumns) return maxColumns;
    return value;
  }

  /// 손가락을 벌리면 사진이 커집니다 = 한 줄에 들어가는 수가 줄어듭니다.
  void zoomIn() => setColumns(state - 1);

  void zoomOut() => setColumns(state + 1);

  void setColumns(int value) {
    final next = _bounded(value);
    if (next == state) return;
    state = next;
    _ref.read(localStorageProvider).setInt(_key, next);
  }
}

final gridColumnsProvider =
    StateNotifierProvider<GridColumns, int>(GridColumns.new);

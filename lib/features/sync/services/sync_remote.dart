import 'package:photo_application/core/supabase/supabase_service.dart';

/// 동기화가 서버와 주고받는 최소한의 창구.
///
/// [SyncService] 가 Supabase 를 직접 부르지 않고 이 인터페이스만 보도록 갈라
/// 두었습니다. 병합 규칙(무엇이 이기고, 지운 것을 어떻게 남기는지)은 이 앱에서
/// 가장 조용히 틀리기 쉬운 부분이라, 네트워크 없이 테스트에서 두 기기를 흉내 내
/// 검증할 수 있어야 합니다.
abstract class SyncRemote {
  /// 한 사용자의 테이블 내용을 전부 가져옵니다.
  Future<List<Map<String, dynamic>>> fetchAll(String table, String userId);

  /// 행들을 넣거나 덮어씁니다. [onConflict] 는 충돌 판정 기준 컬럼들입니다.
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  });
}

/// 실제 Supabase 구현.
class SupabaseSyncRemote implements SyncRemote {
  const SupabaseSyncRemote();

  @override
  Future<List<Map<String, dynamic>>> fetchAll(
    String table,
    String userId,
  ) async {
    final rows =
        await SupabaseService.client.from(table).select().eq('user_id', userId);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  }) async {
    if (rows.isEmpty) return;
    // 한 번에 너무 많이 보내면 요청이 거부될 수 있어 나눠 보냅니다.
    const chunkSize = 500;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = i + chunkSize > rows.length ? rows.length : i + chunkSize;
      await SupabaseService.client
          .from(table)
          .upsert(rows.sublist(i, end), onConflict: onConflict);
    }
  }
}

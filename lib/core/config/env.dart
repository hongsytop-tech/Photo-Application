import 'package:flutter_dotenv/flutter_dotenv.dart';

/// `.env` 에서 읽어오는 런타임 설정.
///
/// 모든 조회가 null 허용입니다. Supabase 자격증명이 없으면 앱은 **로컬 전용
/// 모드**로 정상 동작하고 로그인/동기화 기능만 비활성화됩니다. 사진 탐색·메모·
/// 태그·폴더는 백엔드 없이도 전부 동작해야 하기 때문입니다.
class Env {
  const Env._();

  static String? get supabaseUrl => _maybe('SUPABASE_URL');

  static String? get supabaseAnonKey => _maybe('SUPABASE_ANON_KEY');

  /// 두 자격증명이 모두 있을 때만 true.
  static bool get isSupabaseConfigured =>
      (supabaseUrl?.isNotEmpty ?? false) &&
      (supabaseAnonKey?.isNotEmpty ?? false);

  static String? _maybe(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.maybeGet(key)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:photo_application/core/supabase/supabase_service.dart';

/// 이메일/비밀번호 인증.
///
/// 이 앱에서 로그인은 **선택 사항**입니다. 로그인하지 않아도 사진 탐색·메모·
/// 태그·폴더가 전부 동작하고, 로그인은 그 메타데이터를 다른 기기와 맞추는
/// 용도로만 쓰입니다.
class AuthService {
  const AuthService();

  bool get isConfigured => SupabaseService.isConfigured;

  Stream<AuthState> get authStateChanges => SupabaseService.auth.onAuthStateChange;

  User? get currentUser => SupabaseService.currentUser;

  Future<void> signIn({required String email, required String password}) async {
    _ensureConfigured();
    await SupabaseService.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUp({required String email, required String password}) async {
    _ensureConfigured();
    await SupabaseService.auth.signUp(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() async {
    if (!SupabaseService.isConfigured) return;
    await SupabaseService.auth.signOut();
  }

  void _ensureConfigured() {
    if (!SupabaseService.isConfigured) {
      throw StateError(
        '백엔드가 설정되지 않았습니다. .env 에 SUPABASE_URL 과 '
        'SUPABASE_ANON_KEY 를 넣고 다시 빌드하세요.',
      );
    }
  }
}

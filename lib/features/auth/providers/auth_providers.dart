import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:photo_application/core/supabase/supabase_service.dart';
import 'package:photo_application/features/auth/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => const AuthService());

/// 현재 로그인한 사용자. 백엔드가 없으면 항상 null 을 흘립니다.
final authStateProvider = StreamProvider<User?>((ref) {
  if (!SupabaseService.isConfigured) {
    return Stream<User?>.value(null);
  }
  final auth = ref.watch(authServiceProvider);
  return auth.authStateChanges.map((event) => event.session?.user);
});

/// 로그인 여부 (동기 조회용).
final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).valueOrNull != null;
});

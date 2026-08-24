import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:photo_application/core/config/env.dart';

/// 전역 Supabase 클라이언트 래퍼.
///
/// 이 앱에서 Supabase 는 **메타데이터(메모·태그·폴더) 동기화 전용**입니다.
/// 사진 원본은 절대 업로드하지 않습니다.
///
/// 자격증명이 없으면 [isConfigured] 가 false 로 남고, 호출부는 이를 보고
/// 조용히 로컬 전용으로 동작합니다.
class SupabaseService {
  const SupabaseService._();

  static bool _initialized = false;

  static bool get isConfigured => _initialized;

  static Future<void> initialize() async {
    if (!Env.isSupabaseConfigured) {
      debugPrint(
        'Supabase 자격증명 없음 — 로컬 전용 모드로 실행합니다. '
        '사진/메모/태그/폴더는 모두 정상 동작하고 기기 간 동기화만 꺼집니다.',
      );
      return;
    }
    await Supabase.initialize(
      url: Env.supabaseUrl!,
      anonKey: Env.supabaseAnonKey!,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  static User? get currentUser => _initialized ? auth.currentUser : null;

  static bool get isAuthenticated => currentUser != null;
}

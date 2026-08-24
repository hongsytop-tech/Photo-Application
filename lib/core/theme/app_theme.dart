import 'package:flutter/material.dart';

/// 앱 테마.
///
/// 사진이 주인공이므로 UI 색은 최대한 물러섭니다. 특히 그리드와 뷰어의
/// 배경은 어느 테마에서든 어둡게 둬서 사진 가장자리가 배경에 묻히지 않게 합니다.
class AppTheme {
  const AppTheme._();

  static const _seed = Color(0xFF4C6EF5);

  /// 사진 그리드/뷰어의 바탕색. 밝은 테마에서도 사진 대비를 지키려고
  /// 별도로 둡니다.
  static const canvas = Color(0xFF101114);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: scheme.outlineVariant),
        showCheckmark: false,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

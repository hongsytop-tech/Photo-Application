import 'package:shared_preferences/shared_preferences.dart';

/// [SharedPreferences] 파사드 — **설정값 전용**입니다.
///
/// 사진 메타데이터(메모·태그·폴더)는 수만 건 규모라 SQLite(`AppDatabase`)가
/// 담당합니다. 여기에는 마지막 스캔 시각, 마지막 선택 탭처럼 작고 단일한
/// 값만 둡니다.
class LocalStorage {
  LocalStorage._(this._prefs);

  final SharedPreferences _prefs;

  static LocalStorage? _instance;

  static Future<LocalStorage> getInstance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    return _instance = LocalStorage._(prefs);
  }

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  int? getInt(String key) => _prefs.getInt(key);

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}

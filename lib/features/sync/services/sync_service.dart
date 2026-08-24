import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/core/supabase/supabase_service.dart';

/// 로컬 테이블 하나와 서버 테이블 하나를 짝지은 명세.
///
/// 여섯 개 테이블이 전부 같은 규칙(키 + 데이터 + updated_ms + deleted)을
/// 따르므로, 테이블마다 동기화 코드를 따로 쓰지 않고 이 명세로 일반화합니다.
class _TableSpec {
  const _TableSpec({
    required this.local,
    required this.remote,
    required this.keys,
    required this.data,
    this.pushFilter,
  });

  final String local;
  final String remote;

  /// 로컬 기본키를 이루는 컬럼들. 서버에서는 여기에 user_id 가 더해집니다.
  final List<String> keys;

  /// 키/메타(updated_ms, deleted)를 뺀 실제 내용 컬럼들.
  final List<String> data;

  /// 서버로 올릴 행을 더 좁히는 조건 (선택).
  final String? pushFilter;

  List<String> get allColumns => [...keys, ...data, 'updated_ms', 'deleted'];

  /// Supabase upsert 의 충돌 기준.
  String get onConflict => ['user_id', ...keys].join(',');
}

/// 동기화 결과.
class SyncResult {
  const SyncResult({this.pulled = 0, this.pushed = 0});

  final int pulled;
  final int pushed;

  bool get isEmpty => pulled == 0 && pushed == 0;
}

/// 메모·태그·폴더를 계정에 붙여 기기 간에 맞춥니다.
///
/// **사진 파일은 절대 오가지 않습니다.** 오가는 것은 사진을 가리키는 키와
/// 거기 붙은 글자뿐입니다.
///
/// 충돌은 마지막 수정 시각이 이기는(LWW) 방식으로 풉니다. 삭제도 행을 지우지
/// 않고 `deleted = 1` 로 남겨 두기 때문에, 한쪽에서 지운 항목이 다른 쪽의
/// 오래된 사본 때문에 되살아나지 않습니다.
class SyncService {
  SyncService(this._database);

  final AppDatabase _database;

  static const _pushWatermarkKey = 'last_push_ms';

  static const List<_TableSpec> _specs = [
    _TableSpec(
      local: 'notes',
      remote: 'photo_notes',
      keys: ['photo_key'],
      data: ['body'],
    ),
    _TableSpec(
      local: 'tags',
      remote: 'photo_tag_defs',
      keys: ['id'],
      data: ['name'],
    ),
    _TableSpec(
      local: 'photo_tags',
      remote: 'photo_tag_links',
      keys: ['photo_key', 'tag_id'],
      data: [],
    ),
    _TableSpec(
      local: 'folders',
      remote: 'photo_folders',
      keys: ['id'],
      data: ['name', 'sort_order'],
    ),
    _TableSpec(
      local: 'folder_items',
      remote: 'photo_folder_items',
      keys: ['folder_id', 'photo_key'],
      data: [],
    ),
    // 사진 신원 정보는 기기의 사진 수만큼(수만 건) 있을 수 있어 통째로 올리면
    // 안 됩니다. 실제로 메모·태그·폴더가 붙은 사진의 것만 올립니다.
    _TableSpec(
      local: 'photo_identity',
      remote: 'photo_identities',
      keys: ['photo_key'],
      data: ['file_name', 'created_ms', 'width', 'height'],
      pushFilter: '''
        photo_key IN (
          SELECT photo_key FROM notes WHERE deleted = 0
          UNION SELECT photo_key FROM photo_tags WHERE deleted = 0
          UNION SELECT photo_key FROM folder_items WHERE deleted = 0
        )
      ''',
    ),
  ];

  bool get canSync =>
      SupabaseService.isConfigured && SupabaseService.isAuthenticated;

  /// 내려받고 올려보냅니다. 로그인하지 않았으면 조용히 아무것도 하지 않습니다.
  Future<SyncResult> sync() async {
    if (!canSync) return const SyncResult();
    final userId = SupabaseService.currentUser!.id;

    // 내려받기를 먼저 합니다. 이 기기의 오래된 내용으로 다른 기기의 최신
    // 내용을 덮어쓰는 일을 막기 위해서입니다.
    final pulled = await _pullAll(userId);
    final pushed = await _pushAll(userId);

    debugPrint('동기화 완료: 내려받음 $pulled건, 올려보냄 $pushed건');
    return SyncResult(pulled: pulled, pushed: pushed);
  }

  // --- 내려받기 -----------------------------------------------------------

  Future<int> _pullAll(String userId) async {
    var applied = 0;
    for (final spec in _specs) {
      applied += await _pull(spec, userId);
    }
    return applied;
  }

  /// 서버 행을 전부 받아 로컬보다 새 것만 반영합니다.
  ///
  /// 워터마크로 일부만 받지 않는 이유는 기기마다 시계가 달라서입니다.
  /// 조금 뒤처진 시계를 가진 기기가 쓴 행은 워터마크 방식에서 영원히
  /// 건너뛰어질 수 있습니다. 메타데이터는 양이 작아 전부 받아도 부담이 없습니다.
  Future<int> _pull(_TableSpec spec, String userId) async {
    final rows = await SupabaseService.client
        .from(spec.remote)
        .select()
        .eq('user_id', userId);

    if (rows is! List || rows.isEmpty) return 0;

    var applied = 0;
    await _database.db.transaction((txn) async {
      for (final raw in rows) {
        if (raw is! Map) continue;
        final remote = raw.cast<String, dynamic>();

        final whereClause = spec.keys.map((k) => '$k = ?').join(' AND ');
        final whereArgs = spec.keys.map((k) => remote[k]).toList();

        final localRows = await txn.query(
          spec.local,
          columns: ['updated_ms'],
          where: whereClause,
          whereArgs: whereArgs,
          limit: 1,
        );

        final remoteUpdated = _asInt(remote['updated_ms']);
        if (localRows.isNotEmpty) {
          final localUpdated = _asInt(localRows.first['updated_ms']);
          // 같은 시각이면 그대로 둡니다. 굳이 다시 쓸 이유가 없습니다.
          if (localUpdated >= remoteUpdated) continue;
        }

        final values = <String, Object?>{
          for (final column in spec.allColumns)
            column: _normalize(column, remote[column]),
        };
        await txn.insert(
          spec.local,
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        applied++;
      }
    });
    return applied;
  }

  // --- 올려보내기 ---------------------------------------------------------

  Future<int> _pushAll(String userId) async {
    final watermark = await _readWatermark();
    // 올리기 시작한 시각을 기준으로 삼습니다. 올리는 도중에 생긴 변경이
    // 다음 회차에서 빠지지 않게 하려는 것입니다.
    final startedAt = DateTime.now().millisecondsSinceEpoch;

    var pushed = 0;
    for (final spec in _specs) {
      pushed += await _push(spec, userId, watermark);
    }

    await _writeWatermark(startedAt);
    return pushed;
  }

  Future<int> _push(_TableSpec spec, String userId, int watermark) async {
    final conditions = ['updated_ms > ?'];
    if (spec.pushFilter != null) conditions.add('(${spec.pushFilter})');

    final rows = await _database.db.query(
      spec.local,
      columns: spec.allColumns,
      where: conditions.join(' AND '),
      whereArgs: [watermark],
    );
    if (rows.isEmpty) return 0;

    final payload = rows
        .map((row) => <String, dynamic>{'user_id': userId, ...row})
        .toList();

    // 한 번에 너무 많이 보내면 요청이 거부될 수 있어 나눠 보냅니다.
    const chunkSize = 500;
    for (var i = 0; i < payload.length; i += chunkSize) {
      final chunk = payload.sublist(
        i,
        i + chunkSize > payload.length ? payload.length : i + chunkSize,
      );
      await SupabaseService.client
          .from(spec.remote)
          .upsert(chunk, onConflict: spec.onConflict);
    }
    return payload.length;
  }

  // --- 워터마크 -----------------------------------------------------------

  Future<int> _readWatermark() async {
    final rows = await _database.db.query(
      'sync_state',
      where: 'key = ?',
      whereArgs: [_pushWatermarkKey],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse((rows.first['value'] as String?) ?? '') ?? 0;
  }

  Future<void> _writeWatermark(int value) async {
    await _database.db.insert(
      'sync_state',
      {'key': _pushWatermarkKey, 'value': '$value'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 이 기기의 데이터를 서버에서 처음부터 다시 받아오도록 되돌립니다.
  Future<void> resetWatermark() => _writeWatermark(0);

  // --- 값 변환 -----------------------------------------------------------

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  /// Postgres 의 boolean/numeric 을 SQLite 가 받을 수 있는 형태로 맞춥니다.
  static Object? _normalize(String column, Object? value) {
    if (value == null) return null;
    if (column == 'deleted') {
      if (value is bool) return value ? 1 : 0;
      return _asInt(value);
    }
    if (column == 'updated_ms' ||
        column == 'created_ms' ||
        column == 'sort_order' ||
        column == 'width' ||
        column == 'height') {
      return _asInt(value);
    }
    return value;
  }
}

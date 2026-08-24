import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 앱 로컬 데이터베이스.
///
/// 설계 요지
/// - `photos` 는 기기 갤러리를 스캔한 **인덱스**입니다. asset id 가 기본키라
///   기기 내 사진 한 장당 한 행이고, 스캔 때마다 통째로 다시 채워집니다.
/// - 사용자가 만든 데이터(메모·태그·폴더)는 asset id 가 아니라 `photo_key`
///   (기기 간 안정 키)에 매답니다. 그래서 사진 인덱스를 지웠다 다시 만들어도,
///   심지어 사진이 잠시 사라졌다 돌아와도 메모가 살아남습니다.
/// - 사용자 데이터 테이블은 전부 `updated_ms` + `deleted` 를 가집니다.
///   삭제를 실제 DELETE 가 아니라 tombstone 으로 남겨야 기기 간 동기화에서
///   "한쪽에서 지운 항목이 다른 쪽에서 부활하는" 문제가 생기지 않습니다.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static AppDatabase? _instance;

  static const _fileName = 'photo_application.db';
  static const _version = 1;

  static Future<AppDatabase> getInstance() async {
    if (_instance != null) return _instance!;
    final dir = await getDatabasesPath();
    return _instance = await openAt(p.join(dir, _fileName));
  }

  /// 경로를 직접 지정해 엽니다. 테스트에서 in-memory DB 를 쓰기 위한 통로이며,
  /// 싱글톤을 건드리지 않습니다.
  static Future<AppDatabase> openAt(String path) async {
    final database = await openDatabase(
      path,
      version: _version,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return AppDatabase._(database);
  }

  static Future<void> _onConfigure(Database db) async {
    // 외래키는 켜지 않습니다. 메타데이터는 사진 인덱스보다 오래 살아남아야
    // 하므로(사진이 일시적으로 사라져도 메모 유지) 의도적으로 느슨하게 둡니다.
    //
    // journal_mode 는 값을 돌려주는 PRAGMA 라 execute 가 아니라 rawQuery 로
    // 실행합니다.
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  static Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final stmt in _schemaV1) {
      batch.execute(stmt);
    }
    await batch.commit(noResult: true);
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    // v1 이 최초 버전이라 아직 마이그레이션 경로가 없습니다.
    // 이후 스키마를 바꿀 때 여기에 from < N 분기를 추가하세요.
  }

  static const List<String> _schemaV1 = [
    // --- 기기 갤러리 인덱스 (스캔으로 재생성됨) ---------------------------
    '''
    CREATE TABLE photos (
      asset_id   TEXT PRIMARY KEY,
      photo_key  TEXT NOT NULL,
      file_name  TEXT NOT NULL DEFAULT '',
      created_ms INTEGER NOT NULL DEFAULT 0,
      width      INTEGER NOT NULL DEFAULT 0,
      height     INTEGER NOT NULL DEFAULT 0,
      seen_gen   INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX photos_created_idx ON photos (created_ms DESC)',
    'CREATE INDEX photos_key_idx ON photos (photo_key)',

    // --- 사진별 메모 (사진 1장 : 메모 1개) --------------------------------
    '''
    CREATE TABLE notes (
      photo_key  TEXT PRIMARY KEY,
      body       TEXT NOT NULL DEFAULT '',
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // --- 태그 사전 --------------------------------------------------------
    '''
    CREATE TABLE tags (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX tags_name_idx ON tags (name)',

    // --- 사진 ↔ 태그 (다대다) ---------------------------------------------
    '''
    CREATE TABLE photo_tags (
      photo_key  TEXT NOT NULL,
      tag_id     TEXT NOT NULL,
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (photo_key, tag_id)
    )
    ''',
    'CREATE INDEX photo_tags_tag_idx ON photo_tags (tag_id)',

    // --- 가상 폴더 --------------------------------------------------------
    '''
    CREATE TABLE folders (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // --- 사진 ↔ 가상 폴더 (다대다) ----------------------------------------
    // 한 사진이 여러 폴더에 들어갈 수 있게 했습니다. 한 곳에만 넣고 싶으면
    // 그냥 하나만 고르면 되므로, 단일 소속 모델의 상위 호환입니다.
    '''
    CREATE TABLE folder_items (
      folder_id  TEXT NOT NULL,
      photo_key  TEXT NOT NULL,
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (folder_id, photo_key)
    )
    ''',
    'CREATE INDEX folder_items_photo_idx ON folder_items (photo_key)',

    // --- 사진 신원 정보 ---------------------------------------------------
    // photo_key 를 만들어낸 원재료를 따로 보관합니다. 기기를 바꿨을 때
    // 서버에서 내려받은 메타데이터를 새 기기의 사진에 다시 붙이려면
    // 키만으로는 부족하고 "이 키가 어떤 파일이었는지"가 필요합니다.
    '''
    CREATE TABLE photo_identity (
      photo_key  TEXT PRIMARY KEY,
      file_name  TEXT NOT NULL DEFAULT '',
      created_ms INTEGER NOT NULL DEFAULT 0,
      width      INTEGER NOT NULL DEFAULT 0,
      height     INTEGER NOT NULL DEFAULT 0,
      updated_ms INTEGER NOT NULL DEFAULT 0,
      deleted    INTEGER NOT NULL DEFAULT 0
    )
    ''',

    // --- 동기화 상태 (마지막 pull 시각 등) --------------------------------
    '''
    CREATE TABLE sync_state (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL DEFAULT ''
    )
    ''',
  ];

  /// 로컬 사용자 데이터를 전부 지웁니다 (설정 화면의 초기화용).
  /// 사진 인덱스는 스캔으로 다시 만들어지므로 함께 비웁니다.
  Future<void> wipeUserData() async {
    await db.transaction((txn) async {
      for (final table in [
        'notes',
        'tags',
        'photo_tags',
        'folders',
        'folder_items',
        'photo_identity',
        'sync_state',
      ]) {
        await txn.delete(table);
      }
    });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/folders/services/folder_service.dart';
import 'package:photo_application/features/notes/services/note_service.dart';
import 'package:photo_application/features/sync/services/sync_remote.dart';
import 'package:photo_application/features/sync/services/sync_service.dart';
import 'package:photo_application/features/tags/services/tag_service.dart';

/// 네트워크 없이 서버를 흉내 내는 저장소.
///
/// 실제 Supabase 처럼 (user_id + 자연키) 로 행을 덮어씁니다. 두 "기기"가 같은
/// 인스턴스를 공유하게 해서 한쪽의 변경이 다른 쪽에 어떻게 도달하는지 봅니다.
class FakeRemote implements SyncRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};

  int get rowCount =>
      tables.values.fold(0, (sum, rows) => sum + rows.length);

  @override
  Future<List<Map<String, dynamic>>> fetchAll(String table, String userId) async {
    return (tables[table] ?? {})
        .values
        .where((row) => row['user_id'] == userId)
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  Future<void> upsert(
    String table,
    List<Map<String, dynamic>> rows, {
    required String onConflict,
  }) async {
    final keys = onConflict.split(',');
    final store = tables.putIfAbsent(table, () => {});
    for (final row in rows) {
      final id = keys.map((k) => '${row[k]}').join('|');
      store[id] = Map<String, dynamic>.from(row);
    }
  }
}

/// 한 대의 기기 — 자기 로컬 DB 와 서비스들을 들고 있습니다.
class Device {
  Device(this.db, this.remote)
      : notes = NoteService(db),
        tags = TagService(db),
        folders = FolderService(db),
        sync = SyncService(db, remote);

  final AppDatabase db;
  final FakeRemote remote;
  final NoteService notes;
  final TagService tags;
  final FolderService folders;
  final SyncService sync;

  /// 기기마다 **자기만의 데이터베이스 파일**을 씁니다.
  ///
  /// inMemoryDatabasePath(':memory:') 를 두 번 열면 안 됩니다. sqflite 는 열린
  /// DB 를 경로로 캐시해서 같은 인스턴스를 돌려주므로, 두 기기가 한 저장소를
  /// 공유하게 됩니다. 그러면 동기화를 거치지 않고도 데이터가 "도착"해 버려서
  /// 이 파일의 테스트가 전부 무의미해집니다.
  static Future<Device> create(FakeRemote remote, String dbPath) async =>
      Device(await AppDatabase.openAt(dbPath), remote);

  /// 갤러리 스캔이 넣었을 법한 사진 한 장.
  Future<void> addPhoto(String assetId, String photoKey) => db.db.insert('photos', {
        'asset_id': assetId,
        'photo_key': photoKey,
        'file_name': 'IMG.jpg',
        'created_ms': 1000,
        'width': 100,
        'height': 100,
        'seen_gen': 1,
      });

  Future<void> run() => sync.sync(asUserId: 'user-1');

  Future<void> close() => db.db.close();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory workDir;
  late FakeRemote remote;
  late Device a;
  late Device b;

  setUp(() async {
    workDir = await Directory.systemTemp.createTemp('photo_sync_test');
    remote = FakeRemote();
    a = await Device.create(remote, '${workDir.path}/device-a.db');
    b = await Device.create(remote, '${workDir.path}/device-b.db');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await workDir.delete(recursive: true);
  });

  test('두 기기의 로컬 저장소가 서로 분리되어 있다', () async {
    // 이 파일의 다른 모든 테스트가 이 전제 위에 서 있습니다. 분리가 깨지면
    // 동기화를 거치지 않고도 데이터가 보여서, 테스트가 통과해도 아무것도
    // 검증하지 못합니다. 실제로 한 번 그렇게 깨진 적이 있어 못을 박아 둡니다.
    await a.addPhoto('a1', 'k1');
    await a.notes.write('k1', 'A 에만 있는 메모');

    expect(await b.notes.read('k1'), isNull,
        reason: '두 기기가 같은 DB 를 공유하면 이 파일 전체가 무의미해집니다');
    expect(await b.tags.listAll(), isEmpty);
    expect(await b.folders.listAll(), isEmpty);
  });

  test('사진 원본은 서버로 올라가지 않는다', () async {
    await a.addPhoto('a1', 'k1');
    await a.notes.write('k1', '메모');
    await a.run();

    // photos 테이블에 해당하는 서버 테이블이 아예 없어야 합니다.
    expect(remote.tables.keys, isNot(contains('photos')));
    expect(remote.tables.keys, everyElement(startsWith('photo_')));
    expect(remote.tables['photo_notes'], isNotNull);
  });

  test('한쪽에서 쓴 메모가 다른 쪽에 도착한다', () async {
    await a.addPhoto('a1', 'k1');
    await b.addPhoto('b1', 'k1'); // 같은 사진, 기기별로 asset id 는 다름
    await a.notes.write('k1', '제주도에서');
    await a.run();

    expect(await b.notes.read('k1'), isNull);
    await b.run();
    expect((await b.notes.read('k1'))?.body, '제주도에서');
  });

  test('나중에 고친 쪽이 이긴다', () async {
    await a.addPhoto('a1', 'k1');
    await b.addPhoto('b1', 'k1');

    await a.notes.write('k1', '먼저 쓴 메모');
    await a.run();
    await b.run();

    // B 가 나중에 고침
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await b.notes.write('k1', '나중에 고친 메모');
    await b.run();
    await a.run();

    expect((await a.notes.read('k1'))?.body, '나중에 고친 메모');
    expect((await b.notes.read('k1'))?.body, '나중에 고친 메모');
  });

  test('한쪽에서 지운 메모가 다른 쪽의 오래된 사본 때문에 되살아나지 않는다', () async {
    await a.addPhoto('a1', 'k1');
    await b.addPhoto('b1', 'k1');

    await a.notes.write('k1', '지워질 메모');
    await a.run();
    await b.run();
    expect((await b.notes.read('k1'))?.body, '지워질 메모');

    // A 에서 삭제
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await a.notes.delete('k1');
    await a.run();

    // B 가 동기화하면 삭제가 반영되어야 합니다.
    await b.run();
    expect(await b.notes.read('k1'), isNull);

    // 그리고 B 가 다시 올려도 A 에서 되살아나면 안 됩니다.
    await b.run();
    await a.run();
    expect(await a.notes.read('k1'), isNull);
  });

  test('태그와 폴더도 함께 건너간다', () async {
    await a.addPhoto('a1', 'k1');
    await b.addPhoto('b1', 'k1');

    final tag = await a.tags.ensure('바다');
    await a.tags.attach('k1', tag.id);
    final folder = await a.folders.create('여행');
    await a.folders.add(folder.id, 'k1');
    await a.run();
    await b.run();

    expect((await b.tags.tagsOf('k1')).map((t) => t.name), ['바다']);
    expect((await b.folders.listAll()).single.name, '여행');
    expect(await b.folders.countUnassigned(), 0);
  });

  test('두 기기가 따로 만든 같은 이름 태그는 하나로 합쳐진다', () async {
    await a.addPhoto('a1', 'k1');
    await b.addPhoto('b1', 'k2');

    // 서로 모르는 채 각자 "바다" 를 만듦 → id 가 다름
    final tagA = await a.tags.ensure('바다');
    await a.tags.attach('k1', tagA.id);
    final tagB = await b.tags.ensure('바다');
    await b.tags.attach('k2', tagB.id);
    expect(tagA.id, isNot(tagB.id));

    await a.run();
    await b.run();
    await a.run();
    await b.run();

    // 양쪽 모두 "바다" 가 하나만 남고, 두 사진 모두 그 태그를 가져야 합니다.
    for (final device in [a, b]) {
      final names = (await device.tags.listAll()).map((t) => t.name).toList();
      expect(names, ['바다'], reason: '기기마다 태그 목록이 달라지면 안 됩니다');
      expect((await device.tags.tagsOf('k1')).length, 1);
      expect((await device.tags.tagsOf('k2')).length, 1);
    }

    // 두 기기가 고른 승자가 같아야 합니다 (다르면 영원히 서로 밀어냅니다).
    expect(
      (await a.tags.listAll()).single.id,
      (await b.tags.listAll()).single.id,
    );
  });

  test('태그 분류가 다른 기기에 그대로 도착한다', () async {
    await a.addPhoto('a1', 'k1');
    final people = await a.tags.ensureGroup('인물');
    final mom = await a.tags.ensure('엄마', groupId: people.id);
    await a.tags.attach('k1', mom.id);

    await a.run();
    await b.run();

    final groups = await b.tags.listGroups();
    expect(groups.single.name, '인물');
    expect((await b.tags.listAll()).single.groupId, groups.single.id);
  });

  test('한쪽에서 지운 분류가 다른 쪽에서 되살아나지 않는다', () async {
    final people = await a.tags.ensureGroup('인물');
    await a.tags.ensure('엄마', groupId: people.id);
    await a.run();
    await b.run();
    expect((await b.tags.listGroups()).length, 1);

    await a.tags.deleteGroup(people.id);
    await a.run();
    await b.run();

    expect(await b.tags.listGroups(), isEmpty);
    // 분류만 사라지고 태그는 남아야 합니다.
    final tags = await b.tags.listAll();
    expect(tags.single.name, '엄마');
    expect(tags.single.groupId, isEmpty);
  });

  test('합쳐지는 태그의 분류를 잃지 않는다', () async {
    // A 는 분류까지 정리해 두었고, B 는 같은 이름을 아무 분류 없이 만들었다.
    final people = await a.tags.ensureGroup('인물');
    await a.tags.ensure('엄마', groupId: people.id);
    await b.tags.ensure('엄마');

    await a.run();
    await b.run();
    await a.run();
    await b.run();

    for (final device in [a, b]) {
      final tags = await device.tags.listAll();
      expect(tags.length, 1);
      expect(
        tags.single.groupId,
        isNotEmpty,
        reason: '병합만으로 분류가 사라지면 안 됩니다',
      );
      expect((await device.tags.listGroups()).single.name, '인물');
    }
  });

  test('서버가 아직 모르는 칸이 비어 와도 동기화가 멈추지 않는다', () async {
    // 마이그레이션을 아직 돌리지 않은 서버는 group_id 를 돌려주지 않습니다.
    // 그 값을 그대로 쓰면 NOT NULL 에 걸려 pull 전체가 뒤집힙니다.
    remote.tables['photo_tag_defs'] = {
      'user-1|t1': {
        'user_id': 'user-1',
        'id': 't1',
        'name': '바다',
        'updated_ms': 100,
        'deleted': 0,
      },
    };

    await b.run();

    final tags = await b.tags.listAll();
    expect(tags.single.name, '바다');
    expect(tags.single.groupId, isEmpty, reason: '기본값이 들어가야 한다');
  });

  test('바뀐 것이 없으면 다시 올려보내지 않는다', () async {
    await a.addPhoto('a1', 'k1');
    await a.notes.write('k1', '메모');

    final first = await a.sync.sync(asUserId: 'user-1');
    expect(first.pushed, greaterThan(0));

    final second = await a.sync.sync(asUserId: 'user-1');
    expect(second.pushed, 0, reason: '워터마크가 동작해야 합니다');
  });

  test('메타데이터가 붙은 사진의 신원 정보만 올라간다', () async {
    // 사진 3장 중 1장에만 메모를 붙입니다.
    for (var i = 0; i < 3; i++) {
      await a.addPhoto('a$i', 'k$i');
      await a.db.db.insert('photo_identity', {
        'photo_key': 'k$i',
        'file_name': 'IMG_$i.jpg',
        'created_ms': 1000 + i,
        'width': 100,
        'height': 100,
        'updated_ms': 1,
        'deleted': 0,
      });
    }
    await a.notes.write('k1', '메모');
    await a.run();

    final identities = await remote.fetchAll('photo_identities', 'user-1');
    expect(identities.map((r) => r['photo_key']), ['k1'],
        reason: '기기의 사진 전부를 올리면 수만 건이 됩니다');
  });

  test('나중에 메모가 붙은 사진의 신원 정보도 결국 올라간다', () async {
    // 실제 순서를 그대로 따라간다:
    //   1) 앱 시작 → 스캔이 photo_identity 를 만든다 (그때 시각으로)
    //   2) 첫 동기화 → 올릴 메타데이터가 없어 아무것도 안 올라간다
    //   3) 나중에 사용자가 메모를 쓴다
    //   4) 다음 동기화 → 메모와 함께 그 사진의 신원 정보도 올라가야 한다
    //
    // 워터마크는 "지난 동기화 이후 바뀐 행"만 올린다. 신원 정보는 스캔
    // 이후 값이 그대로라 바뀐 적이 없고, 그래서 영원히 빠진다. 올라갈
    // 자격이 생겼는데 값이 안 바뀌는 종류의 행은 워터마크로 못 잡는다.
    await a.addPhoto('a1', 'k1');
    await a.db.db.insert('photo_identity', {
      'photo_key': 'k1',
      'file_name': 'IMG_1.jpg',
      'created_ms': 1000,
      'width': 100,
      'height': 100,
      'updated_ms': 1, // 스캔 시각 — 아주 오래전
      'deleted': 0,
    });

    await a.run(); // 첫 동기화: 메타데이터가 없으니 신원 정보도 안 올라감
    expect(await remote.fetchAll('photo_identities', 'user-1'), isEmpty);

    await a.notes.write('k1', '나중에 쓴 메모');
    await a.run();

    expect(
      (await remote.fetchAll('photo_notes', 'user-1')).map((r) => r['photo_key']),
      ['k1'],
    );
    expect(
      (await remote.fetchAll('photo_identities', 'user-1')).map((r) => r['photo_key']),
      ['k1'],
      reason: '메모만 올라가고 신원 정보가 빠지면 기기를 바꿨을 때 재매칭 단서가 없다',
    );
  });

  test('로그아웃 상태에서는 아무것도 하지 않는다', () async {
    await a.addPhoto('a1', 'k1');
    await a.notes.write('k1', '메모');

    final result = await a.sync.sync(); // asUserId 없음 = 로그인 안 됨
    expect(result.isEmpty, isTrue);
    expect(remote.rowCount, 0);
  });
}

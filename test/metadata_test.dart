import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/folders/services/folder_service.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/notes/services/note_service.dart';
import 'package:photo_application/features/tags/services/tag_service.dart';

/// 데이터 계층을 실제 SQLite 위에서 돌려 본다.
///
/// 이 앱의 어려운 부분은 위젯이 아니라 "사진 인덱스와 사용자 데이터를 어떻게
/// 이어 붙이는가"라서, 그 지점을 직접 검증한다.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late NoteService notes;
  late TagService tags;
  late FolderService folders;
  late PhotoQueryService photos;

  /// 갤러리 스캔이 넣었을 법한 행을 직접 만든다.
  Future<void> addPhoto(
    String assetId,
    String photoKey, {
    String fileName = 'IMG.jpg',
    int createdMs = 1000,
  }) =>
      db.db.insert('photos', {
        'asset_id': assetId,
        'photo_key': photoKey,
        'file_name': fileName,
        'created_ms': createdMs,
        'width': 100,
        'height': 100,
        'seen_gen': 1,
      });

  Future<List<String>> idsOf(PhotoQuery query) async {
    final page = await photos.page(query, limit: 100, offset: 0);
    return page.map((p) => p.assetId).toList();
  }

  setUp(() async {
    db = await AppDatabase.openAt(inMemoryDatabasePath);
    notes = NoteService(db);
    tags = TagService(db);
    folders = FolderService(db);
    photos = PhotoQueryService(db);
  });

  tearDown(() => db.db.close());

  group('메모', () {
    test('쓰고 읽는다', () async {
      await addPhoto('a1', 'k1');
      await notes.write('k1', '제주도에서 찍음');
      expect((await notes.read('k1'))?.body, '제주도에서 찍음');
    });

    test('빈 메모는 없는 것으로 취급하되 행은 tombstone 으로 남는다', () async {
      await addPhoto('a1', 'k1');
      await notes.write('k1', '내용');
      await notes.write('k1', '   ');

      expect(await notes.read('k1'), isNull);
      // 실제 DELETE 가 아니어야 다른 기기에서 되살아나지 않는다.
      final rows = await db.db.query('notes', where: 'photo_key = ?', whereArgs: ['k1']);
      expect(rows.single['deleted'], 1);
    });

    test('사진이 인덱스에서 사라져도 메모는 남는다', () async {
      await addPhoto('a1', 'k1');
      await notes.write('k1', '살아남아야 함');

      // 스캔에서 사진이 사라진 상황 (SD 카드 분리 등)
      await db.db.delete('photos');
      expect((await notes.read('k1'))?.body, '살아남아야 함');

      // 사진이 돌아오면 같은 키로 다시 붙는다
      await addPhoto('a99', 'k1');
      expect(await idsOf(const PhotoQuery(scope: PhotoScope.withNote)), ['a99']);
    });

    test('기기에 없는 사진의 메모는 개수에 세지 않는다', () async {
      await addPhoto('a1', 'k1');
      await notes.write('k1', '있는 사진');
      await notes.write('k_ghost', '없는 사진');
      expect(await notes.countPhotosWithNote(), 1);
    });
  });

  group('태그', () {
    test('같은 이름은 대소문자가 달라도 하나로 합쳐진다', () async {
      final a = await tags.ensure('Beach');
      final b = await tags.ensure('beach');
      expect(a.id, b.id);
      expect((await tags.listAll()).length, 1);
    });

    test('지웠던 이름을 다시 쓰면 되살아난다', () async {
      final first = await tags.ensure('바다');
      await tags.delete(first.id);
      expect(await tags.listAll(), isEmpty);

      final again = await tags.ensure('바다');
      expect(again.id, first.id);
      expect((await tags.listAll()).single.name, '바다');
    });

    test('사진 수는 기기에 실제로 있는 사진만 센다', () async {
      await addPhoto('a1', 'k1');
      final tag = await tags.ensure('바다');
      await tags.attach('k1', tag.id);
      await tags.attach('k_ghost', tag.id);

      expect((await tags.listAll()).single.photoCount, 1);
    });

    test('태그를 지우면 사진에서 떨어지지만 사진은 남는다', () async {
      await addPhoto('a1', 'k1');
      final tag = await tags.ensure('바다');
      await tags.attach('k1', tag.id);

      await tags.delete(tag.id);
      expect(await tags.tagsOf('k1'), isEmpty);
      expect(await idsOf(const PhotoQuery()), ['a1']);
    });

    test('여러 태그를 모두 가진 사진만 좁혀 볼 수 있다', () async {
      await addPhoto('a1', 'k1', createdMs: 3000);
      await addPhoto('a2', 'k2', createdMs: 2000);
      final sea = await tags.ensure('바다');
      final trip = await tags.ensure('여행');

      await tags.attach('k1', sea.id);
      await tags.attach('k1', trip.id);
      await tags.attach('k2', sea.id);

      expect(
        await idsOf(PhotoQuery(scope: PhotoScope.tag, tagIds: [sea.id])),
        ['a1', 'a2'],
      );
      expect(
        await idsOf(PhotoQuery(scope: PhotoScope.tag, tagIds: [sea.id, trip.id])),
        ['a1'],
      );
    });

    test('태그가 여러 개 달려도 목록에 사진이 중복으로 나오지 않는다', () async {
      await addPhoto('a1', 'k1');
      for (final name in ['하나', '둘', '셋']) {
        await tags.attach('k1', (await tags.ensure(name)).id);
      }
      expect(await idsOf(const PhotoQuery(scope: PhotoScope.tagged)), ['a1']);
    });
  });

  group('가상 폴더', () {
    test('폴더에 넣지 않은 사진이 미지정으로 잡힌다', () async {
      await addPhoto('a1', 'k1', createdMs: 2000);
      await addPhoto('a2', 'k2', createdMs: 1000);
      final folder = await folders.create('여행');
      await folders.add(folder.id, 'k1');

      expect(await folders.countUnassigned(), 1);
      expect(await idsOf(const PhotoQuery(scope: PhotoScope.unassigned)), ['a2']);
      expect(
        await idsOf(PhotoQuery(scope: PhotoScope.folder, folderId: folder.id)),
        ['a1'],
      );
    });

    test('폴더를 지워도 사진은 남고 미지정으로 돌아간다', () async {
      await addPhoto('a1', 'k1');
      final folder = await folders.create('여행');
      await folders.add(folder.id, 'k1');
      expect(await folders.countUnassigned(), 0);

      await folders.delete(folder.id);
      expect(await folders.listAll(), isEmpty);
      expect(await idsOf(const PhotoQuery()), ['a1']);
      expect(await folders.countUnassigned(), 1);
    });

    test('한 사진이 여러 폴더에 들어갈 수 있다', () async {
      await addPhoto('a1', 'k1');
      final trip = await folders.create('여행');
      final family = await folders.create('가족');
      await folders.setFoldersOf('k1', {trip.id, family.id});

      expect(await folders.folderIdsOf('k1'), {trip.id, family.id});
      expect(await folders.countUnassigned(), 0);
    });

    test('setFoldersOf 는 빠진 폴더에서 사진을 빼낸다', () async {
      await addPhoto('a1', 'k1');
      final trip = await folders.create('여행');
      final family = await folders.create('가족');
      await folders.setFoldersOf('k1', {trip.id, family.id});

      await folders.setFoldersOf('k1', {family.id});
      expect(await folders.folderIdsOf('k1'), {family.id});
      expect(
        await idsOf(PhotoQuery(scope: PhotoScope.folder, folderId: trip.id)),
        isEmpty,
      );
    });
  });

  group('검색', () {
    test('파일명과 메모 양쪽을 본다', () async {
      await addPhoto('a1', 'k1', fileName: '바다.jpg', createdMs: 2000);
      await addPhoto('a2', 'k2', fileName: 'IMG_2.jpg', createdMs: 1000);
      await notes.write('k2', '바다에서 찍은 사진');

      expect(await idsOf(const PhotoQuery(keyword: '바다')), ['a1', 'a2']);
    });

    test('검색어의 % 와 _ 가 와일드카드로 새지 않는다', () async {
      await addPhoto('a1', 'k1', fileName: 'IMG_2.jpg', createdMs: 2000);
      await addPhoto('a2', 'k2', fileName: 'IMGX.jpg', createdMs: 1000);

      // '_' 를 이스케이프하지 않으면 IMGX.jpg 까지 걸린다.
      expect(await idsOf(const PhotoQuery(keyword: 'IMG_')), ['a1']);
      // '%' 를 이스케이프하지 않으면 전부 걸린다.
      expect(await idsOf(const PhotoQuery(keyword: '%')), isEmpty);
    });
  });

  group('동일 사진의 복사본', () {
    test('둘 다 목록에 보이고 메모는 공유한다', () async {
      // 같은 파일을 복사하면 파일명·촬영시각·해상도가 같아 키가 겹친다.
      await addPhoto('a1', 'k1', createdMs: 2000);
      await addPhoto('a2', 'k1', createdMs: 2000);
      await notes.write('k1', '공유되는 메모');

      // 목록에서 사라지지 않는다 (사진 목록은 asset 단위)
      expect((await idsOf(const PhotoQuery())).length, 2);
      expect(await idsOf(const PhotoQuery(scope: PhotoScope.withNote)), hasLength(2));
    });
  });

  group('페이지 나누기', () {
    test('offset 으로 이어 읽으면 중복도 누락도 없다', () async {
      for (var i = 0; i < 25; i++) {
        await addPhoto('a$i', 'k$i', createdMs: 1000 + i);
      }
      final first = await photos.page(const PhotoQuery(), limit: 10, offset: 0);
      final second = await photos.page(const PhotoQuery(), limit: 10, offset: 10);
      final third = await photos.page(const PhotoQuery(), limit: 10, offset: 20);

      final all = [...first, ...second, ...third].map((p) => p.assetId).toList();
      expect(all.toSet(), hasLength(25));
      expect(await photos.count(const PhotoQuery()), 25);
      // 최신순 정렬
      expect(all.first, 'a24');
      expect(all.last, 'a0');
    });
  });
}

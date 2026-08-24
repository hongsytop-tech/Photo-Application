import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';

/// 가상 폴더와 사진↔폴더 소속을 관리합니다.
class FolderService {
  FolderService(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<List<PhotoFolder>> listAll() async {
    final rows = await _database.db.rawQuery('''
      SELECT f.id, f.name, f.sort_order,
             (SELECT COUNT(DISTINCT p.asset_id)
                FROM folder_items fi
                JOIN photos p ON p.photo_key = fi.photo_key
               WHERE fi.folder_id = f.id AND fi.deleted = 0) AS photo_count
        FROM folders f
       WHERE f.deleted = 0
       ORDER BY f.sort_order ASC, f.name COLLATE NOCASE ASC
    ''');
    return rows.map(PhotoFolder.fromRow).toList();
  }

  /// 어떤 가상 폴더에도 넣지 않은 사진 수 — 홈의 "미지정" 칸에 씁니다.
  Future<int> countUnassigned() async {
    final rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM photos p WHERE NOT EXISTS '
      '(SELECT 1 FROM folder_items fi WHERE fi.photo_key = p.photo_key AND fi.deleted = 0)',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 사진 한 장이 속한 폴더 id 들.
  Future<Set<String>> folderIdsOf(String photoKey) async {
    final rows = await _database.db.query(
      'folder_items',
      columns: ['folder_id'],
      where: 'photo_key = ? AND deleted = 0',
      whereArgs: [photoKey],
    );
    return rows.map((r) => r['folder_id'] as String).toSet();
  }

  Future<PhotoFolder> create(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('폴더 이름이 비어 있습니다.');
    }
    final maxRows = await _database.db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM folders WHERE deleted = 0',
    );
    final nextOrder = ((maxRows.first['m'] as int?) ?? -1) + 1;

    final id = _uuid.v4();
    await _database.db.insert('folders', {
      'id': id,
      'name': name,
      'sort_order': nextOrder,
      'updated_ms': _now,
      'deleted': 0,
    });
    return PhotoFolder(id: id, name: name, sortOrder: nextOrder);
  }

  Future<void> rename(String folderId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    await _database.db.update(
      'folders',
      {'name': name, 'updated_ms': _now},
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  /// 폴더를 지웁니다. **사진은 지워지지 않습니다** — 소속만 풀려서 해당
  /// 사진들이 "미지정"으로 돌아갑니다.
  Future<void> delete(String folderId) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      await txn.update(
        'folders',
        {'deleted': 1, 'updated_ms': now},
        where: 'id = ?',
        whereArgs: [folderId],
      );
      await txn.update(
        'folder_items',
        {'deleted': 1, 'updated_ms': now},
        where: 'folder_id = ?',
        whereArgs: [folderId],
      );
    });
  }

  Future<void> reorder(List<String> orderedIds) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.update(
          'folders',
          {'sort_order': i, 'updated_ms': now},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
    });
  }

  Future<void> add(String folderId, String photoKey) =>
      addMany(folderId, [photoKey]);

  Future<void> remove(String folderId, String photoKey) =>
      removeMany(folderId, [photoKey]);

  Future<void> addMany(String folderId, Iterable<String> photoKeys) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      final batch = txn.batch();
      for (final key in photoKeys) {
        batch.insert(
          'folder_items',
          {
            'folder_id': folderId,
            'photo_key': key,
            'updated_ms': now,
            'deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> removeMany(String folderId, Iterable<String> photoKeys) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      final batch = txn.batch();
      for (final key in photoKeys) {
        batch.insert(
          'folder_items',
          {
            'folder_id': folderId,
            'photo_key': key,
            'updated_ms': now,
            'deleted': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 사진 한 장의 소속 폴더를 통째로 교체합니다 (폴더 선택 시트의 저장 동작).
  Future<void> setFoldersOf(String photoKey, Set<String> folderIds) async {
    final current = await folderIdsOf(photoKey);
    final toAdd = folderIds.difference(current);
    final toRemove = current.difference(folderIds);
    for (final id in toAdd) {
      await add(id, photoKey);
    }
    for (final id in toRemove) {
      await remove(id, photoKey);
    }
  }
}

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/folders/models/photo_folder.dart';

/// 가상 폴더(트리)와 사진↔폴더 소속을 관리합니다.
class FolderService {
  FolderService(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<List<PhotoFolder>> listAll() async {
    final rows = await _database.db.rawQuery('''
      SELECT f.id, f.name, f.parent_id, f.sort_order,
             (SELECT COUNT(DISTINCT p.asset_id)
                FROM folder_items fi
                JOIN photos p ON p.photo_key = fi.photo_key
               WHERE fi.folder_id = f.id AND fi.deleted = 0) AS photo_count,
             (SELECT COUNT(*)
                FROM folders c
               WHERE c.parent_id = f.id AND c.deleted = 0) AS subfolder_count
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

  /// [folderId] 와 그 아래 모든 폴더의 id.
  ///
  /// `UNION ALL` 이 아니라 `UNION` 입니다. 동기화가 고리(X 아래 Y, Y 아래 X)를
  /// 만들어 낼 수 있고, ALL 이면 그 고리를 영원히 돌아 앱이 멈춥니다.
  /// UNION 은 이미 본 id 를 걸러내므로 고리가 있어도 끝납니다.
  Future<Set<String>> subtreeIds(String folderId) async {
    final rows = await _database.db.rawQuery('''
      WITH RECURSIVE sub(id) AS (
        SELECT id FROM folders WHERE id = ? AND deleted = 0
        UNION
        SELECT f.id FROM folders f
          JOIN sub ON f.parent_id = sub.id
         WHERE f.deleted = 0
      )
      SELECT id FROM sub
    ''', [folderId]);
    return rows.map((r) => r['id'] as String).toSet();
  }

  /// 폴더를 만듭니다. [parentId] 가 비어 있으면 뿌리 폴더입니다.
  Future<PhotoFolder> create(String rawName, {String parentId = ''}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('폴더 이름이 비어 있습니다.');
    }

    // 정렬 순서는 형제들 사이에서만 셉니다. 전체에서 세면 하위 폴더를
    // 만들 때마다 엉뚱하게 큰 값이 붙습니다.
    final maxRows = await _database.db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM folders '
      'WHERE deleted = 0 AND parent_id = ?',
      [parentId],
    );
    final nextOrder = ((maxRows.first['m'] as int?) ?? -1) + 1;

    final id = _uuid.v4();
    await _database.db.insert('folders', {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'sort_order': nextOrder,
      'updated_ms': _now,
      'deleted': 0,
    });
    return PhotoFolder(
      id: id,
      name: name,
      parentId: parentId,
      sortOrder: nextOrder,
    );
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

  /// 폴더를 다른 폴더 아래로 옮깁니다. [newParentId] 가 ''면 뿌리로 올립니다.
  ///
  /// 자기 자신이나 자기 하위 폴더 아래로는 옮기지 않습니다. 그렇게 하면
  /// 그 가지가 트리에서 떨어져 나가 화면에 영원히 나오지 않습니다.
  /// 막았으면 [MoveFolderResult.cycle] 을 돌려줍니다 — 조용히 넘기면
  /// 사용자는 왜 아무 일도 안 일어났는지 알 수 없습니다.
  Future<MoveFolderResult> moveFolder(
    String folderId,
    String newParentId,
  ) async {
    if (folderId == newParentId) return MoveFolderResult.cycle;
    if (newParentId.isNotEmpty) {
      final descendants = await subtreeIds(folderId);
      if (descendants.contains(newParentId)) return MoveFolderResult.cycle;
    }

    final maxRows = await _database.db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM folders '
      'WHERE deleted = 0 AND parent_id = ?',
      [newParentId],
    );
    final nextOrder = ((maxRows.first['m'] as int?) ?? -1) + 1;

    await _database.db.update(
      'folders',
      {
        'parent_id': newParentId,
        'sort_order': nextOrder,
        'updated_ms': _now,
      },
      where: 'id = ?',
      whereArgs: [folderId],
    );
    return MoveFolderResult.moved;
  }

  /// 형제들 사이에서 한 칸 위/아래로 옮깁니다.
  ///
  /// 트리에서는 끌어다 놓기로 순서를 바꾸기 어렵습니다 — 같은 단계 안으로
  /// 옮기려는 것인지 다른 부모 아래로 넣으려는 것인지 손짓만으로는 가를
  /// 수 없습니다. 그래서 메뉴로 한 칸씩 움직입니다.
  Future<void> nudge(String folderId, {required bool up}) async {
    final rows = await _database.db.query(
      'folders',
      columns: ['id', 'parent_id'],
      where: 'id = ?',
      whereArgs: [folderId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final parentId = (rows.first['parent_id'] as String?) ?? '';

    final siblings = await _database.db.query(
      'folders',
      columns: ['id'],
      where: 'deleted = 0 AND parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    final ids = siblings.map((r) => r['id'] as String).toList();
    final at = ids.indexOf(folderId);
    if (at < 0) return;

    final to = up ? at - 1 : at + 1;
    if (to < 0 || to >= ids.length) return;

    ids
      ..removeAt(at)
      ..insert(to, folderId);
    await reorder(ids);
  }

  /// 폴더를 지웁니다. **사진은 지워지지 않습니다** — 소속만 풀려서 해당
  /// 사진들이 "미지정"으로 돌아갑니다.
  ///
  /// 하위 폴더도 함께 지웁니다. 남겨 두면 부모를 잃은 채 뿌리로 올라와,
  /// 지웠다고 생각한 것이 다시 나타납니다.
  Future<void> delete(String folderId) async {
    final ids = await subtreeIds(folderId);
    if (ids.isEmpty) return;

    final marks = List.filled(ids.length, '?').join(',');
    final args = ids.toList();
    final now = _now;

    await _database.db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE folders SET deleted = 1, updated_ms = ? WHERE id IN ($marks)',
        [now, ...args],
      );
      await txn.rawUpdate(
        'UPDATE folder_items SET deleted = 1, updated_ms = ? '
        'WHERE folder_id IN ($marks)',
        [now, ...args],
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

  /// 사진을 고른 폴더들에 **복사**합니다. 지금 속한 폴더는 그대로 둡니다.
  Future<void> copyPhotos(
    Iterable<String> targetFolderIds,
    Iterable<String> photoKeys,
  ) async {
    final keys = photoKeys.toList();
    if (keys.isEmpty) return;
    for (final id in targetFolderIds) {
      await addMany(id, keys);
    }
  }

  /// 사진을 [from] 폴더에서 빼고 고른 폴더들로 **이동**합니다.
  ///
  /// [from] 이외의 폴더 소속은 건드리지 않습니다. 한 사진이 여러 폴더에
  /// 들어갈 수 있는 구조라, "이동"을 전체 소속 교체로 해석하면 사용자가
  /// 보고 있지도 않은 폴더에서 사진이 조용히 빠집니다.
  ///
  /// 넣을 곳에 [from] 이 들어 있으면 빼지 않습니다 — 제자리 이동입니다.
  Future<void> movePhotos({
    required String from,
    required Iterable<String> targetFolderIds,
    required Iterable<String> photoKeys,
  }) async {
    final keys = photoKeys.toList();
    if (keys.isEmpty) return;

    final targets = targetFolderIds.toSet();
    for (final id in targets) {
      await addMany(id, keys);
    }
    if (!targets.contains(from)) {
      await removeMany(from, keys);
    }
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

/// [FolderService.moveFolder] 의 결과.
enum MoveFolderResult {
  moved,

  /// 자기 자신이나 자기 하위 폴더 아래로 옮기려 해서 막았음.
  cycle,
}

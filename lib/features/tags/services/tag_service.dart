import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/tags/models/tag.dart';
import 'package:photo_application/features/tags/models/tag_group.dart';

/// 태그 사전과 사진↔태그 연결을 관리합니다.
class TagService {
  TagService(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();

  static int get _now => DateTime.now().millisecondsSinceEpoch;

  /// 모든 태그를 사진 수와 함께 가져옵니다.
  ///
  /// 사진 수는 `photos` 와 조인해서 셉니다. 기기에서 사라진 사진의 태그
  /// 연결은 남아 있을 수 있는데, 그것까지 세면 목록에 "3장"이라 적혀 있는데
  /// 열어보면 비어 있는 상황이 생깁니다.
  Future<List<Tag>> listAll() async {
    final rows = await _database.db.rawQuery('''
      SELECT t.id, t.name, t.group_id,
             (SELECT COUNT(DISTINCT p.asset_id)
                FROM photo_tags pt
                JOIN photos p ON p.photo_key = pt.photo_key
               WHERE pt.tag_id = t.id AND pt.deleted = 0) AS photo_count
        FROM tags t
       WHERE t.deleted = 0
       ORDER BY photo_count DESC, t.name COLLATE NOCASE ASC
    ''');
    return rows.map(Tag.fromRow).toList();
  }

  /// 사진 한 장에 달린 태그들.
  Future<List<Tag>> tagsOf(String photoKey) async {
    final rows = await _database.db.rawQuery('''
      SELECT t.id, t.name, t.group_id, 0 AS photo_count
        FROM photo_tags pt
        JOIN tags t ON t.id = pt.tag_id AND t.deleted = 0
       WHERE pt.photo_key = ? AND pt.deleted = 0
       ORDER BY t.name COLLATE NOCASE ASC
    ''', [photoKey]);
    return rows.map(Tag.fromRow).toList();
  }

  /// 이름으로 태그를 찾거나 없으면 만듭니다.
  ///
  /// 같은 이름을 대소문자만 다르게 또 만드는 걸 막습니다. 예전에 지운 이름을
  /// 다시 쓰면 tombstone 을 되살려 재사용합니다.
  ///
  /// [groupId] 를 주면 새로 만들 때 그 분류에 넣습니다. 이미 있는 태그의
  /// 분류는 건드리지 않습니다 — 사진에 태그를 다는 중에 다른 화면에서 정리해
  /// 둔 분류가 조용히 바뀌면 곤란합니다.
  Future<Tag> ensure(String rawName, {String groupId = TagGroup.none}) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('태그 이름이 비어 있습니다.');
    }

    final existing = await _database.db.query(
      'tags',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final row = existing.first;
      final id = row['id'] as String;
      final revived = (row['deleted'] as int? ?? 0) == 1;
      if (revived) {
        await _database.db.update(
          'tags',
          {'name': name, 'group_id': groupId, 'deleted': 0, 'updated_ms': _now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return Tag(
        id: id,
        name: name,
        groupId: revived ? groupId : (row['group_id'] as String?) ?? '',
      );
    }

    final id = _uuid.v4();
    await _database.db.insert('tags', {
      'id': id,
      'name': name,
      'group_id': groupId,
      'updated_ms': _now,
      'deleted': 0,
    });
    return Tag(id: id, name: name, groupId: groupId);
  }

  // --- 분류 ---------------------------------------------------------------

  /// 모든 분류를 태그 수와 함께 가져옵니다.
  Future<List<TagGroup>> listGroups() async {
    final rows = await _database.db.rawQuery('''
      SELECT g.id, g.name, g.sort_order,
             (SELECT COUNT(*) FROM tags t
               WHERE t.group_id = g.id AND t.deleted = 0) AS tag_count
        FROM tag_groups g
       WHERE g.deleted = 0
       ORDER BY g.sort_order ASC, g.name COLLATE NOCASE ASC
    ''');
    return rows.map(TagGroup.fromRow).toList();
  }

  /// 분류를 만듭니다. 같은 이름이 이미 있으면 그것을 돌려줍니다.
  Future<TagGroup> ensureGroup(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('분류 이름이 비어 있습니다.');
    }

    final existing = await _database.db.query(
      'tag_groups',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final row = existing.first;
      final id = row['id'] as String;
      if ((row['deleted'] as int? ?? 0) == 1) {
        await _database.db.update(
          'tag_groups',
          {'name': name, 'deleted': 0, 'updated_ms': _now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return TagGroup(
        id: id,
        name: name,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
    }

    // 새 분류는 맨 뒤에 붙입니다. 사용자가 만든 순서가 곧 목록 순서입니다.
    final maxOrder = Sqflite.firstIntValue(
          await _database.db.rawQuery(
            'SELECT MAX(sort_order) FROM tag_groups',
          ),
        ) ??
        -1;
    final id = _uuid.v4();
    final group = TagGroup(id: id, name: name, sortOrder: maxOrder + 1);
    await _database.db.insert('tag_groups', {
      'id': id,
      'name': name,
      'sort_order': group.sortOrder,
      'updated_ms': _now,
      'deleted': 0,
    });
    return group;
  }

  Future<void> renameGroup(String groupId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    await _database.db.update(
      'tag_groups',
      {'name': name, 'updated_ms': _now},
      where: 'id = ?',
      whereArgs: [groupId],
    );
  }

  /// 분류를 지웁니다. **태그는 지우지 않고** 미분류로 돌려보냅니다.
  ///
  /// 분류는 정리용 서랍일 뿐이라, 서랍을 버렸다고 안에 있던 태그와 그 태그가
  /// 달린 사진까지 잃으면 되돌릴 길이 없습니다. 폴더를 지울 때 사진이 미지정
  /// 으로 돌아가는 것과 같은 규칙입니다.
  Future<void> deleteGroup(String groupId) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      await txn.update(
        'tag_groups',
        {'deleted': 1, 'updated_ms': now},
        where: 'id = ?',
        whereArgs: [groupId],
      );
      await txn.update(
        'tags',
        {'group_id': TagGroup.none, 'updated_ms': now},
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
    });
  }

  /// 태그를 다른 분류로 옮깁니다. [groupId] 가 빈 문자열이면 미분류로 뺍니다.
  Future<void> moveToGroup(String tagId, String groupId) async {
    await _database.db.update(
      'tags',
      {'group_id': groupId, 'updated_ms': _now},
      where: 'id = ?',
      whereArgs: [tagId],
    );
  }

  Future<void> rename(String tagId, String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    await _database.db.update(
      'tags',
      {'name': name, 'updated_ms': _now},
      where: 'id = ?',
      whereArgs: [tagId],
    );
  }

  /// 태그를 지웁니다. 사진에 달린 연결도 함께 tombstone 처리합니다.
  Future<void> delete(String tagId) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      await txn.update(
        'tags',
        {'deleted': 1, 'updated_ms': now},
        where: 'id = ?',
        whereArgs: [tagId],
      );
      await txn.update(
        'photo_tags',
        {'deleted': 1, 'updated_ms': now},
        where: 'tag_id = ?',
        whereArgs: [tagId],
      );
    });
  }

  Future<void> attach(String photoKey, String tagId) async {
    await _database.db.insert(
      'photo_tags',
      {
        'photo_key': photoKey,
        'tag_id': tagId,
        'updated_ms': _now,
        'deleted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> detach(String photoKey, String tagId) async {
    await _database.db.insert(
      'photo_tags',
      {
        'photo_key': photoKey,
        'tag_id': tagId,
        'updated_ms': _now,
        'deleted': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 여러 사진에 태그를 한 번에 답니다 (다중 선택용).
  Future<void> attachMany(Iterable<String> photoKeys, String tagId) async {
    final now = _now;
    await _database.db.transaction((txn) async {
      final batch = txn.batch();
      for (final key in photoKeys) {
        batch.insert(
          'photo_tags',
          {
            'photo_key': key,
            'tag_id': tagId,
            'updated_ms': now,
            'deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }
}

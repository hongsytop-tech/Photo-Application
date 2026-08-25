import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/tags/models/tag.dart';

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
      SELECT t.id, t.name,
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
      SELECT t.id, t.name, 0 AS photo_count
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
  Future<Tag> ensure(String rawName) async {
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
      if ((row['deleted'] as int? ?? 0) == 1) {
        await _database.db.update(
          'tags',
          {'name': name, 'deleted': 0, 'updated_ms': _now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      return Tag(id: id, name: name);
    }

    final id = _uuid.v4();
    await _database.db.insert('tags', {
      'id': id,
      'name': name,
      'updated_ms': _now,
      'deleted': 0,
    });
    return Tag(id: id, name: name);
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

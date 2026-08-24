import 'package:sqflite/sqflite.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/notes/models/photo_note.dart';

/// 사진별 메모 저장소.
class NoteService {
  NoteService(this._database);

  final AppDatabase _database;

  Future<PhotoNote?> read(String photoKey) async {
    final rows = await _database.db.query(
      'notes',
      where: 'photo_key = ? AND deleted = 0',
      whereArgs: [photoKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final note = PhotoNote.fromRow(rows.first);
    return note.isEmpty ? null : note;
  }

  /// 메모를 저장합니다. 내용이 비면 tombstone 으로 표시해 삭제 처리합니다
  /// (실제 DELETE 를 하면 다른 기기에서 동기화될 때 되살아납니다).
  Future<void> write(String photoKey, String body) async {
    final trimmed = body.trim();
    await _database.db.insert(
      'notes',
      {
        'photo_key': photoKey,
        'body': trimmed,
        'updated_ms': DateTime.now().millisecondsSinceEpoch,
        'deleted': trimmed.isEmpty ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String photoKey) => write(photoKey, '');

  /// 메모가 달린 사진 수.
  Future<int> countPhotosWithNote() async {
    final rows = await _database.db.rawQuery(
      'SELECT COUNT(DISTINCT n.photo_key) AS c FROM notes n '
      "WHERE n.deleted = 0 AND TRIM(n.body) != '' "
      'AND EXISTS (SELECT 1 FROM photos p WHERE p.photo_key = n.photo_key)',
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}

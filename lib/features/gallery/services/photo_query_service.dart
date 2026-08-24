import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/features/gallery/models/photo_item.dart';

/// 갤러리를 어떤 기준으로 걸러 볼지.
enum PhotoScope {
  /// 기기의 모든 사진.
  all,

  /// 어떤 가상 폴더에도 넣지 않은 사진 — "미지정".
  unassigned,

  /// 메모가 달린 사진.
  withNote,

  /// 태그가 하나라도 달린 사진.
  tagged,

  /// 특정 가상 폴더에 속한 사진.
  folder,

  /// 특정 태그(들)를 가진 사진.
  tag,
}

/// 사진 목록 조회 조건.
class PhotoQuery {
  const PhotoQuery({
    this.scope = PhotoScope.all,
    this.folderId,
    this.tagIds = const [],
    this.keyword,
  });

  final PhotoScope scope;
  final String? folderId;

  /// [PhotoScope.tag] 에서 사용. 여러 개를 주면 **모두** 가진 사진만 나옵니다
  /// (AND). "바다 + 2023" 처럼 좁혀 보고 싶을 때를 위한 것입니다.
  final List<String> tagIds;

  /// 파일명 또는 메모 본문 부분 일치.
  final String? keyword;

  PhotoQuery copyWith({
    PhotoScope? scope,
    String? folderId,
    List<String>? tagIds,
    String? keyword,
  }) =>
      PhotoQuery(
        scope: scope ?? this.scope,
        folderId: folderId ?? this.folderId,
        tagIds: tagIds ?? this.tagIds,
        keyword: keyword ?? this.keyword,
      );

  // Riverpod family 의 인자로 쓰이므로 값 동등성이 필요합니다. 이게 없으면
  // 같은 조건인데도 매 rebuild 마다 새 provider 가 생겨 목록이 처음부터
  // 다시 로딩됩니다.
  @override
  bool operator ==(Object other) =>
      other is PhotoQuery &&
      other.scope == scope &&
      other.folderId == folderId &&
      other.keyword == keyword &&
      other.tagIds.length == tagIds.length &&
      const _ListEquality().equals(other.tagIds, tagIds);

  @override
  int get hashCode => Object.hash(
        scope,
        folderId,
        keyword,
        Object.hashAll(tagIds),
      );
}

class _ListEquality {
  const _ListEquality();

  bool equals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _Sql {
  const _Sql(this.where, this.args);
  final String where;
  final List<Object?> args;
}

/// `photos` 테이블에서 조건에 맞는 사진을 페이지 단위로 읽어옵니다.
///
/// 조건을 JOIN 이 아니라 EXISTS 로 표현합니다. 태그가 여러 개 달린 사진이
/// JOIN 때문에 목록에 중복으로 나오는 문제를 처음부터 만들지 않기 위해서입니다.
class PhotoQueryService {
  PhotoQueryService(this._database);

  final AppDatabase _database;

  Future<List<PhotoItem>> page(
    PhotoQuery query, {
    required int limit,
    required int offset,
  }) async {
    final clause = _clause(query);
    final rows = await _database.db.rawQuery(
      'SELECT p.* FROM photos p'
      '${clause.where.isEmpty ? '' : ' WHERE ${clause.where}'}'
      ' ORDER BY p.created_ms DESC, p.asset_id DESC'
      ' LIMIT ? OFFSET ?',
      [...clause.args, limit, offset],
    );
    return rows.map(PhotoItem.fromRow).toList();
  }

  Future<int> count(PhotoQuery query) async {
    final clause = _clause(query);
    final rows = await _database.db.rawQuery(
      'SELECT COUNT(*) AS c FROM photos p'
      '${clause.where.isEmpty ? '' : ' WHERE ${clause.where}'}',
      clause.args,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 사진 한 장을 asset id 로 찾습니다.
  Future<PhotoItem?> byAssetId(String assetId) async {
    final rows = await _database.db.query(
      'photos',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      limit: 1,
    );
    return rows.isEmpty ? null : PhotoItem.fromRow(rows.first);
  }

  _Sql _clause(PhotoQuery query) {
    final parts = <String>[];
    final args = <Object?>[];

    switch (query.scope) {
      case PhotoScope.all:
        break;

      case PhotoScope.unassigned:
        parts.add(
          'NOT EXISTS (SELECT 1 FROM folder_items fi '
          'WHERE fi.photo_key = p.photo_key AND fi.deleted = 0)',
        );

      case PhotoScope.withNote:
        parts.add(
          'EXISTS (SELECT 1 FROM notes n '
          "WHERE n.photo_key = p.photo_key AND n.deleted = 0 AND TRIM(n.body) != '')",
        );

      case PhotoScope.tagged:
        parts.add(
          'EXISTS (SELECT 1 FROM photo_tags pt '
          'WHERE pt.photo_key = p.photo_key AND pt.deleted = 0)',
        );

      case PhotoScope.folder:
        parts.add(
          'EXISTS (SELECT 1 FROM folder_items fi '
          'WHERE fi.photo_key = p.photo_key AND fi.deleted = 0 AND fi.folder_id = ?)',
        );
        args.add(query.folderId);

      case PhotoScope.tag:
        // 태그마다 EXISTS 를 하나씩 → 전부 만족해야 통과 (AND).
        for (final tagId in query.tagIds) {
          parts.add(
            'EXISTS (SELECT 1 FROM photo_tags pt '
            'WHERE pt.photo_key = p.photo_key AND pt.deleted = 0 AND pt.tag_id = ?)',
          );
          args.add(tagId);
        }
    }

    final keyword = query.keyword?.trim();
    if (keyword != null && keyword.isNotEmpty) {
      final like = '%${_escapeLike(keyword)}%';
      parts.add(
        "(p.file_name LIKE ? ESCAPE '\\' "
        'OR EXISTS (SELECT 1 FROM notes n WHERE n.photo_key = p.photo_key '
        "AND n.deleted = 0 AND n.body LIKE ? ESCAPE '\\'))",
      );
      args
        ..add(like)
        ..add(like);
    }

    return _Sql(parts.join(' AND '), args);
  }

  /// LIKE 패턴에서 특수문자를 무력화합니다. 이걸 안 하면 검색어에 들어간
  /// `%` 가 와일드카드로 동작해 엉뚱한 결과가 나옵니다.
  static String _escapeLike(String input) => input
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}

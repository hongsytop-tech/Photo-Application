import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/core/utils/photo_key.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';

/// 스캔 결과 요약.
class PhotoIndexResult {
  const PhotoIndexResult({
    this.total = 0,
    this.indexed = 0,
    this.removed = 0,
  });

  /// 기기가 보고한 전체 사진 수.
  final int total;

  /// 실제로 인덱싱한 수.
  final int indexed;

  /// 이번 스캔에서 사라진(기기에서 삭제된) 사진 수.
  final int removed;
}

/// 기기 갤러리를 훑어 `photos` 테이블을 최신 상태로 맞춥니다.
///
/// 세대(generation) 방식으로 동작합니다: 스캔을 시작할 때 세대 번호를 하나
/// 정하고, 훑으면서 만난 사진에 그 번호를 찍습니다. 끝나고 번호가 다른 행은
/// 기기에서 사라진 사진이므로 인덱스에서 지웁니다.
///
/// 이때 **메모·태그·폴더는 건드리지 않습니다.** 그것들은 photo_key 에 매달려
/// 있어서, 사진이 잠시 사라졌다가(예: SD 카드 분리) 돌아오면 그대로 다시
/// 붙습니다.
class PhotoIndexService {
  PhotoIndexService(this._database, this._gallery);

  final AppDatabase _database;
  final GalleryService _gallery;

  /// 한 번에 읽어올 사진 수. 너무 크면 메모리를, 너무 작으면 왕복 횟수를
  /// 늘립니다. 500 이면 2만 장이 40회 왕복입니다.
  static const _pageSize = 500;

  Future<PhotoIndexResult> reindex({
    void Function(int done, int total)? onProgress,
  }) async {
    final album = await _gallery.allPhotosAlbum();
    if (album == null) return const PhotoIndexResult();

    final total = await album.assetCountAsync;
    if (total == 0) {
      // 사진이 한 장도 없으면 인덱스도 비워야 합니다.
      final removed = await _database.db.delete('photos');
      return PhotoIndexResult(removed: removed);
    }

    final generation = DateTime.now().millisecondsSinceEpoch;
    var done = 0;

    for (var page = 0; done < total; page++) {
      final assets = await album.getAssetListPaged(page: page, size: _pageSize);
      if (assets.isEmpty) break;

      await _database.db.transaction((txn) async {
        final batch = txn.batch();
        for (final asset in assets) {
          final title = (asset.title ?? '').trim();
          // 파일명을 못 얻으면 asset id 로 대체합니다. 이 경우 키가 기기
          // 로컬로 묶이지만, 메모가 아예 붙지 못하는 것보다는 낫습니다.
          final fileName = title.isEmpty ? asset.id : title;
          final createdMs = asset.createDateTime.millisecondsSinceEpoch;
          final photoKey = derivePhotoKey(
            fileName: fileName,
            createdMs: createdMs,
            width: asset.width,
            height: asset.height,
          );

          batch.insert(
            'photos',
            {
              'asset_id': asset.id,
              'photo_key': photoKey,
              'file_name': fileName,
              'created_ms': createdMs,
              'width': asset.width,
              'height': asset.height,
              'seen_gen': generation,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // 신원 정보는 처음 볼 때만 씁니다. 이미 있으면 updated_ms 를
          // 건드리지 않아야 동기화가 매 스캔마다 들썩이지 않습니다.
          batch.insert(
            'photo_identity',
            {
              'photo_key': photoKey,
              'file_name': fileName,
              'created_ms': createdMs,
              'width': asset.width,
              'height': asset.height,
              'updated_ms': generation,
              'deleted': 0,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      });

      done += assets.length;
      onProgress?.call(done, total);
    }

    final removed = await _database.db.delete(
      'photos',
      where: 'seen_gen != ?',
      whereArgs: [generation],
    );

    debugPrint('사진 인덱싱 완료: $done/$total 장, 사라진 사진 $removed 장');
    return PhotoIndexResult(total: total, indexed: done, removed: removed);
  }

  /// 기기에서 지워진 사진을 인덱스에서 뺍니다.
  ///
  /// 다음 스캔이 어차피 정리하지만, 그때까지 목록에 남아 있으면 방금 지운
  /// 사진이 계속 보입니다. 눌러도 이미지가 없어 빈 칸이 되므로 바로 뺍니다.
  ///
  /// **메모·태그·폴더는 지우지 않습니다.** 그것들은 photo_key 에 매달려 있고,
  /// 같은 사진이 다른 기기에는 아직 남아 있을 수 있습니다. 여기서 함께 지우면
  /// 한 기기에서 정리한 것이 다른 기기의 메모까지 앗아갑니다.
  Future<int> forget(Iterable<String> assetIds) async {
    final ids = assetIds.toList();
    if (ids.isEmpty) return 0;
    final marks = List.filled(ids.length, '?').join(',');
    return _database.db.delete(
      'photos',
      where: 'asset_id IN ($marks)',
      whereArgs: ids,
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:photo_application/core/db/app_database.dart';
import 'package:photo_application/core/storage/local_storage.dart';
import 'package:photo_application/features/folders/services/folder_service.dart';
import 'package:photo_application/features/gallery/services/gallery_service.dart';
import 'package:photo_application/features/gallery/services/photo_index_service.dart';
import 'package:photo_application/features/gallery/services/photo_query_service.dart';
import 'package:photo_application/features/notes/services/note_service.dart';
import 'package:photo_application/features/tags/services/tag_service.dart';

/// `main()` 에서 실제 인스턴스로 덮어씁니다. 비동기 초기화가 필요한 값을
/// 화면에서 동기적으로 읽기 위한 관용적인 방법입니다.
final localStorageProvider = Provider<LocalStorage>(
  (ref) => throw UnimplementedError('ProviderScope 에서 override 되어야 합니다.'),
);

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('ProviderScope 에서 override 되어야 합니다.'),
);

/// 메타데이터가 바뀔 때마다 1 씩 증가하는 카운터.
///
/// 메모를 저장하거나 태그를 달면 사진 목록·태그 목록·개수 배지가 전부
/// 다시 계산되어야 합니다. 화면마다 어떤 provider 를 무효화할지 일일이
/// 챙기는 대신, 쓰기 쪽은 [bumpDataRevision] 하나만 호출하고 읽기 쪽은
/// 이 값을 watch 합니다.
final dataRevisionProvider = StateProvider<int>((ref) => 0);

/// 그중 **이 기기에서 직접 만든** 변경만 세는 카운터.
///
/// 자동 동기화는 [dataRevisionProvider] 가 아니라 이 값을 봅니다. 서버에서
/// 받아온 변경까지 세면, 받아온 것 때문에 또 동기화가 돌고 그게 또 변경으로
/// 잡히면서 동기화가 자기 꼬리를 뭅니다.
final localEditRevisionProvider = StateProvider<int>((ref) => 0);

/// 메타데이터 변경을 알립니다. 모든 쓰기 동작 뒤에 호출하세요.
///
/// Riverpod 에서 provider 안의 `Ref` 와 위젯의 `WidgetRef` 는 공통 상위 타입이
/// 없습니다. 양쪽에서 똑같이 `ref.bumpDataRevision()` 으로 쓰려고 확장을
/// 두 벌 둡니다.
extension DataRevisionOnRef on Ref {
  void bumpDataRevision() {
    read(dataRevisionProvider.notifier).update((value) => value + 1);
    read(localEditRevisionProvider.notifier).update((value) => value + 1);
  }

  /// 동기화가 서버에서 받아온 내용을 반영했을 때 씁니다. 화면은 다시 그리되,
  /// 자동 동기화를 다시 깨우지는 않습니다.
  void bumpDataRevisionFromSync() =>
      read(dataRevisionProvider.notifier).update((value) => value + 1);
}

extension DataRevisionOnWidgetRef on WidgetRef {
  void bumpDataRevision() {
    read(dataRevisionProvider.notifier).update((value) => value + 1);
    read(localEditRevisionProvider.notifier).update((value) => value + 1);
  }
}

final galleryServiceProvider = Provider<GalleryService>(
  (ref) => const GalleryService(),
);

final photoIndexServiceProvider = Provider<PhotoIndexService>(
  (ref) => PhotoIndexService(
    ref.watch(appDatabaseProvider),
    ref.watch(galleryServiceProvider),
  ),
);

final photoQueryServiceProvider = Provider<PhotoQueryService>(
  (ref) => PhotoQueryService(ref.watch(appDatabaseProvider)),
);

final noteServiceProvider = Provider<NoteService>(
  (ref) => NoteService(ref.watch(appDatabaseProvider)),
);

final tagServiceProvider = Provider<TagService>(
  (ref) => TagService(ref.watch(appDatabaseProvider)),
);

final folderServiceProvider = Provider<FolderService>(
  (ref) => FolderService(ref.watch(appDatabaseProvider)),
);

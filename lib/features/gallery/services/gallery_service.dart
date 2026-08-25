import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// 사진 접근 권한 상태.
enum GalleryAccess {
  /// 아직 물어보지 않음.
  unknown,

  /// 전체 사진 접근 허용.
  granted,

  /// Android 14+ 의 "일부만 허용". 사용자가 고른 사진만 보입니다.
  limited,

  /// 거부됨. 설정 앱에서 직접 켜야 합니다.
  denied,
}

/// 기기 갤러리(MediaStore) 접근을 감싸는 얇은 래퍼.
class GalleryService {
  const GalleryService();

  /// 권한을 요청하고 결과를 돌려줍니다.
  Future<GalleryAccess> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    switch (state) {
      case PermissionState.authorized:
        return GalleryAccess.granted;
      case PermissionState.limited:
        return GalleryAccess.limited;
      case PermissionState.denied:
      case PermissionState.restricted:
        return GalleryAccess.denied;
      case PermissionState.notDetermined:
        return GalleryAccess.unknown;
    }
  }

  /// 권한 화면을 다시 띄우지 않고 현재 상태만 확인합니다.
  Future<GalleryAccess> currentAccess() async {
    try {
      final state = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.image,
            mediaLocation: false,
          ),
        ),
      );
      switch (state) {
        case PermissionState.authorized:
          return GalleryAccess.granted;
        case PermissionState.limited:
          return GalleryAccess.limited;
        case PermissionState.denied:
        case PermissionState.restricted:
          return GalleryAccess.denied;
        case PermissionState.notDetermined:
          return GalleryAccess.unknown;
      }
    } catch (error) {
      debugPrint('권한 상태 조회 실패: $error');
      return GalleryAccess.unknown;
    }
  }

  /// 시스템 설정의 앱 권한 화면을 엽니다.
  Future<void> openSettings() => PhotoManager.openSetting();

  /// "일부만 허용" 상태에서 허용 사진을 다시 고르게 합니다 (Android 14+).
  Future<void> pickMorePhotos() => PhotoManager.presentLimited();

  /// 기기의 모든 사진을 담은 가상 앨범.
  ///
  /// `onlyAll: true` 로 폴더별 앨범 대신 전체 묶음 하나만 받습니다. 이 앱은
  /// 기기 폴더 구조를 그대로 보여주는 게 목적이 아니라, 전체 사진 위에
  /// 사용자만의 가상 폴더를 얹는 것이 목적이기 때문입니다.
  Future<AssetPathEntity?> allPhotosAlbum() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: true),
        orders: const [
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    return paths.isEmpty ? null : paths.first;
  }

  /// 사진을 기기에서 치웁니다. **실제로 치워진 asset id 만** 돌려줍니다.
  ///
  /// 되도록 **휴지통으로 보냅니다.** Android 11 부터 MediaStore 에 시스템
  /// 휴지통이 있어서, 거기로 보내면 30일 안에는 되살릴 수 있습니다. 완전 삭제는
  /// 되돌릴 방법이 아예 없으므로 기본으로 삼을 동작이 아닙니다.
  ///
  /// 휴지통을 쓸 수 없는 기기(Android 10 이하)에서는 완전 삭제로 넘어갑니다.
  /// 그 경로에서도 시스템이 확인 창을 한 번 더 띄웁니다.
  ///
  /// 어느 쪽이든 사용자가 시스템 확인 창에서 거절하면 아무것도 치워지지 않은 채
  /// 빈 목록이 돌아옵니다. 그래서 "요청한 것"이 아니라 "치워진 것"을 기준으로
  /// 인덱스를 정리해야 합니다.
  Future<PhotoRemoval> removeAssets(List<String> assetIds) async {
    if (assetIds.isEmpty) return const PhotoRemoval.none();

    try {
      final entities = <AssetEntity>[];
      for (final id in assetIds) {
        final entity = await AssetEntity.fromId(id);
        if (entity != null) entities.add(entity);
      }
      if (entities.isNotEmpty) {
        final moved = await PhotoManager.editor.android.moveToTrash(entities);
        // 빈 목록은 "사용자가 확인 창에서 거절함"입니다. 실패가 아니므로
        // 완전 삭제로 넘어가면 안 됩니다 — 방금 거절한 사람에게 창을 한 번 더
        // 들이밀고, 이번에는 되돌릴 수 없게 지우게 됩니다.
        return PhotoRemoval(ids: moved, trashed: true);
      }
    } catch (error) {
      // Android 10 이하에는 휴지통 자체가 없어 여기서 예외가 납니다.
      debugPrint('휴지통으로 보내지 못해 완전 삭제로 넘어갑니다: $error');
    }

    final deleted = await PhotoManager.editor.deleteWithIds(assetIds);
    return PhotoRemoval(ids: deleted, trashed: false);
  }
}

/// 사진을 치운 결과.
class PhotoRemoval {
  const PhotoRemoval({required this.ids, required this.trashed});

  const PhotoRemoval.none()
      : ids = const [],
        trashed = false;

  /// 실제로 치워진 asset id 들. 사용자가 시스템 확인 창에서 거절하면 비어 있습니다.
  final List<String> ids;

  /// 휴지통으로 보냈으면 true, 완전히 지웠으면 false.
  final bool trashed;

  bool get isEmpty => ids.isEmpty;
}

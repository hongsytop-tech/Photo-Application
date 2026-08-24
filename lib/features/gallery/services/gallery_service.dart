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
}

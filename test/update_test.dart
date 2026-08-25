import 'package:flutter_test/flutter_test.dart';

import 'package:photo_application/features/update/services/update_service.dart';

void main() {
  group('stripAbiOffset', () {
    // --split-per-abi 는 versionCode 에 ABI 오프셋을 더한다.
    // 이걸 걷어내지 않으면 릴리스 번호와 견줄 때 언제나 설치된 쪽이 커 보여
    // 업데이트가 영원히 오지 않는다. 화면에는 "최신 버전입니다"로만 보여서
    // 고장난 줄 모르고 지나가기 쉬운 종류다.
    test('arm64-v8a 오프셋(+2000)을 걷어낸다', () {
      expect(UpdateService.stripAbiOffset(2011), 11);
      expect(UpdateService.stripAbiOffset(2013), 13);
    });

    test('armeabi-v7a 오프셋(+1000)을 걷어낸다', () {
      expect(UpdateService.stripAbiOffset(1011), 11);
    });

    test('x86_64 오프셋(+4000)을 걷어낸다', () {
      expect(UpdateService.stripAbiOffset(4011), 11);
    });

    test('universal APK 는 오프셋이 없어 그대로 둔다', () {
      expect(UpdateService.stripAbiOffset(11), 11);
      expect(UpdateService.stripAbiOffset(999), 999);
    });

    test('오프셋을 걷어낸 뒤에는 새 릴리스가 더 크게 나온다', () {
      // 실제로 겪은 상황: 설치된 arm64 빌드 11, 서버 릴리스 13.
      const installedVersionCode = 2011;
      const latestRelease = 13;

      expect(latestRelease > installedVersionCode, isFalse,
          reason: '오프셋을 그대로 두면 이렇게 뒤집힌다');
      expect(latestRelease > UpdateService.stripAbiOffset(installedVersionCode),
          isTrue,
          reason: '걷어내면 제대로 비교된다');
    });
  });
}

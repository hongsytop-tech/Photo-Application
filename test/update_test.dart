import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_application/features/update/models/app_release.dart';
import 'package:photo_application/features/update/providers/update_providers.dart';
import 'package:photo_application/features/update/services/update_service.dart';

/// 실제 네트워크·설정 화면 대신 눌린 순서만 기록하는 대역.
class _FakeUpdateService extends UpdateService {
  _FakeUpdateService({this.granted = false});

  /// "이 출처의 앱 설치"가 켜져 있는지.
  bool granted;

  /// 설정 화면에서 사용자가 켜 줄지.
  bool grantOnRequest = false;

  int settingsOpened = 0;
  int downloads = 0;
  int installs = 0;

  @override
  Future<int> currentBuildNumber() async => 10;

  @override
  Future<AppRelease?> fetchLatest() async => const AppRelease(
        buildNumber: 11,
        tag: 'apk-build-11',
        downloadUrl: 'https://example.invalid/app.apk',
        sizeBytes: 20 * 1024 * 1024,
      );

  @override
  Future<bool> canInstallPackages() async => granted;

  @override
  Future<bool> requestInstallPermission() async {
    settingsOpened++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<File> download(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    downloads++;
    onProgress?.call(1);
    return File('${Directory.systemTemp.path}/fake-${release.tag}.apk');
  }

  @override
  Future<String?> install(File apk) async {
    installs++;
    return null;
  }
}

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

  // 업데이트는 두 걸음이어야 합니다. 스토어를 거치지 않는 APK 는 "이 출처의
  // 앱 설치"가 꺼져 있으면 설치 화면에서 되돌려보내집니다. 먼저 받아 놓고
  // 마지막에 막히면, 사용자는 20MB 를 버린 채 이유도 모른 채 남습니다.
  group('설치 허용 먼저, 내려받기는 그다음', () {
    late _FakeUpdateService service;
    late ProviderContainer container;

    Future<UpdateController> ready() async {
      final controller = container.read(updateProvider.notifier);
      await controller.check();
      expect(container.read(updateProvider).phase, UpdatePhase.available);
      return controller;
    }

    setUp(() {
      service = _FakeUpdateService();
      container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
    });
    tearDown(() => container.dispose());

    test('허용이 없으면 업데이트를 눌러도 받지 않고 설정으로 보낸다', () async {
      final controller = await ready();

      await controller.start();

      expect(service.settingsOpened, 1, reason: '설정 화면으로 보내야 한다');
      expect(service.downloads, 0, reason: '허용 전에는 한 바이트도 받지 않는다');
      expect(container.read(updateProvider).phase, UpdatePhase.needsPermission);
    });

    test('설정에서 허용하고 돌아오면 내려받기 버튼 단계로 넘어간다', () async {
      final controller = await ready();
      service.grantOnRequest = true;

      await controller.start();

      expect(container.read(updateProvider).phase, UpdatePhase.ready);
      expect(service.downloads, 0, reason: '누르는 건 사용자 몫이다');
    });

    test('허용된 뒤 다운로드를 누르면 받고 설치 화면을 띄운다', () async {
      final controller = await ready();
      service.granted = true;

      await controller.start();
      expect(container.read(updateProvider).phase, UpdatePhase.ready);

      await controller.downloadAndInstall();

      expect(service.downloads, 1);
      expect(service.installs, 1);
      expect(container.read(updateProvider).phase, UpdatePhase.installing);
    });

    test('허용해 놓고 껐으면 다운로드를 눌러도 다시 설정으로 보낸다', () async {
      final controller = await ready();
      service.granted = true;
      await controller.start();

      // 설정 화면에 다녀오는 사이 자동 차단이 다시 켜진 상황.
      service.granted = false;
      await controller.downloadAndInstall();

      expect(service.downloads, 0);
      expect(container.read(updateProvider).phase, UpdatePhase.needsPermission);
    });

    test('시스템 설정에서 직접 껐다가 돌아오면 다시 확인해 준다', () async {
      final controller = await ready();
      await controller.start();
      expect(container.read(updateProvider).phase, UpdatePhase.needsPermission);

      // 우리가 연 화면이 아니라 설정 앱 깊숙한 곳에서 자동 차단을 끈 경우.
      service.granted = true;
      await controller.recheckPermission();

      expect(container.read(updateProvider).phase, UpdatePhase.ready);
    });
  });
}

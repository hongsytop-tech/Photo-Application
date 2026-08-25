import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:photo_application/features/update/models/app_release.dart';

/// 새 버전을 찾아 내려받고 설치 화면까지 띄웁니다.
///
/// 이 앱은 스토어를 거치지 않으므로 업데이트를 스스로 챙겨야 합니다. GitHub
/// 릴리스를 그대로 배포처로 씁니다 — 저장소가 공개라 토큰 없이 읽을 수 있고,
/// 앱에 자격증명을 심지 않아도 됩니다.
class UpdateService {
  const UpdateService();

  static const _owner = 'hongsytop-tech';
  static const _repo = 'Photo-Application';

  static const _latestUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// 빌드할 때 --dart-define 으로 심는 번호. 이게 가장 믿을 만합니다.
  static const compiledBuildNumber =
      int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

  /// 지금 설치된 빌드 번호.
  Future<int> currentBuildNumber() async {
    if (compiledBuildNumber > 0) return compiledBuildNumber;

    // 폴백: 안드로이드 versionCode.
    final info = await PackageInfo.fromPlatform();
    return stripAbiOffset(int.tryParse(info.buildNumber) ?? 0);
  }

  /// versionCode 에서 ABI 오프셋을 걷어냅니다.
  ///
  /// --split-per-abi 로 빌드하면 Flutter 가 versionCode 에 ABI 별 오프셋을
  /// 더합니다 (armeabi-v7a +1000, arm64-v8a +2000, x86_64 +4000). 그래서
  /// 빌드 11 의 arm64 APK 는 versionCode 가 2011 이 됩니다.
  ///
  /// 이걸 모르고 릴리스 번호와 그대로 견주면 2011 vs 13 이 되어 언제나
  /// "이미 최신"으로 판정합니다. 업데이트가 영원히 오지 않는데 화면에는
  /// 아무 이상이 없어 보이는, 알아채기 어려운 종류의 고장입니다.
  static int stripAbiOffset(int versionCode) =>
      versionCode >= 1000 ? versionCode % 1000 : versionCode;

  /// 서버의 최신 릴리스. 없거나 읽지 못하면 null.
  ///
  /// 기기 ABI 에 맞는 APK 를 고릅니다. arm64 폰에 54MB 짜리 universal 을
  /// 내려받게 하는 건 낭비라서, 맞는 것이 있으면 그걸 쓰고 없을 때만
  /// universal 로 물러섭니다.
  Future<AppRelease?> fetchLatest() async {
    try {
      final response = await http
          .get(Uri.parse(_latestUrl), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('릴리스 조회 실패: HTTP ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map) return null;

      final tag = body['tag_name'] as String?;
      if (tag == null) return null;
      final build = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '');
      if (build == null) return null;

      final assets = (body['assets'] as List?) ?? const [];
      final wanted = _preferredAbiNames();

      Map<String, dynamic>? pick;
      for (final name in wanted) {
        pick = assets.cast<Map<String, dynamic>>().firstWhere(
              (a) => (a['name'] as String? ?? '').contains(name),
              orElse: () => <String, dynamic>{},
            );
        if (pick.isNotEmpty) break;
        pick = null;
      }
      if (pick == null) return null;

      return AppRelease(
        buildNumber: build,
        tag: tag,
        downloadUrl: pick['browser_download_url'] as String,
        sizeBytes: (pick['size'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('릴리스 조회 실패: $error');
      return null;
    }
  }

  /// 이 기기에 맞는 APK 이름 조각을 우선순위대로.
  ///
  /// Abi.current() 는 dart:ffi 가 주는 값이라 별도 패키지가 필요 없습니다.
  static List<String> _preferredAbiNames() {
    switch (Abi.current()) {
      case Abi.androidArm64:
        return ['arm64-v8a', 'universal'];
      case Abi.androidArm:
        return ['armeabi-v7a', 'universal'];
      default:
        return ['universal'];
    }
  }

  /// APK 를 내려받아 저장한 경로를 돌려줍니다.
  ///
  /// [onProgress] 는 0.0~1.0. 서버가 길이를 안 알려주면 호출되지 않습니다.
  Future<File> download(
    AppRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/photo-${release.tag}.apk');

    // 받다 만 파일이 남아 있으면 지웁니다. 이어받기는 하지 않습니다 —
    // 반쯤 받은 APK 를 설치하려 들면 실패 이유를 알기 어렵습니다.
    if (file.existsSync()) await file.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(release.downloadUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = file.openWrite();
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      });
      await sink.flush();
      await sink.close();
      return file;
    } finally {
      client.close();
    }
  }

  /// 안드로이드 설치 화면을 띄웁니다.
  ///
  /// 실제 설치 여부는 사용자가 그 화면에서 결정합니다. 앱이 조용히 자기를
  /// 바꿔치기할 수는 없습니다 — 그게 안드로이드의 안전장치입니다.
  Future<String?> install(File apk) async {
    final result = await OpenFilex.open(
      apk.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type == ResultType.done) return null;
    return result.message;
  }
}

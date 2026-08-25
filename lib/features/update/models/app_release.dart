/// GitHub 릴리스 하나.
class AppRelease {
  const AppRelease({
    required this.buildNumber,
    required this.tag,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  /// 릴리스 태그에서 뽑아낸 빌드 번호 (`apk-build-12` → 12).
  final int buildNumber;
  final String tag;
  final String downloadUrl;
  final int sizeBytes;

  String get sizeLabel => '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)}MB';
}

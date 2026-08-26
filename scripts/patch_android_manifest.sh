#!/usr/bin/env bash
# `flutter create . --platforms=android` 로 생성된 AndroidManifest.xml 에
# 사진 라이브러리 접근 권한과 앱 이름을 주입합니다.
#
# 안드로이드 버전별로 필요한 권한이 다릅니다:
#   - Android 12 이하 (API ≤ 32): READ_EXTERNAL_STORAGE
#   - Android 13+  (API 33+)    : READ_MEDIA_IMAGES
#   - Android 14+  (API 34+)    : READ_MEDIA_VISUAL_USER_SELECTED (부분 허용)
# photo_manager 는 실행 시점에 OS 버전을 보고 알맞은 권한을 요청합니다.

set -euo pipefail

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "❌ $MANIFEST 가 없습니다. 먼저 'flutter create . --platforms=android' 를 실행하세요." >&2
  exit 1
fi

python3 - "$MANIFEST" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    s = f.read()

if 'READ_MEDIA_IMAGES' in s:
    print('✅ 이미 패치되어 있습니다. 건너뜁니다.')
    sys.exit(0)

permissions = '''
    <!-- 메타데이터 동기화(Supabase)용 -->
    <uses-permission android:name="android.permission.INTERNET"/>

    <!-- 사진 읽기. Android 12 이하에서만 사용되도록 maxSdkVersion 으로 제한 -->
    <uses-permission
        android:name="android.permission.READ_EXTERNAL_STORAGE"
        android:maxSdkVersion="32"/>

    <!-- Android 13+ 의 세분화된 미디어 권한 -->
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>

    <!-- Android 14+ "일부 사진만 허용" 모드 -->
    <uses-permission android:name="android.permission.READ_MEDIA_VISUAL_USER_SELECTED"/>

    <!-- 사진 삭제. Android 11+ 는 시스템이 확인 창을 띄워 처리하므로 이 권한이
         필요 없지만, Android 10 이하에서는 이것이 있어야 지울 수 있습니다. -->
    <uses-permission
        android:name="android.permission.WRITE_EXTERNAL_STORAGE"
        android:maxSdkVersion="29"/>

    <!-- 앱 내 업데이트: 내려받은 APK 의 설치 화면을 띄우기 위해 필요.
         실제 설치 여부는 사용자가 그 화면에서 결정합니다. -->
    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
'''

# <manifest ...> 바로 안쪽에 권한 삽입
s, n = re.subn(r'(<manifest[^>]*>)', r'\1' + permissions, s, count=1)
if n != 1:
    print('❌ <manifest> 태그를 찾지 못했습니다.', file=sys.stderr)
    sys.exit(1)

# 앱 이름을 한국어로
s = re.sub(r'android:label="[^"]*"', 'android:label="마이모먼트"', s, count=1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(s)

print('✅ AndroidManifest.xml 패치 완료 (사진 권한 + 앱 이름)')
PY

# 패치 결과 검증 — 조용히 실패하지 않도록
for perm in READ_MEDIA_IMAGES READ_MEDIA_VISUAL_USER_SELECTED READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE INTERNET REQUEST_INSTALL_PACKAGES; do
  grep -q "$perm" "$MANIFEST" || { echo "❌ 검증 실패: $perm 권한이 없습니다." >&2; exit 1; }
done
echo "✅ 권한 6종 검증 통과"

grep -q 'android:label="마이모먼트"' "$MANIFEST" \
  || { echo "❌ 검증 실패: 앱 이름이 바뀌지 않았습니다." >&2; exit 1; }
echo "✅ 앱 이름 검증 통과"

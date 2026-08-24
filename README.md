# 사진 정리 (Photo Application)

폰에 저장된 사진을 **옮기거나 고치지 않고**, 그 위에 나만의 메모·태그·폴더를
얹어 관리하는 안드로이드 앱.

## 이 앱이 하는 일

1. **모든 사진 탐색** — 기기 갤러리를 통째로 훑어 최신순 그리드로 봅니다.
2. **사진별 메모** — 사진 한 장에 메모장이 하나씩 붙습니다. 사진 위에 글자가
   그려지는 게 아니라, 열어야 보이는 별도의 글입니다.
3. **복수 태그** — 사진 한 장에 태그를 여러 개 달고, 같은 태그를 가진 사진을
   모아 봅니다. 태그를 여러 개 골라 **전부 가진** 사진만 좁혀 볼 수도 있습니다.
4. **가상 폴더** — 기기의 실제 폴더와 무관하게 나만의 폴더를 만들어 사진을
   담습니다. 어느 폴더에도 담지 않은 사진은 **미지정**으로 모입니다.

사진 파일은 **읽기만** 합니다. 고치거나 옮기거나 지우지 않고, 어디로도
올리지 않습니다.

## 왜 웹이 아니라 안드로이드 앱인가

브라우저는 갤러리 전체를 탐색할 수 없습니다. 사용자가 파일 선택창에서 직접
고른 파일만 넘겨받고, 그마저도 다음에 다시 열면 남아 있지 않습니다. 1번
요구사항이 웹에서는 성립하지 않아 이 프로젝트만 GitHub Pages 가 아닌
**APK 배포**를 씁니다.

## 설치

`Actions → Build APK` 가 돌 때마다 **Releases** 에 APK 가 올라갑니다.
폰에서 `photo-arm64-v8a-*.apk` 를 받아 설치하세요 (요즘 폰 대부분).
CPU 를 모르겠으면 `photo-universal-*.apk` 를 받으면 됩니다.

첫 실행 때 사진 접근 권한을 물어봅니다. 허용하면 갤러리를 훑어 목록을 만듭니다.
사진이 수만 장이면 첫 스캔에 수십 초가 걸릴 수 있고, 이후 실행은 빠릅니다.

### keystore 를 한 번만 설정해 두세요 (권장)

설정하지 않아도 APK 는 나오지만, 빌드마다 서명 키가 달라져 **기존 앱 위에
덮어쓰기 설치가 안 됩니다**(매번 지우고 새로 깔아야 하고, 그때 앱 데이터도
사라집니다). 한 번만 해두면 됩니다.

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # 이 출력을 통째로 복사
```

저장소 **Settings → Secrets and variables → Actions** 에 등록:

| 시크릿 | 값 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 위 base64 출력 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 비밀번호 |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 |

> `upload-keystore.jks` 원본은 안전한 곳에 보관하세요. 잃어버리면 같은 서명으로
> 업데이트할 수 없습니다.

## 기기 간 동기화 (선택)

로그인 없이도 모든 기능이 동작합니다. 백엔드는 **메모·태그·폴더를 다른 기기와
맞추고 싶을 때만** 필요합니다. **사진 원본은 서버로 올라가지 않습니다.**

1. Supabase 프로젝트 생성 → `SUPABASE_URL`, `anon key` 확보
2. SQL Editor 에서 `supabase/migrations/0001_photo_metadata.sql` 실행
3. 저장소 시크릿에 `SUPABASE_URL`, `SUPABASE_ANON_KEY` 등록 후 다시 빌드
4. 앱의 설정 탭에서 로그인

기기를 바꿨다면 새 기기에서 로그인한 뒤 **설정 → 서버에서 전부 다시 받기**를
한 번 실행하세요.

## 직접 빌드하기

```bash
cp .env.example .env          # 백엔드를 안 쓸 거면 값은 비워 둬도 됩니다
flutter create . --project-name photo_application --org com.hongsytop --platforms=android
bash scripts/patch_android_manifest.sh    # 사진 권한 주입
python3 scripts/patch_android_signing.py  # 릴리스 서명 설정
flutter pub get
flutter run                   # 연결된 기기에서 실행
flutter test                  # 데이터 계층 테스트
```

`android/` 를 저장소에 두지 않고 매번 `flutter create` 로 만듭니다. Flutter 자신의
템플릿을 쓰므로 AGP·Gradle 버전이 설치된 SDK 와 항상 맞고, 손으로 커밋해 둔
스캐폴딩이 시간이 지나 어긋나는 문제가 생기지 않습니다.

## 구조

```
lib/
  main.dart                       # dotenv → Supabase → SQLite → runApp
  app.dart                        # 시작 시 갤러리 스캔 + 동기화
  core/
    config/env.dart               # .env 접근 (전부 null 허용)
    db/app_database.dart          # SQLite 스키마 — 이 앱의 중심
    supabase/supabase_service.dart
    storage/local_storage.dart    # 설정값 전용 (사진 데이터 아님)
    providers/core_providers.dart # 서비스 주입 + 데이터 변경 알림
    utils/photo_key.dart          # 기기 간 안정 사진 식별키
    theme/app_theme.dart
  features/
    gallery/   기기 사진 스캔·조회·그리드·뷰어
    notes/     사진별 메모
    tags/      태그 사전 + 사진↔태그
    folders/   가상 폴더 + 사진↔폴더
    sync/      메타데이터 동기화 (사진 파일 제외)
    auth/      로그인 (선택)
    settings/  스캔·계정·초기화
    shell/     하단 탭
supabase/migrations/0001_photo_metadata.sql
scripts/       CI 에서 android/ 를 패치하는 스크립트
```

## 설계에서 중요한 두 가지

### 1. 사진을 무엇으로 식별하는가

메모를 사진에 매달려면 "이 사진"을 가리키는 이름표가 필요합니다. 안드로이드가
주는 MediaStore id 를 그대로 쓰면 편하지만, 기기를 바꾸거나 사진을 SD 카드로
옮기거나 OS 가 미디어 DB 를 재구축하면 값이 달라집니다. 그 위에 메모를 올려두면
언젠가 메모가 통째로 미아가 됩니다.

그래서 **파일명 + 촬영시각 + 해상도**에서 sha1 키를 유도해 씁니다. 파일 내용
해시가 더 정확하지만 수만 장의 원본을 전부 읽어야 해서 첫 스캔이 수 분대로
늘어납니다. 위 세 값은 MediaStore 가 이미 들고 있어 파일을 열지 않고 얻습니다.

알려진 트레이드오프: 완전히 동일한 사진의 **복사본**은 같은 키를 가져 메모와
태그를 공유합니다. 갤러리에는 둘 다 정상적으로 보입니다(목록은 사진 단위,
메타데이터는 키 단위).

### 2. 삭제를 어떻게 기록하는가

메모·태그·폴더를 지울 때 행을 실제로 지우지 않고 `deleted = 1` 로 표시합니다.
정말 지워버리면, 아직 그 사실을 모르는 다른 기기가 자기 사본을 올리는 순간
지운 항목이 되살아납니다. 충돌은 마지막 수정 시각이 이기는 방식으로 풉니다.

## 스택

Flutter · Riverpod · sqflite · photo_manager · Supabase(선택) · GitHub Actions

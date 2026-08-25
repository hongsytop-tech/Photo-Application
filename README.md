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
5. **골라서 치우기** — 목록에서 길게 눌러 여러 장을 고른 뒤 **휴지통으로**
   보냅니다. 30일 안에는 갤러리 앱에서 되살릴 수 있습니다.

사진 파일을 **고치거나 옮기지 않고**, 어디로도 올리지 않습니다. 파일을 건드리는
동작은 이것 하나뿐이고, 직접 고른 사진에 대해 확인을 받은 뒤에만 일어납니다
(안드로이드가 시스템 확인 창을 한 번 더 띄웁니다).

휴지통은 Android 11 부터 MediaStore 가 제공하는 시스템 휴지통(`IS_TRASHED`)을
씁니다. 완전 삭제는 되돌릴 방법이 없어 기본 동작으로 삼지 않았고, 휴지통이 없는
안드로이드 10 이하에서만 그쪽으로 넘어갑니다.

지운 사진의 메모·태그는 함께 지우지 않습니다. 같은 사진이 다른 기기에 남아
있을 수 있어서, 여기서 지우면 그쪽 메모까지 잃습니다.

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
덮어쓰기 설치가 안 됩니다**(매번 지우고 새로 깔아야 하고, 그때 메모·태그·폴더도
사라집니다). 한 번만 해두면 됩니다.

**내 컴퓨터에 아무것도 깔지 않고 GitHub Codespaces 안에서 끝낼 수 있습니다.**

1. 저장소 페이지에서 초록색 **Code** 버튼 → **Codespaces** 탭 →
   **Create codespace on ...** 를 누릅니다. 브라우저에 VS Code 가 열리고,
   준비가 끝나면 터미널 아래에 "✅ 준비 완료" 가 뜹니다 (첫 실행은 몇 분 걸립니다).

2. 터미널에 이걸 붙여 넣습니다:

   ```bash
   bash scripts/setup_keystore.sh
   ```

   비밀번호를 물어보는데 **그냥 엔터를 누르면 안전한 비밀번호를 자동으로
   만들어 줍니다.** 스크립트가 서명키를 만들고 GitHub 시크릿 4개까지 대신
   등록합니다.

3. 스크립트가 시키는 대로 **`upload-keystore.jks` 파일을 내려받아 보관**하세요.
   VS Code 왼쪽 파일 목록에서 파일을 오른쪽 클릭 → **Download**.
   자동 생성된 비밀번호도 함께 적어 두세요.

   > Codespace 는 지워질 수 있는 임시 공간입니다. 이 파일을 잃으면 같은 서명으로
   > 업데이트할 방법이 영영 없습니다. 클라우드 드라이브나 비밀번호 관리자에
   > 넣어 두세요. (`.gitignore` 에 들어 있어 저장소에는 올라가지 않습니다.)

4. 다음 빌드부터 적용됩니다. 빌드는 **커밋을 밀어 넣어** 돌립니다:

   ```bash
   git commit --allow-empty -m "chore: 서명키 적용 빌드" && git push
   ```

   Actions 로그의 "서명 keystore 준비" 단계에 경고 대신
   `✅ 업로드 keystore 로 서명합니다.` 가 뜨면 성공입니다.

> **`gh workflow run` 은 Codespaces 에서 403 이 납니다.** Codespaces 가 기본으로
> 주는 토큰은 권한이 좁은 통합(GitHub App) 토큰이라 워크플로를 띄우거나 시크릿을
> 쓸 수 없습니다. 워크플로가 `push` 에서도 돌기 때문에 커밋을 미는 쪽이 가장
> 확실합니다.

시크릿 자동 등록도 같은 이유로 실패할 수 있습니다. 그러면 스크립트가 이렇게
알려 줍니다 — 내 계정으로 다시 로그인한 뒤 시크릿만 다시 등록하면 됩니다
(**keystore 는 다시 만들지 않습니다**):

```bash
unset GITHUB_TOKEN GH_TOKEN
gh auth login -h github.com -p https -w -s repo,workflow
KEYSTORE_PASSWORD='아까_그_비밀번호' bash scripts/setup_keystore.sh --secrets-only
```

이것도 번거로우면 **Settings → Secrets and variables → Actions** 에서 직접
등록해도 됩니다. 스크립트가 `keystore.base64.txt` 를 남겨 둡니다.

<details>
<summary>Codespaces 대신 내 컴퓨터에서 하려면</summary>

JDK 가 필요합니다 (Android Studio 가 있으면 이미 있습니다).

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks     # Mac: base64 -i upload-keystore.jks | tr -d '\n'
```

**Settings → Secrets and variables → Actions** 에서 시크릿 4개를 등록합니다:
`ANDROID_KEYSTORE_BASE64`(위 출력 전체), `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`(`upload`), `ANDROID_KEY_PASSWORD`.

</details>

## Codespaces 에서 코드 확인하기

`.devcontainer` 가 있어 Codespace 를 열면 Flutter 가 자동으로 깔립니다.
CI 를 기다리지 않고 바로 확인할 수 있습니다:

```bash
flutter analyze --no-fatal-infos   # CI 와 같은 기준
flutter test                       # 데이터 계층 테스트
```

APK 빌드와 실기기 실행은 Codespaces 에서 하지 않습니다. 안드로이드 SDK 를
얹으면 컨테이너가 몇 GB 로 불어나고 준비 시간이 길어져서, 그 일은 GitHub
Actions 에 맡깁니다.

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

#!/usr/bin/env bash
# Codespaces / dev container 준비.
#
# 이 컨테이너로 할 수 있는 일:
#   - flutter analyze / flutter test  → CI 를 기다리지 않고 바로 확인
#   - bash scripts/setup_keystore.sh  → 앱 서명키 만들고 GitHub 시크릿 등록
#
# 안드로이드 APK 빌드와 실기기 실행은 여기서 하지 않습니다. 그건 GitHub
# Actions 가 맡습니다 (Codespaces 에 안드로이드 SDK 를 얹으면 컨테이너가
# 몇 GB 로 불어나고 준비 시간도 길어집니다).

set -euo pipefail

FLUTTER_DIR="/opt/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Flutter SDK 설치 중…"
  sudo git clone --depth 1 -b stable \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  sudo chown -R "$(whoami)" "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_DIR"

flutter config --no-analytics --no-cli-animations >/dev/null 2>&1 || true
flutter precache --universal >/dev/null 2>&1 || true

# .env 는 pubspec 에 asset 으로 선언되어 있어 파일 자체가 없으면 빌드가
# 실패합니다. 값은 비어 있어도 됩니다 — 그러면 앱이 로컬 전용으로 동작합니다.
if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env.example 로부터 .env 를 만들었습니다."
fi

# 테스트에서 in-memory SQLite 를 씁니다.
sudo apt-get update -qq && sudo apt-get install -y -qq libsqlite3-0 >/dev/null 2>&1 || true

flutter pub get

cat <<'MSG'

────────────────────────────────────────────────────────
✅ 준비 완료

  flutter analyze --no-fatal-infos   코드 검사 (CI 와 같은 기준)
  flutter test                       데이터 계층 테스트

  bash scripts/setup_keystore.sh     앱 서명키 만들기 (최초 1회)
  gh workflow run build-apk.yml      APK 빌드 돌리기
────────────────────────────────────────────────────────
MSG

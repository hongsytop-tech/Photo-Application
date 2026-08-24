#!/usr/bin/env bash
#
# 앱 서명 keystore 를 만들고 GitHub 시크릿 4개를 등록합니다.
# GitHub Codespaces 터미널에서 한 번만 실행하면 됩니다:
#
#     bash scripts/setup_keystore.sh
#
# 왜 필요한가: 안드로이드는 APK 의 서명으로 앱의 신원을 판단합니다. 서명 키가
# 바뀌면 같은 앱으로 보지 않아 기존 앱 위에 업데이트가 되지 않고, 지웠다
# 새로 깔아야 해서 그때 앱 데이터(메모·태그·폴더)도 사라집니다. 지금은
# keystore 가 없어 CI 가 매 빌드 임시 키를 만들어 쓰므로 매번 재설치입니다.

set -euo pipefail

KEYSTORE_FILE="upload-keystore.jks"
ALIAS="upload"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n❌ %s\n' "$*" >&2; exit 1; }

# --- 사전 확인 -------------------------------------------------------------

# Codespaces 기본 이미지에는 JDK 가 있지만, 없으면 JAVA_HOME 아래를 찾아봅니다.
KEYTOOL="$(command -v keytool || true)"
if [ -z "$KEYTOOL" ] && [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/keytool" ]; then
  KEYTOOL="$JAVA_HOME/bin/keytool"
fi
[ -n "$KEYTOOL" ] || fail "keytool 을 찾지 못했습니다. JDK 가 필요합니다.
   Codespaces 라면 .devcontainer 에 java 기능이 들어 있으니 컨테이너를
   Rebuild 하거나, 임시로 'sudo apt-get install -y default-jdk' 를 실행하세요."

command -v gh >/dev/null || fail "gh CLI 를 찾지 못했습니다. Codespaces 에는 기본 설치되어 있습니다."

# --secrets-only: keystore 는 그대로 두고 시크릿 등록만 다시 시도합니다.
# 권한 문제로 등록이 실패했을 때, 다시 로그인한 뒤 쓰라고 있는 통로입니다.
SECRETS_ONLY=0
if [ "${1:-}" = "--secrets-only" ]; then
  SECRETS_ONLY=1
fi

if [ "$SECRETS_ONLY" = "1" ]; then
  [ -e "$KEYSTORE_FILE" ] || fail "$KEYSTORE_FILE 이 없습니다.
   --secrets-only 는 이미 만들어 둔 keystore 를 쓰는 모드입니다.
   아직 안 만들었다면 옵션 없이 그냥 실행하세요."
elif [ -e "$KEYSTORE_FILE" ]; then
  fail "$KEYSTORE_FILE 이 이미 있습니다.
   덮어쓰면 기존 서명을 영영 잃습니다.

   시크릿 등록만 다시 하려면:
       KEYSTORE_PASSWORD='비밀번호' bash scripts/setup_keystore.sh --secrets-only

   정말 새 키를 만들 생각이라면 기존 파일을 먼저 안전한 곳으로 옮기세요."
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$REPO" ] || fail "현재 폴더의 GitHub 저장소를 알아내지 못했습니다. 저장소 안에서 실행하세요."

say "저장소: $REPO"

# --- 비밀번호 --------------------------------------------------------------

# 대화형이면 물어보고, 아니면 KEYSTORE_PASSWORD 환경변수를 봅니다.
# 둘 다 없으면 안전한 비밀번호를 만들어 씁니다.
#
# read 는 EOF 에서 실패 코드를 내는데 set -e 와 만나면 스크립트가 아무 말도
# 없이 죽습니다. 반드시 || true 로 받아야 합니다.
PW="${KEYSTORE_PASSWORD:-}"
GENERATED=0

if [ -z "$PW" ] && [ -t 0 ]; then
  printf '\nkeystore 비밀번호를 정하세요.\n'
  printf '그냥 엔터를 누르면 안전한 비밀번호를 자동으로 만들어 드립니다.\n'
  read -rsp '비밀번호: ' PW || PW=""
  echo
  if [ -n "$PW" ]; then
    read -rsp '비밀번호 확인: ' PW2 || PW2=""
    echo
    [ "$PW" = "$PW2" ] || fail "두 번 입력한 비밀번호가 다릅니다."
  fi
fi

if [ -z "$PW" ]; then
  # 16진수만 써서 셸이나 gradle 이 헷갈릴 여지를 없앱니다.
  #
  # `tr -dc ... </dev/urandom | head -c N` 을 쓰면 안 됩니다. head 가 먼저
  # 끝나면서 tr 이 SIGPIPE 로 죽고, 이 스크립트의 pipefail 과 set -e 가 만나
  # 아무 메시지 없이 종료됩니다. od 는 입력을 다 읽고 정상 종료합니다.
  PW="$(od -An -tx1 -N 21 /dev/urandom | tr -d ' \n')"
  GENERATED=1
  echo
  echo "비밀번호를 자동으로 만들었습니다."
else
  [ ${#PW} -ge 6 ] || fail "비밀번호는 6자 이상이어야 합니다."
fi

if [ "$SECRETS_ONLY" = "1" ] && [ "$GENERATED" = "1" ]; then
  fail "--secrets-only 에는 기존 keystore 의 비밀번호가 필요합니다.
   KEYSTORE_PASSWORD='비밀번호' bash scripts/setup_keystore.sh --secrets-only"
fi

# --- 생성 ------------------------------------------------------------------

if [ "$SECRETS_ONLY" = "1" ]; then
  say "기존 keystore 를 씁니다 (새로 만들지 않습니다)"
else
say "keystore 를 만드는 중…"
# -dname 을 주면 이름·조직을 묻지 않고 바로 만듭니다. 개인용 서명키라
# 이 값들은 아무 의미가 없어서 고정해 둡니다.
"$KEYTOOL" -genkeypair \
  -keystore "$KEYSTORE_FILE" \
  -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$ALIAS" \
  -dname "CN=Photo Application, OU=Personal, O=hongsytop, L=Seoul, C=KR" \
  -storepass "$PW" -keypass "$PW" >/dev/null 2>&1

[ -s "$KEYSTORE_FILE" ] || fail "keystore 가 만들어지지 않았습니다."
fi

# 만들어진 키가 실제로 열리는지, 별칭이 맞는지 확인합니다.
FINGERPRINT="$("$KEYTOOL" -list -v -keystore "$KEYSTORE_FILE" -alias "$ALIAS" \
  -storepass "$PW" 2>/dev/null | grep 'SHA256:' | head -1 | sed 's/^[[:space:]]*//')"
[ -n "$FINGERPRINT" ] || fail "keystore 검증에 실패했습니다."

if [ "$SECRETS_ONLY" = "1" ]; then
  say "✅ keystore 확인 완료"
else
  say "✅ keystore 생성 완료"
fi
echo "   별칭: $ALIAS"
echo "   $FINGERPRINT"

# --- GitHub 시크릿 등록 ----------------------------------------------------

say "GitHub 시크릿을 등록하는 중…"
B64="$(base64 -w0 "$KEYSTORE_FILE")"

SECRETS_OK=1
set +e
gh secret set ANDROID_KEYSTORE_BASE64   --repo "$REPO" --body "$B64" 2>/dev/null || SECRETS_OK=0
gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO" --body "$PW"  2>/dev/null || SECRETS_OK=0
gh secret set ANDROID_KEY_ALIAS         --repo "$REPO" --body "$ALIAS" 2>/dev/null || SECRETS_OK=0
gh secret set ANDROID_KEY_PASSWORD      --repo "$REPO" --body "$PW"  2>/dev/null || SECRETS_OK=0
set -e

if [ "$SECRETS_OK" = "1" ]; then
  say "✅ 시크릿 4개 등록 완료"
  gh secret list --repo "$REPO" | grep -E 'ANDROID_' || true
else
  printf '%s' "$B64" > keystore.base64.txt

  # 웹 UI 에 붙여 넣을 값 네 개를 이름표와 함께 한 파일에 모아 둡니다.
  # base64 덩어리와 비밀번호를 따로 찾아 헤매지 않도록 하려는 것입니다.
  {
    echo "# GitHub 저장소 → Settings → Secrets and variables → Actions"
    echo "# → New repository secret 에서 아래 4개를 그대로 등록하세요."
    echo "# 이름은 대소문자까지 정확히 같아야 합니다."
    echo "#"
    echo "# 등록이 끝나면 이 파일과 keystore.base64.txt 는 지워도 됩니다."
    echo "# 단, upload-keystore.jks 와 비밀번호는 반드시 따로 보관하세요."
    echo
    echo "=== 1) ANDROID_KEYSTORE_PASSWORD ==="
    echo "$PW"
    echo
    echo "=== 2) ANDROID_KEY_PASSWORD ==="
    echo "$PW"
    echo
    echo "=== 3) ANDROID_KEY_ALIAS ==="
    echo "$ALIAS"
    echo
    echo "=== 4) ANDROID_KEYSTORE_BASE64 ==="
    echo "# 아래 한 줄 전체 (매우 깁니다). keystore.base64.txt 와 같은 내용입니다."
    echo "$B64"
  } > keystore-secrets.txt

  cat <<MSG

⚠️  시크릿 자동 등록에 실패했습니다. keystore 자체는 정상적으로 만들어졌습니다.

  등록할 값 4개를 keystore-secrets.txt 에 모아 두었습니다. 웹에서 직접
  등록하시려면 그 파일만 열면 됩니다.

  Codespaces 가 기본으로 주는 토큰은 권한이 좁은 통합(GitHub App) 토큰이라
  시크릿을 쓸 수 없습니다. gh auth refresh 로는 해결되지 않습니다 — 환경변수
  토큰을 쓰는 중에는 그 명령이 동작하지 않기 때문입니다. 환경변수를 걷어내고
  내 계정으로 다시 로그인해야 합니다.

  방법 1 — 다시 로그인한 뒤 시크릿만 등록 (권장)

      unset GITHUB_TOKEN GH_TOKEN
      gh auth login -h github.com -p https -w -s repo,workflow

    화면에 뜨는 8자리 코드를 브라우저에 입력해 승인하고, 그 다음:

      KEYSTORE_PASSWORD='$PW' bash scripts/setup_keystore.sh --secrets-only

  방법 2 — 웹에서 직접 등록

    keystore-secrets.txt 를 열어 4개를 순서대로 옮겨 담으세요.
    $REPO → Settings → Secrets and variables → Actions → New repository secret

MSG
fi

# --- 마무리 안내 -----------------------------------------------------------

cat <<MSG

────────────────────────────────────────────────────────────
지금 바로 해야 할 일

1. $KEYSTORE_FILE 를 내 컴퓨터로 내려받아 보관하세요.
   VS Code 왼쪽 파일 목록에서 파일을 오른쪽 클릭 → Download.

   Codespace 는 지워질 수 있는 임시 공간입니다. 이 파일을 잃으면 같은
   서명으로 업데이트할 방법이 영영 없습니다(앱을 지우고 새로 깔아야 하고
   그때 메모·태그·폴더도 사라집니다).

MSG

if [ "${GENERATED:-0}" = "1" ]; then
  cat <<MSG
2. 자동 생성된 비밀번호도 함께 보관하세요. 다시 볼 수 없습니다:

       $PW

MSG
else
  echo "2. 정한 비밀번호를 keystore 파일과 함께 보관하세요."
  echo
fi

cat <<MSG
3. 다음 빌드부터 이 키로 서명됩니다. Actions 로그의 "서명 keystore 준비"
   단계에 경고 대신 "✅ 업로드 keystore 로 서명합니다." 가 뜨면 성공입니다.
   "서명 확인" 단계의 SHA256 지문이 위와 같은지 보면 확실합니다.

   빌드를 돌리는 가장 확실한 방법은 커밋을 하나 밀어 넣는 것입니다
   (워크플로가 push 에서 돕니다):

       git commit --allow-empty -m "chore: 서명키 적용 빌드" && git push

   gh workflow run 은 Codespaces 기본 토큰 권한으로는 403 이 납니다.

주의: $KEYSTORE_FILE 는 .gitignore 에 들어 있어 커밋되지 않습니다.
      절대 저장소에 올리지 마세요.
────────────────────────────────────────────────────────────
MSG

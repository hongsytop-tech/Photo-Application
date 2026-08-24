#!/usr/bin/env python3
"""`flutter create` 가 만든 android/app/build.gradle.kts 에 릴리스 서명을 붙인다.

Flutter 기본 템플릿은 릴리스 빌드도 debug 키로 서명한다. debug 키는 빌드하는
기계마다 달라서, CI 가 매번 다른 키로 서명하면 폰에서 "앱이 설치되지 않음"이
뜨고 기존 앱 위에 업데이트가 안 된다.

그래서 android/key.properties 가 있으면 그 keystore 로 서명하도록 바꾼다.
없으면 debug 서명으로 두되 빌드는 성공시킨다 — keystore 를 아직 안 만든
사람도 첫 APK 를 받아볼 수 있어야 하기 때문이다. (이 경우 다음 빌드와 서명이
달라 덮어쓰기 설치는 안 된다는 점을 워크플로가 경고한다.)

패치 후 검증에 실패하면 비-0 으로 끝나 CI 를 멈춘다. 서명이 조용히 잘못되는
것이 가장 나쁜 결과이기 때문이다.
"""
import re
import sys
from pathlib import Path

# Gradle Kotlin DSL 안에서 `java` 는 패키지가 아니라 Gradle 의 java 확장으로
# 먼저 해석된다. 그래서 `java.util.Properties()` 라고 쓰면 "Unresolved
# reference 'util'" 로 스크립트 컴파일이 깨진다. 파일 맨 위에서 import 해야
# 한다 (Flutter 공식 서명 문서가 쓰는 방식).
IMPORTS = "import java.util.Properties\nimport java.io.FileInputStream\n\n"

# storeFile 을 만들 때 쓰는 file() 은 Project 의 메서드다. AGP 9 의 새 DSL
# 블록 안에서 이런 Project 스코프 호출이 어떻게 해석되는지는 버전마다 다르다.
# 값은 전부 여기 평범한 스크립트 스코프에서 만들어 두고, DSL 블록 안에서는
# 대입만 한다.
KEYSTORE_LOADER = '''
// key.properties 가 있으면 릴리스 서명에 쓴다 (CI 가 시크릿에서 만들어 둔다).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val keystoreFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
'''

SIGNING_CONFIGS = '''    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreFile
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

'''

# key.properties 가 없으면 debug 로 폴백 — 빌드 자체는 항상 성공한다.
RELEASE_SIGNING = (
    'signingConfig = if (hasKeystore) '
    'signingConfigs.getByName("release") else signingConfigs.getByName("debug")'
)


def find_block_end(content: str, pattern: str) -> int | None:
    """`pattern` 이 여는 중괄호까지 매치한다고 보고, 짝이 맞는 닫는 위치를 찾는다."""
    m = re.search(pattern, content)
    if not m:
        return None
    depth, i = 1, m.end()
    while i < len(content) and depth > 0:
        if content[i] == '{':
            depth += 1
        elif content[i] == '}':
            depth -= 1
        i += 1
    return i if depth == 0 else None


def patch(content: str) -> str:
    # import 는 반드시 파일 맨 위, plugins 블록보다 앞에 와야 한다.
    if 'import java.util.Properties' not in content:
        content = IMPORTS + content

    if 'keystorePropertiesFile' not in content:
        end = find_block_end(content, r'\bplugins\s*\{')
        if end is None:
            raise RuntimeError('plugins { } 블록을 찾지 못했습니다.')
        content = content[:end] + '\n' + KEYSTORE_LOADER + content[end:]

    # 'signingConfigs' 문자열만으로 판단하면 안 된다 — 템플릿의
    # signingConfigs.getByName("debug") 에 이미 들어 있어 오탐한다.
    if 'create("release")' not in content:
        content, n = re.subn(
            r'(\n[ \t]*buildTypes\s*\{)',
            '\n' + SIGNING_CONFIGS.rstrip('\n') + r'\1',
            content,
            count=1,
        )
        if n != 1:
            raise RuntimeError('buildTypes { } 블록을 찾지 못했습니다.')

    # 템플릿의 debug 서명 지정을 조건부로 교체 (공백·인용부호 변형 허용)
    content, n = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*["\']debug["\']\s*\)',
        RELEASE_SIGNING,
        content,
        count=1,
    )
    if n != 1 and RELEASE_SIGNING not in content:
        raise RuntimeError('buildTypes.release 의 debug 서명 지정을 찾지 못했습니다.')
    return content


def verify(content: str) -> None:
    checks = {
        'Properties import': 'import java.util.Properties' in content,
        'FileInputStream import': 'import java.io.FileInputStream' in content,
        'import 가 plugins 앞에 위치': (
            content.index('import java.util.Properties') < content.index('plugins')
            if 'plugins' in content else True
        ),
        'java.util 직접 참조 없음': 'java.util.Properties()' not in content,
        'keystoreProperties 로딩': 'keystorePropertiesFile' in content,
        'hasKeystore 플래그': 'val hasKeystore' in content,
        'file() 호출이 DSL 블록 밖': 'val keystoreFile' in content,
        'release signingConfig 정의': 'create("release")' in content,
        'buildTypes.release 가 release 서명을 참조': (
            'signingConfigs.getByName("release")' in content
        ),
        'debug 무조건 서명이 남아있지 않음': not re.search(
            r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*"debug"\s*\)\s*$',
            content,
            re.M,
        ),
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        print('❌ 서명 패치 검증 실패:', file=sys.stderr)
        for name in failed:
            print(f'   - {name}', file=sys.stderr)
        raise RuntimeError('signing patch verification failed')


def main() -> None:
    path = Path('android/app/build.gradle.kts')
    if not path.exists():
        print(
            "❌ android/app/build.gradle.kts 가 없습니다. "
            "먼저 'flutter create . --platforms=android' 를 실행하세요.",
            file=sys.stderr,
        )
        sys.exit(1)

    patched = patch(path.read_text())
    verify(patched)
    path.write_text(patched)

    signed = Path('android/key.properties').exists()
    print(
        f"✅ 서명 설정 패치 완료 — 이번 빌드는 "
        f"{'업로드 keystore' if signed else 'debug 키(임시)'} 로 서명됩니다."
    )


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""flutter_create로 생성된 android/app/build.gradle(.kts)에 release 서명 설정을 추가.

견고성을 위해:
- 정규식으로 'debug' 서명 라인을 매칭 (공백·인용부호 차이에 강함)
- 패치 후 release 서명이 실제로 적용됐는지 검증
- 검증 실패 시 비-0 종료 → CI 빌드 중단

이렇게 해야 매 빌드가 일관된 keystore로 서명되어 폰에서 업데이트가 정상 작동.
"""
import re
import sys
from pathlib import Path


def find_plugins_block_end(content: str) -> int | None:
    m = re.search(r"\bplugins\s*\{", content)
    if not m:
        return None
    depth = 1
    i = m.end()
    while i < len(content) and depth > 0:
        c = content[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return i if depth == 0 else None


def insert_after_plugins(content: str, code: str) -> str:
    end = find_plugins_block_end(content)
    if end is None:
        return code + content
    return content[:end] + "\n\n" + code + content[end:]


KTS_KEYSTORE = (
    "val keystoreProperties = java.util.Properties()\n"
    'val keystorePropertiesFile = rootProject.file("key.properties")\n'
    "if (keystorePropertiesFile.exists()) {\n"
    "    keystoreProperties.load(java.io.FileInputStream(keystorePropertiesFile))\n"
    "}\n"
)

KTS_SIGNING = (
    "    signingConfigs {\n"
    '        create("release") {\n'
    '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
    '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
    '            storeFile = keystoreProperties["storeFile"]?.let { file(it) }\n'
    '            storePassword = keystoreProperties["storePassword"] as String?\n'
    "        }\n"
    "    }\n"
)

GROOVY_KEYSTORE = (
    "def keystoreProperties = new Properties()\n"
    "def keystorePropertiesFile = rootProject.file('key.properties')\n"
    "if (keystorePropertiesFile.exists()) {\n"
    "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
    "}\n"
)

GROOVY_SIGNING = (
    "    signingConfigs {\n"
    "        release {\n"
    "            keyAlias keystoreProperties['keyAlias']\n"
    "            keyPassword keystoreProperties['keyPassword']\n"
    "            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null\n"
    "            storePassword keystoreProperties['storePassword']\n"
    "        }\n"
    "    }\n"
)


def patch_kts(content: str) -> str:
    if "keystoreProperties" in content and "signingConfigs.getByName(\"release\")" in content:
        return content  # already patched

    if "keystoreProperties" not in content:
        content = insert_after_plugins(content, KTS_KEYSTORE)
    if "create(\"release\")" not in content:
        content = re.sub(
            r"(\n\s*buildTypes\s*\{)",
            "\n" + KTS_SIGNING + r"\1",
            content,
            count=1,
        )
    # debug → release (다양한 공백·인용부호 변형 모두 처리)
    content = re.sub(
        r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*["\']debug["\']\s*\)',
        'signingConfig = signingConfigs.getByName("release")',
        content,
    )
    return content


def patch_groovy(content: str) -> str:
    if "keystoreProperties" in content and "signingConfigs.release" in content:
        return content

    if "keystoreProperties" not in content:
        content = insert_after_plugins(content, GROOVY_KEYSTORE)
    if "signingConfigs {" not in content or "release {" not in content:
        content = re.sub(
            r"(\n\s*buildTypes\s*\{)",
            "\n" + GROOVY_SIGNING + r"\1",
            content,
            count=1,
        )
    # debug → release (Groovy: with or without '=')
    content = re.sub(
        r"signingConfig\s+signingConfigs\.debug\b",
        "signingConfig signingConfigs.release",
        content,
    )
    content = re.sub(
        r"signingConfig\s*=\s*signingConfigs\.debug\b",
        "signingConfig = signingConfigs.release",
        content,
    )
    return content


def verify(content: str, path: Path) -> None:
    """release 서명 설정이 실제로 적용됐는지 확인 — 실패 시 RuntimeError."""
    checks = {
        "keystoreProperties 선언": "keystoreProperties" in content,
        "release signingConfig 정의": (
            'create("release")' in content or "release {" in content
        ),
        "buildTypes.release가 release 서명 참조": (
            'signingConfigs.getByName("release")' in content
            or "signingConfigs.release" in content
        ),
        "buildTypes.release가 더 이상 debug 서명을 참조하지 않음": not bool(
            re.search(
                r"buildTypes\s*\{[\s\S]{0,500}?release\s*\{[\s\S]{0,300}?signingConfig[^=\n]*=?\s*signingConfigs[.\\]\s*(?:getByName\(\s*[\"']debug[\"']\s*\)|debug)",
                content,
            )
        ),
    }
    failed = [name for name, ok in checks.items() if not ok]
    if failed:
        print(f"❌ {path} 서명 패치 검증 실패:", file=sys.stderr)
        for name in failed:
            print(f"   - {name}", file=sys.stderr)
        print("\n--- 현재 build.gradle 일부 ---", file=sys.stderr)
        # buildTypes 블록 전후만 출력
        m = re.search(r"buildTypes\s*\{[\s\S]{0,800}", content)
        if m:
            print(m.group(0), file=sys.stderr)
        raise RuntimeError("signing patch verification failed")


def main() -> None:
    candidates = [
        Path("android/app/build.gradle.kts"),
        Path("android/app/build.gradle"),
    ]
    for path in candidates:
        if path.exists():
            original = path.read_text()
            if path.suffix == ".kts":
                patched = patch_kts(original)
            else:
                patched = patch_groovy(original)
            path.write_text(patched)
            verify(patched, path)
            print(f"✅ {path} 서명 설정 패치 + 검증 통과")
            return
    print(
        "❌ android/app/build.gradle(.kts) not found. Run 'flutter create .' first.",
        file=sys.stderr,
    )
    sys.exit(1)


if __name__ == "__main__":
    main()

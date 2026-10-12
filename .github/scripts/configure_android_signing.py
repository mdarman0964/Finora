#!/usr/bin/env python3
"""Configure a stable Android release signing key from GitHub Actions secrets.

The keystore and key.properties are written only to the CI runner and are
ignored by git. If secrets are absent, leave Flutter's temporary CI signing
configuration untouched so pull-request checks can still run.
"""
import base64
import os
from pathlib import Path
import re
import sys

encoded = os.environ.get("ANDROID_KEYSTORE_BASE64", "").strip()
store_password = os.environ.get("ANDROID_KEYSTORE_PASSWORD", "")
key_alias = os.environ.get("ANDROID_KEY_ALIAS", "")
key_password = os.environ.get("ANDROID_KEY_PASSWORD", "")

if not all((encoded, store_password, key_alias, key_password)):
    print("::warning::Android release signing secrets are incomplete; this build will use the generated CI signing configuration, not a stable release key.")
    sys.exit(0)

android = Path("android")
app = android / "app"
keystore = app / "upload-keystore.jks"
try:
    keystore.write_bytes(base64.b64decode(encoded, validate=True))
except Exception as exc:
    print(f"::error::ANDROID_KEYSTORE_BASE64 is not valid base64: {exc}")
    sys.exit(1)

(android / "key.properties").write_text(
    "storePassword=" + store_password + "\n"
    + "keyPassword=" + key_password + "\n"
    + "keyAlias=" + key_alias + "\n"
    + "storeFile=upload-keystore.jks\n",
    encoding="utf-8",
)

kts = app / "build.gradle.kts"
groovy = app / "build.gradle"

if kts.exists():
    content = kts.read_text(encoding="utf-8")
    imports = "import java.io.FileInputStream\nimport java.util.Properties\n\n"
    if "val keystoreProperties = Properties()" not in content:
        content = imports + content
        marker = "plugins {"
        if marker not in content:
            sys.exit("::error::Could not find plugins block in build.gradle.kts")
        content = content.replace(
            marker,
            'val keystoreProperties = Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) {\n'
            '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
            '}\n\n' + marker,
            1,
        )
    if 'create("release")' not in content:
        content = re.sub(
            r'(?m)^\s*buildTypes\s*\{',
            '    signingConfigs {\n'
            '        create("release") {\n'
            '            keyAlias = keystoreProperties["keyAlias"] as String\n'
            '            keyPassword = keystoreProperties["keyPassword"] as String\n'
            '            storeFile = file(keystoreProperties["storeFile"] as String)\n'
            '            storePassword = keystoreProperties["storePassword"] as String\n'
            '        }\n'
            '    }\n\n    buildTypes {',
            content,
            count=1,
        )
    content = content.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = signingConfigs.getByName("release")',
    )
    if 'signingConfig = signingConfigs.getByName("release")' not in content:
        content = re.sub(
            r'(?m)(buildTypes\s*\{\s*release\s*\{)',
            r'\1\n            signingConfig = signingConfigs.getByName("release")',
            content,
            count=1,
        )
    kts.write_text(content, encoding="utf-8")
elif groovy.exists():
    content = groovy.read_text(encoding="utf-8")
    if "keystoreProperties = new Properties()" not in content:
        content = (
            "def keystoreProperties = new Properties()\n"
            "def keystorePropertiesFile = rootProject.file('key.properties')\n"
            "if (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n"
            + content
        )
    if not re.search(r"signingConfigs\s*\{\s*release\s*\{", content):
        content = re.sub(
            r"(?m)^\s*buildTypes\s*\{",
            "    signingConfigs {\n"
            "        release {\n"
            "            keyAlias keystoreProperties['keyAlias']\n"
            "            keyPassword keystoreProperties['keyPassword']\n"
            "            storeFile file(keystoreProperties['storeFile'])\n"
            "            storePassword keystoreProperties['storePassword']\n"
            "        }\n"
            "    }\n\n    buildTypes {",
            content,
            count=1,
        )
    content = content.replace("signingConfig signingConfigs.debug", "signingConfig signingConfigs.release")
    if "signingConfig signingConfigs.release" not in content:
        content = re.sub(
            r"(?m)(buildTypes\s*\{\s*release\s*\{)",
            r"\1\n            signingConfig signingConfigs.release",
            content,
            count=1,
        )
    groovy.write_text(content, encoding="utf-8")
else:
    sys.exit("::error::Generated Android app build.gradle(.kts) was not found")

print("Android release signing configured from GitHub Secrets.")

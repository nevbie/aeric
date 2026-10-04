#!/usr/bin/env python3
"""Adds aeric's settings to the platform folders that `flutter create` generates
(so the repo only needs lib/, test/ and pubspec.yaml)."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------- Android
manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    m = manifest.read_text()
    if "android.permission.INTERNET" not in m:
        m = re.sub(r"(<manifest[^>]*>\n)",
                   lambda g: g.group(1) + '    <uses-permission android:name="android.permission.INTERNET"/>\n',
                   m, count=1)
    m = re.sub(r'android:label="[^"]*"', 'android:label="aeric"', m, count=1)
    manifest.write_text(m)
    print("patched", manifest)

# ---------------------------------------------------------------- iOS
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    s = plist.read_text()
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1aeric\2", s)
    plist.write_text(s)
    print("patched", plist)

# The default counter-app test from `flutter create` does not apply to aeric.
default_test = root / "test/widget_test.dart"
if default_test.exists():
    default_test.unlink()
    print("removed", default_test)

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
    perms = [
        "android.permission.INTERNET",
        # GPS for the flight instruments and recording, also with the screen off.
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.WAKE_LOCK",
        # Barometer at more than 200 Hz is not needed, but some devices gate fast sensors.
        "android.permission.HIGH_SAMPLING_RATE_SENSORS",
        # Bluetooth varios.
        "android.permission.BLUETOOTH_SCAN",
        "android.permission.BLUETOOTH_CONNECT",
        # QR codes of competition tasks.
        "android.permission.CAMERA",
    ]
    add = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
    m = re.sub(r"(<manifest[^>]*>\n)", lambda g: g.group(1) + add, m, count=1)
    if "TTS_SERVICE" not in m:
        tts = ('        <intent>\n'
               '            <action android:name="android.intent.action.TTS_SERVICE"/>\n'
               '        </intent>\n')
        if "<queries>" in m:
            m = m.replace("<queries>\n", "<queries>\n" + tts, 1)
        else:
            m = m.replace("</manifest>", "    <queries>\n" + tts + "    </queries>\n</manifest>")
    m = re.sub(r'android:label="[^"]*"', 'android:label="aeric"', m, count=1)
    manifest.write_text(m)
    print("patched", manifest)

# Some plugins (e.g. flutter_pcm_sound) still compile against API 33, but newer AndroidX
# dependencies (androidx.exifinterface via file_picker) need every module on API 34+.
# Raise compileSdk of all plugin modules; registered before evaluationDependsOn(":app").
COMPILE_SDK = 36
kts = root / "android/build.gradle.kts"
groovy = root / "android/build.gradle"
marker = "aeric: raise plugin compileSdk"
if kts.exists() and marker not in kts.read_text():
    s = kts.read_text()
    block = f"""// {marker}
subprojects {{
    if (name != "app") {{
        val raise: Project.() -> Unit = {{
            extensions.findByName("android")?.withGroovyBuilder {{ "compileSdkVersion"({COMPILE_SDK}) }}
        }}
        if (state.executed) raise() else afterEvaluate {{ raise() }}
    }}
}}
"""
    anchor = "subprojects {\n    project.evaluationDependsOn"
    s = s.replace(anchor, block + anchor, 1) if anchor in s else s + "\n" + block
    kts.write_text(s)
    print("patched", kts)
elif groovy.exists() and marker not in groovy.read_text():
    s = groovy.read_text()
    block = f"""// {marker}
subprojects {{ p ->
    if (p.name != "app") {{
        def raise = {{ if (p.extensions.findByName("android") != null) p.android.compileSdkVersion({COMPILE_SDK}) }}
        if (p.state.executed) raise() else p.afterEvaluate {{ raise() }}
    }}
}}
"""
    anchor = "subprojects {\n    project.evaluationDependsOn"
    s = s.replace(anchor, block + anchor, 1) if anchor in s else s + "\n" + block
    groovy.write_text(s)
    print("patched", groovy)

# ---------------------------------------------------------------- iOS
plist = root / "ios/Runner/Info.plist"
if plist.exists():
    s = plist.read_text()
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1aeric\2", s)
    entries = {
        "NSLocationWhenInUseUsageDescription": "aeric uses your location for the flight instruments and to record your flights.",
        "NSLocationAlwaysAndWhenInUseUsageDescription": "aeric keeps recording your flight and the vario running when the screen is off.",
        "NSMotionUsageDescription": "aeric uses the barometer (altimeter) for the variometer.",
        "NSBluetoothAlwaysUsageDescription": "aeric connects to your Bluetooth vario (XC Tracer, Skytraxx, FlyMaster …).",
        "NSCameraUsageDescription": "aeric scans the QR code of competition tasks.",
    }
    extra = "".join(f"\t<key>{k}</key>\n\t<string>{v}</string>\n" for k, v in entries.items() if k not in s)
    if "UIBackgroundModes" not in s:
        extra += "\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>\n\t\t<string>audio</string>\n\t\t<string>bluetooth-central</string>\n\t</array>\n"
    idx = s.rfind("</dict>")
    s = s[:idx] + extra + s[idx:]
    plist.write_text(s)
    print("patched", plist)

# The default counter-app test from `flutter create` does not apply to aeric.
default_test = root / "test/widget_test.dart"
if default_test.exists():
    default_test.unlink()
    print("removed", default_test)

# ---------------------------------------------------------------- Release signing
# CI writes android/key.properties (+ the keystore) from GitHub secrets. Without it the release
# APK is signed with a throwaway debug key, so updates would not install over earlier builds.
app_gradle = root / "android/app/build.gradle.kts"
sign_marker = "release signing from key.properties"
if app_gradle.exists() and sign_marker not in app_gradle.read_text():
    g = app_gradle.read_text()
    # Kotlin DSL: only imports may precede the plugins block, so the properties go after it.
    props = ("\n"
             f"// {sign_marker}\n"
             "val keystoreProperties = Properties()\n"
             "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
             "val hasReleaseKeystore = keystorePropertiesFile.exists()\n"
             "if (hasReleaseKeystore) {\n"
             "    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }\n"
             "}\n")
    signing = ("    signingConfigs {\n"
               "        if (hasReleaseKeystore) {\n"
               "            create(\"release\") {\n"
               "                keyAlias = keystoreProperties.getProperty(\"keyAlias\")\n"
               "                keyPassword = keystoreProperties.getProperty(\"keyPassword\")\n"
               "                storeFile = file(keystoreProperties.getProperty(\"storeFile\"))\n"
               "                storePassword = keystoreProperties.getProperty(\"storePassword\")\n"
               "            }\n"
               "        }\n"
               "    }\n\n"
               "    buildTypes {\n")
    plugins_end = g.find("\n}\n", g.find("plugins {"))
    if (g.find("plugins {") < 0 or plugins_end < 0 or "    buildTypes {\n" not in g
            or 'signingConfig = signingConfigs.getByName("debug")' not in g):
        print("::warning::patch_platforms: unexpected android/app/build.gradle.kts layout, release signing not added")
    else:
        g = "import java.util.Properties\n\n" + g[:plugins_end + 3] + props + g[plugins_end + 3:]
        g = g.replace("    buildTypes {\n", signing, 1)
        g = g.replace('signingConfig = signingConfigs.getByName("debug")',
                      'signingConfig = signingConfigs.getByName(if (hasReleaseKeystore) "release" else "debug")', 1)
        app_gradle.write_text(g)
        print("patched", app_gradle, "(release key)" if (root / "android/key.properties").exists() else "(no key.properties: debug key)")

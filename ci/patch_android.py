"""Донастройва Android частта, която `flutter create` създава в GitHub.

- известия: разрешения и приемници за планирани напомняния и след рестарт;
- desugaring и compileSdk, нужни на flutter_local_notifications.
Скриптът може да се пуска многократно – не добавя нищо два пъти.
"""
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
manifest = root / "android/app/src/main/AndroidManifest.xml"
gradle = root / "android/app/build.gradle.kts"

# ---------------------------------------------------------------- manifest
m = manifest.read_text(encoding="utf-8")
m = m.replace('android:label="svestenik"', 'android:label="Свещеник"')

permissions = """
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" android:maxSdkVersion="32"/>
"""
receivers = """
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""
if "RECEIVE_BOOT_COMPLETED" not in m:
    m = re.sub(r"(<manifest[^>]*>)", r"\1" + permissions.replace("\\", "\\\\"), m, count=1)
if "ScheduledNotificationReceiver" not in m:
    m = m.replace("</application>", receivers + "    </application>", 1)
manifest.write_text(m, encoding="utf-8")

# ---------------------------------------------------------------- gradle
g = gradle.read_text(encoding="utf-8")
if "isCoreLibraryDesugaringEnabled" not in g:
    g, n = re.subn(r"compileOptions\s*\{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", g, count=1)
    if n == 0:
        g = g.replace("android {", "android {\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }", 1)
if "multiDexEnabled" not in g:
    g = re.sub(r"defaultConfig\s*\{", "defaultConfig {\n        multiDexEnabled = true", g, count=1)
# Известията искат поне compileSdk 37.
g = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion",
           "compileSdk = maxOf(flutter.compileSdkVersion, 37)", g)
if "desugar_jdk_libs" not in g:
    g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
gradle.write_text(g, encoding="utf-8")

print("---- AndroidManifest.xml ----")
print(m)
print("---- build.gradle.kts ----")
print(g)

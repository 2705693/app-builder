import glob
from pathlib import Path

# 1. 注入 AndroidManifest 权限与明文网络传输
for mf in glob.glob("android/app/src/main/AndroidManifest.xml"):
    p = Path(mf)
    c = p.read_text(encoding="utf-8")
    perms = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
"""
    if "<uses-permission" not in c:
        c = c.replace("<application", perms + "\n    <application", 1)
    if 'android:usesCleartextTraffic="true"' not in c:
        c = c.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
    p.write_text(c, encoding="utf-8")
    print("Updated permissions in:", mf)

# 2. 确保 app 的 minSdk 为 21
for bg in glob.glob("android/app/build.gradle*"):
    p = Path(bg)
    s = p.read_text(encoding="utf-8")
    s = s.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 21")
    s = s.replace("minSdkVersion = flutter.minSdkVersion", "minSdkVersion = 21")
    s = s.replace("minSdk flutter.minSdkVersion", "minSdk 21")
    s = s.replace("minSdk = flutter.minSdkVersion", "minSdk = 21")
    p.write_text(s, encoding="utf-8")
    print("Updated minSdk to 21 in:", bg)

print("Android configuration fixed successfully!")

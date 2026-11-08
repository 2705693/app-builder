import glob
import re
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
    c = re.sub(r'android:label="[^"]*"', 'android:label="一链取影"', c, count=1)
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

# 3. GitHub Actions 会重建 android/，因此在这里重新注入 MP3 保存到系统下载目录的通道。
main_activity = Path(
    "android/app/src/main/kotlin/com/sd0739/chaoji_huiwan/MainActivity.kt"
)
main_activity.parent.mkdir(parents=True, exist_ok=True)
main_activity.write_text(
    r'''package com.sd0739.chaoji_huiwan

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val channelName = "com.sd0739.chaoji_huiwan/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method != "saveAudioToDownloads") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("filePath")
            val displayName = call.argument<String>("displayName") ?: "audio.mp3"
            if (sourcePath.isNullOrBlank()) {
                result.error("INVALID_PATH", "音频临时文件不存在", null)
                return@setMethodCallHandler
            }
            try {
                result.success(saveAudio(File(sourcePath), displayName))
            } catch (error: Exception) {
                result.error("SAVE_FAILED", error.message ?: "保存音频失败", null)
            }
        }
    }

    private fun saveAudio(source: File, displayName: String): String {
        require(source.exists()) { "音频临时文件不存在" }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "audio/mpeg")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/一链取影")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("无法创建系统下载文件")
            try {
                resolver.openOutputStream(uri)?.use { output ->
                    FileInputStream(source).use { input -> input.copyTo(output) }
                } ?: error("无法写入系统下载文件")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                return uri.toString()
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        }

        val directory = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!directory.exists()) directory.mkdirs()
        val target = File(directory, displayName)
        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output -> input.copyTo(output) }
        }
        return target.absolutePath
    }
}
''',
    encoding="utf-8",
)
print("Injected audio MediaStore channel into:", main_activity)

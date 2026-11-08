package com.sd0739.chaoji_huiwan

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
            // 文件复制必须离开 Android 主线程，否则较大的音频会阻塞 Flutter
            // 渲染并出现黑屏或“应用无响应”。结果再切回主线程回传。
            Thread {
                try {
                    val savedPath = saveAudio(File(sourcePath), displayName)
                    runOnUiThread { result.success(savedPath) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("SAVE_FAILED", error.message ?: "保存音频失败", null)
                    }
                }
            }.start()
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

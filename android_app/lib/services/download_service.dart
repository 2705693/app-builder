import 'dart:io';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

typedef DownloadProgressCallback = void Function(int received, int total, double progress);

class DownloadService {
  static const MethodChannel _mediaChannel = MethodChannel('com.sd0739.chaoji_huiwan/media');
  final Dio _dio = Dio();
  CancelToken? _cancelToken;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<bool> saveLocalVideo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('本地视频文件不存在');
    final result = await ImageGallerySaverPlus.saveFile(filePath);
    if (result is Map && result['isSuccess'] == false) {
      throw Exception('相册写入失败，请检查权限');
    }
    return true;
  }

  // 下载 MP3 并写入 Android 系统“下载”目录。
  Future<String> downloadAndSaveAudio({
    required String audioUrl,
    String? filename,
    required DownloadProgressCallback onProgress,
  }) async {
    _isDownloading = true;
    _cancelToken = CancelToken();
    final safeName = (filename == null || filename.trim().isEmpty)
        ? 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3'
        : (filename.toLowerCase().endsWith('.mp3') ? filename : '$filename.mp3');
    final normalizedName = safeName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/$normalizedName';

    try {
      await _dio.download(
        audioUrl,
        tempPath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          onProgress(received, total, total > 0 ? received / total : 0);
        },
      );
      final savedUri = await _mediaChannel.invokeMethod<String>('saveAudioToDownloads', {
        'filePath': tempPath,
        'displayName': normalizedName,
      });
      if (savedUri == null || savedUri.isEmpty) throw Exception('系统下载目录写入失败');
      return savedUri;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw Exception('已停止下载');
      throw Exception('音频下载失败: ${e.message}');
    } finally {
      _isDownloading = false;
      _cancelToken = null;
      final temp = File(tempPath);
      if (await temp.exists()) await temp.delete();
    }
  }

  // 停止 / 取消当前下载任务
  void cancelDownload() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel("用户主动停止下载");
    }
    _isDownloading = false;
    _cancelToken = null;
  }

  // 下载视频并存入手机系统相册 (DCIM/Photos)
  Future<bool> downloadAndSaveVideo({
    required String videoUrl,
    required DownloadProgressCallback onProgress,
  }) async {
    _isDownloading = true;
    _cancelToken = CancelToken();

    try {
      // 1. 检查或申请相册访问与写入权限
      if (Platform.isAndroid) {
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      }

      // 2. 准备本地临时文件路径
      final tempDir = await getTemporaryDirectory();
      final tempFilePath = '${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';

      // 3. 开始高速流式下载
      await _dio.download(
        videoUrl,
        tempFilePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          double progress = 0.0;
          if (total > 0) {
            progress = received / total;
          }
          onProgress(received, total, progress);
        },
      );

      // 4. 将临时文件写入系统原生相册
      await ImageGallerySaverPlus.saveFile(tempFilePath);

      // 5. 清理临时文件
      final file = File(tempFilePath);
      if (await file.exists()) {
        await file.delete();
      }

      _isDownloading = false;
      _cancelToken = null;
      return true;
    } on DioException catch (e) {
      _isDownloading = false;
      _cancelToken = null;
      if (CancelToken.isCancel(e)) {
        return false; // 用户主动取消，不视为错误
      }
      throw Exception('网络下载异常: ${e.message}');
    } catch (e) {
      _isDownloading = false;
      _cancelToken = null;
      rethrow;
    }
  }

  // 批量下载图集并存入系统相册
  Future<int> downloadAndSaveImages({
    required List<String> imageUrls,
    required Function(int current, int total) onProgress,
  }) async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        await Permission.storage.request();
      }
    }

    final tempDir = await getTemporaryDirectory();
    int successCount = 0;

    for (int i = 0; i < imageUrls.length; i++) {
      try {
        final url = imageUrls[i];
        final tempPath = '${tempDir.path}/img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await _dio.download(url, tempPath);
        await ImageGallerySaverPlus.saveFile(tempPath);
        final file = File(tempPath);
        if (await file.exists()) {
          await file.delete();
        }
        successCount++;
        onProgress(successCount, imageUrls.length);
      } catch (_) {}
    }

    return successCount;
  }
}

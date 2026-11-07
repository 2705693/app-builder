import 'dart:io';
import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

typedef DownloadProgressCallback = void Function(int received, int total, double progress);

class DownloadService {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

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
      bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        hasAccess = await Gal.requestAccess();
        if (!hasAccess) {
          throw Exception('未授予相册存储权限，无法保存视频');
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
      await Gal.putVideo(tempFilePath, album: '钞机汇玩');

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
    bool hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      hasAccess = await Gal.requestAccess();
      if (!hasAccess) {
        throw Exception('未授予相册存储权限');
      }
    }

    final tempDir = await getTemporaryDirectory();
    int successCount = 0;

    for (int i = 0; i < imageUrls.length; i++) {
      try {
        final url = imageUrls[i];
        final tempPath = '${tempDir.path}/img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        await _dio.download(url, tempPath);
        await Gal.putImage(tempPath, album: '钞机汇玩');
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

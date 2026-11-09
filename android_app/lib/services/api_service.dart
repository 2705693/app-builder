import 'dart:io';
import 'package:dio/dio.dart';
import '../models/parse_result.dart';

class ApiService {
  static const String baseUrl = 'https://sy.sd0739.top';
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 45),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'Accept': 'application/json',
      'User-Agent': 'ChaojiHuiwan-Android/1.0',
    },
  ));

  // 1. 全平台视频/图集解析接口
  Future<ParseResult> parseUrl(String text, {String? userId}) async {
    final response = await _dio.post('/api/parse', data: {
      'url': text,
      'text': text,
      'user_id': userId ?? 'android-user-default',
    });

    if (response.statusCode != 200) {
      throw Exception('网络请求异常 (HTTP ${response.statusCode})');
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw Exception('服务器返回格式错误');
    }

    if (data['code'] != 0) {
      throw Exception(data['message'] ?? data['msg'] ?? '解析失败，请检查链接');
    }

    final resData = Map<String, dynamic>.from(data['data'] ?? {});

    // 补齐相对路径代理 URL 为完整 HTTPS 域名
    String videoUrl = (resData['video_url'] ?? '').toString();
    if (videoUrl.startsWith('/')) {
      videoUrl = '$baseUrl$videoUrl';
    }

    String originUrl = (resData['origin_url'] ?? '').toString();
    if (originUrl.startsWith('/')) {
      originUrl = '$baseUrl$originUrl';
    }

    String coverUrl = (resData['cover_url'] ?? resData['cover'] ?? '').toString();
    if (coverUrl.startsWith('/')) {
      coverUrl = '$baseUrl$coverUrl';
    }

    List<String> images = [];
    if (resData['images'] is List) {
      for (var img in resData['images']) {
        String s = img.toString();
        if (s.startsWith('/')) {
          s = '$baseUrl$s';
        }
        images.add(s);
      }
    }

    resData['video_url'] = videoUrl;
    resData['origin_url'] = originUrl;
    resData['cover_url'] = coverUrl;
    resData['images'] = images;

    return ParseResult.fromJson(resData);
  }

  // 2. 提交意见反馈
  Future<bool> submitFeedback({
    required String content,
    String? contact,
    String? userId,
  }) async {
    final response = await _dio.post('/api/feedback', data: {
      'content': content,
      'contact': contact ?? '',
      'user_id': userId ?? 'android-user',
      'source': 'android_app',
    });

    return response.statusCode == 200;
  }

  // 3. 上传图片局部修复接口 (OpenCV Inpainting)
  Future<String> inpaintImage({
    required File imageFile,
    required File maskFile,
    String radius = '5',
  }) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(imageFile.path, filename: 'image.jpg'),
      'mask': await MultipartFile.fromFile(maskFile.path, filename: 'mask.png'),
      'radius': radius,
    });

    final response = await _dio.post('/api/image/inpaint', data: formData);
    if (response.statusCode == 200 && response.data != null) {
      final res = response.data;
      if (res['code'] == 0 && res['data'] != null) {
        String resultUrl = res['data']['result_url'] ?? '';
        if (resultUrl.startsWith('/')) {
          resultUrl = '$baseUrl$resultUrl';
        }
        return resultUrl;
      }
      throw Exception(res['message'] ?? '修复失败');
    }
    throw Exception('图片修复服务异常');
  }

  Future<String> portraitMatting({
    required File imageFile,
    required String userId,
    required String backgroundColor,
  }) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(imageFile.path, filename: 'portrait.jpg'),
      'user_id': userId,
      'bg_color': backgroundColor,
    });
    try {
      final response = await _dio.post(
        '/api/image/portrait_matting',
        data: form,
        options: Options(sendTimeout: const Duration(minutes: 2), receiveTimeout: const Duration(minutes: 2)),
      );
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        final payload = body['data'] is Map ? Map<String, dynamic>.from(body['data']) : <String, dynamic>{};
        var url = (payload['url'] ?? '').toString();
        if (url.startsWith('/')) url = '$baseUrl$url';
        if (url.isNotEmpty) return url;
      }
      throw Exception(body is Map ? (body['detail'] ?? body['message'] ?? '人像抠图失败') : '人像抠图失败');
    } on DioException catch (error) {
      final body = error.response?.data;
      throw Exception(body is Map ? (body['detail'] ?? body['message'] ?? '人像抠图服务连接失败') : '人像抠图服务连接失败');
    }
  }

  // 4. 同步用户额度信息
  Future<Map<String, dynamic>> fetchUserInfo(String userId) async {
    try {
      final response = await _dio.get('/api/user/info', queryParameters: {'user_id': userId});
      if (response.statusCode == 200 && response.data != null) {
        return Map<String, dynamic>.from(response.data['data'] ?? {});
      }
    } catch (_) {}
    return {
      'total_quota': 10,
      'bonus_quota': 0,
      'is_vip': false,
    };
  }

  Future<Map<String, dynamic>> consumeQuota({
    required String userId,
    required String feature,
  }) async {
    try {
      final response = await _dio.post('/api/quota/consume', data: {
        'user_id': userId,
        'feature': feature,
      });
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        return Map<String, dynamic>.from(body['data'] ?? {});
      }
      throw Exception(body is Map ? (body['message'] ?? '今日可用次数已用尽') : '额度扣减失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null ? data['detail'].toString() : '额度服务连接失败');
    }
  }

  // 5. 使用授权卡密增加次数或开通不限次服务
  Future<String> redeemCard({
    required String userId,
    required String cardKey,
  }) async {
    try {
      final response = await _dio.post('/api/user/redeem', data: {
        'user_id': userId,
        'card_key': cardKey.trim(),
      });
      final data = response.data;
      if (response.statusCode == 200 && data is Map && data['code'] == 0) {
        return (data['message'] ?? '兑换成功，额度已到账').toString();
      }
      throw Exception('兑换失败，请检查卡密');
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        throw Exception(data['detail'].toString());
      }
      throw Exception('连接服务器失败，请稍后重试');
    }
  }

  Future<String> createRecoveryCode(String userId) async {
    try {
      final response = await _dio.post('/api/auth/recovery/create', data: {'user_id': userId});
      final data = Map<String, dynamic>.from(response.data['data'] ?? {});
      final code = (data['recovery_code'] ?? '').toString();
      if (response.data['code'] == 0 && code.isNotEmpty) return code;
      throw Exception(response.data['message'] ?? '恢复码生成失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null ? data['detail'].toString() : '连接服务器失败');
    }
  }

  Future<Map<String, dynamic>> restoreRecoveryCode(String recoveryCode) async {
    try {
      final response = await _dio.post('/api/auth/recovery/restore', data: {
        'recovery_code': recoveryCode.trim(),
      });
      if (response.data['code'] == 0) {
        return Map<String, dynamic>.from(response.data['data'] ?? {});
      }
      throw Exception(response.data['message'] ?? '账号恢复失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null ? data['detail'].toString() : '连接服务器失败');
    }
  }

  Future<Map<String, dynamic>> recoverAccount({
    required String currentUserId,
    required String credential,
  }) async {
    try {
      final response = await _dio.post('/api/auth/account/recover', data: {
        'current_user_id': currentUserId,
        'credential': credential.trim(),
        'bind_wechat': false,
      });
      if (response.data['code'] == 0) {
        return Map<String, dynamic>.from(response.data['data'] ?? {});
      }
      throw Exception(response.data['message'] ?? '账号找回失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null
          ? data['detail'].toString()
          : '连接服务器失败');
    }
  }

  Future<String?> authenticateAndroid({
    required String deviceId,
    required String legacyUserId,
  }) async {
    try {
      final response = await _dio.post('/api/auth/android', data: {
        'device_id': deviceId,
        'legacy_user_id': legacyUserId,
      });
      if (response.statusCode == 200 && response.data['code'] == 0) {
        final data = Map<String, dynamic>.from(response.data['data'] ?? {});
        final userId = (data['user_id'] ?? '').toString().trim();
        return userId.isEmpty ? null : userId;
      }
    } catch (_) {}
    return null;
  }

  // 8. 创建 MP3 音频提取任务
  Future<String> createAudioTask({
    required String url,
    String quality = '192K',
  }) async {
    try {
      final response = await _dio.post('/api/audio/parse', data: {
        'url': url,
        'quality': quality,
      });
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        final data = Map<String, dynamic>.from(body['data'] ?? {});
        final taskId = (data['task_id'] ?? '').toString();
        if (taskId.isNotEmpty) return taskId;
      }
      throw Exception(body is Map ? (body['message'] ?? '音频任务创建失败') : '音频任务创建失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null
          ? data['detail'].toString()
          : '音频服务连接失败');
    }
  }

  // 9. 查询 MP3 音频提取任务
  Future<Map<String, dynamic>> fetchAudioTask(String taskId) async {
    try {
      final response = await _dio.get('/api/audio/status/$taskId');
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        final data = Map<String, dynamic>.from(body['data'] ?? {});
        var downloadUrl = (data['download_url'] ?? '').toString();
        if (downloadUrl.startsWith('/')) downloadUrl = '$baseUrl$downloadUrl';
        data['download_url'] = downloadUrl;
        return data;
      }
      throw Exception(body is Map ? (body['message'] ?? '音频任务查询失败') : '音频任务查询失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null
          ? data['detail'].toString()
          : '音频任务查询失败');
    }
  }

  Future<Map<String, dynamic>> extractLocalVideoAudio(File videoFile) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(videoFile.path, filename: 'local-video.mp4'),
      'quality': '192k',
    });
    try {
      final response = await _dio.post(
        '/api/video/extract_local_audio',
        data: form,
        options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)),
      );
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        final data = Map<String, dynamic>.from(body['data'] ?? {});
        var url = (data['download_url'] ?? '').toString();
        if (url.startsWith('/')) url = '$baseUrl$url';
        data['download_url'] = url;
        return data;
      }
      throw Exception(body is Map ? (body['detail'] ?? body['msg'] ?? '音频提取失败') : '音频提取失败');
    } on DioException catch (e) {
      final data = e.response?.data;
      throw Exception(data is Map && data['detail'] != null ? data['detail'].toString() : '本地视频上传或转码失败');
    }
  }

  Future<String> processLocalVideo(File file, String endpoint, Map<String, dynamic> fields, {File? image}) async {
    final data = <String, dynamic>{
      'file': await MultipartFile.fromFile(file.path, filename: 'local-video.mp4'),
      ...fields,
    };
    if (image != null) data['image'] = await MultipartFile.fromFile(image.path, filename: 'sign.png');
    try {
      final response = await _dio.post(endpoint, data: FormData.fromMap(data), options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 5)));
      final body = response.data;
      if (response.statusCode == 200 && body is Map && body['code'] == 0) {
        var url = (body['data']?['video_url'] ?? '').toString();
        if (url.startsWith('/')) url = '$baseUrl$url';
        if (url.isNotEmpty) return url;
      }
      throw Exception(body is Map ? (body['detail'] ?? body['msg'] ?? '视频处理失败') : '视频处理失败');
    } on DioException catch (e) {
      final body = e.response?.data;
      throw Exception(body is Map && body['detail'] != null ? body['detail'].toString() : '视频上传或处理失败');
    }
  }
}

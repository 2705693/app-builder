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
}

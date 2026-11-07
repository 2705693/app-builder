import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_id/android_id.dart';
import '../models/history_item.dart';
import 'api_service.dart';

class StorageService {
  static const String _keyHistory = 'parse_history_list';
  static const String _keyUserId = 'user_unique_id';
  static const String _keyLegalAccepted = 'legal_agreement_accepted_v1';
  static final ValueNotifier<int> historyVersion = ValueNotifier<int>(0);
  static String? _resolvedUserId;

  // 1. 获取或生成稳定的设备用户唯一标识
  static Future<String> getUserId() async {
    if (_resolvedUserId != null && _resolvedUserId!.isNotEmpty) {
      return _resolvedUserId!;
    }
    final sp = await SharedPreferences.getInstance();
    String? uid = sp.getString(_keyUserId);
    if (uid == null || uid.isEmpty) {
      uid = 'android_${DateTime.now().millisecondsSinceEpoch}';
      await sp.setString(_keyUserId, uid);
    }
    try {
      const androidIdPlugin = AndroidId();
      final deviceId = await androidIdPlugin.getId();
      if (deviceId != null && deviceId.isNotEmpty) {
        final stableUid = await ApiService().authenticateAndroid(
          deviceId: deviceId,
          legacyUserId: uid,
        );
        if (stableUid != null && stableUid.isNotEmpty) {
          uid = stableUid;
          await sp.setString(_keyUserId, uid);
        }
      }
    } catch (_) {
      // 无网络或系统不支持时继续使用本地 ID，不影响基本功能。
    }
    _resolvedUserId = uid;
    return uid!;
  }

  static Future<void> setUserId(String userId) async {
    final value = userId.trim();
    if (value.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyUserId, value);
    _resolvedUserId = value;
  }

  // 2. 保存单条历史记录（最多保留 100 条）
  static Future<void> addHistory(HistoryItem item) async {
    final sp = await SharedPreferences.getInstance();
    List<HistoryItem> list = await getHistoryList();
    
    // 避免重复加入相同链接或标题
    list.removeWhere((e) => e.videoUrl == item.videoUrl && e.videoUrl.isNotEmpty);
    list.insert(0, item);

    if (list.length > 100) {
      list = list.sublist(0, 100);
    }

    final jsonList = list.map((e) => e.toJson()).toList();
    await sp.setString(_keyHistory, jsonEncode(jsonList));
    historyVersion.value++;
  }

  // 3. 读取所有历史记录
  static Future<List<HistoryItem>> getHistoryList() async {
    final sp = await SharedPreferences.getInstance();
    final str = sp.getString(_keyHistory);
    if (str == null || str.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(str);
      return jsonList.map((e) => HistoryItem.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  // 4. 清空全部历史记录
  static Future<void> clearHistory() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyHistory);
    historyVersion.value++;
  }

  static Future<bool> isLegalAccepted() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_keyLegalAccepted) ?? false;
  }

  static Future<void> acceptLegalAgreement() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyLegalAccepted, true);
  }
}

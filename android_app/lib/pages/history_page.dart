import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';

import '../models/history_item.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../widgets/download_dialog.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DownloadService _downloadService = DownloadService();
  List<HistoryItem> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    StorageService.historyVersion.addListener(_loadHistory);
    _loadHistory();
  }

  @override
  void dispose() {
    StorageService.historyVersion.removeListener(_loadHistory);
    super.dispose();
  }

  void _loadHistory() async {
    final items = await StorageService.getHistoryList();
    if (mounted) {
      setState(() {
        _list = items;
        _loading = false;
      });
    }
  }

  void _clearAll() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('确定要清空手机本地保存的全部历史记录吗？此操作无法撤销，不会影响服务器日志和剩余次数。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageService.clearHistory();
              Fluttertoast.showToast(msg: '本地历史已清空');
            },
            child: const Text('确定清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _copyDownloadLink(HistoryItem item) {
    final url = item.videoUrl.isNotEmpty ? item.videoUrl : (item.images.isNotEmpty ? item.images.first : '');
    if (url.isEmpty) {
      Fluttertoast.showToast(msg: '该记录没有可复制的下载链接');
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    Fluttertoast.showToast(msg: '下载链接已复制');
  }

  Future<void> _saveHistoryItem(HistoryItem item) async {
    if (item.type != 'video' && item.images.isNotEmpty) {
      Fluttertoast.showToast(msg: '开始保存图集到相册…');
      final count = await _downloadService.downloadAndSaveImages(
        imageUrls: item.images,
        onProgress: (_, __) {},
      );
      Fluttertoast.showToast(msg: '已保存 $count 张图片到相册');
      return;
    }
    if (item.videoUrl.isEmpty) {
      Fluttertoast.showToast(msg: '该记录没有可保存的视频');
      return;
    }

    double progress = 0;
    String sizeText = '';
    StateSetter? updateDialog;
    BuildContext? progressContext;
    bool dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) {
          progressContext = ctx;
          updateDialog = setDialogState;
          return DownloadDialog(
            progress: progress,
            sizeText: sizeText,
            onCancel: () {
              _downloadService.cancelDownload();
              if (dialogOpen) {
                dialogOpen = false;
                Navigator.of(ctx).pop();
              }
              Fluttertoast.showToast(msg: '已停止下载');
            },
          );
        },
      ),
    ).whenComplete(() => dialogOpen = false);

    try {
      final ok = await _downloadService.downloadAndSaveVideo(
        videoUrl: item.videoUrl,
        onProgress: (received, total, value) {
          progress = value;
          if (total > 0) {
            sizeText = '${(received / 1024 / 1024).toStringAsFixed(1)} MB / ${(total / 1024 / 1024).toStringAsFixed(1)} MB';
          }
          if (dialogOpen) updateDialog?.call(() {});
        },
      );
      if (dialogOpen && progressContext != null && progressContext!.mounted) {
        dialogOpen = false;
        Navigator.of(progressContext!).pop();
      }
      if (ok) Fluttertoast.showToast(msg: '视频已保存到手机相册');
    } catch (e) {
      if (dialogOpen && progressContext != null && progressContext!.mounted) {
        dialogOpen = false;
        Navigator.of(progressContext!).pop();
      }
      Fluttertoast.showToast(msg: '保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('提取记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2822),
        actions: [
          if (_list.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF8C9B91)),
              tooltip: '清空历史',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF127C44)))
          : _list.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_rounded, size: 54, color: Color(0xFFCAD8CE)),
                      SizedBox(height: 12),
                      Text('暂无提取记录', style: TextStyle(color: Color(0xFF8A9990), fontSize: 14)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, idx) {
                    final item = _list[idx];
                    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt);

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
                        ],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: item.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: item.coverUrl,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 72,
                                    height: 72,
                                    color: const Color(0xFFE8F2EC),
                                    child: const Icon(Icons.movie_filter_rounded, color: Color(0xFF127C44)),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEBF7EF),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.platform,
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F7841)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.type == 'video' ? '视频' : '图集(${item.images.length}张)',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF8A9990)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF202B23)),
                                ),
                                const SizedBox(height: 4),
                                Text(dateStr, style: const TextStyle(fontSize: 11, color: Color(0xFFACBDB3))),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 92,
                            child: Column(
                              children: [
                                TextButton.icon(
                                  onPressed: () => _copyDownloadLink(item),
                                  icon: const Icon(Icons.copy_rounded, size: 15),
                                  label: const Text('复制链接', style: TextStyle(fontSize: 11)),
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                                ),
                                TextButton.icon(
                                  onPressed: () => _saveHistoryItem(item),
                                  icon: const Icon(Icons.download_rounded, size: 16),
                                  label: const Text('保存相册', style: TextStyle(fontSize: 11)),
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

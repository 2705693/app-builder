import 'package:flutter/material.dart';

class DownloadDialog extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0
  final String sizeText; // e.g. "35.2MB / 88.0MB"
  final VoidCallback onCancel;

  const DownloadDialog({
    super.key,
    required this.progress,
    required this.sizeText,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).toInt().clamp(0, 100);

    return WillPopScope(
      onWillPop: () async {
        onCancel();
        return true;
      },
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题与百分比
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '正在下载视频',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A231D),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF7EF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F7841),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress > 0 ? progress : null,
                  minHeight: 10,
                  backgroundColor: const Color(0xFFEAF1ED),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF07C160)),
                ),
              ),
              const SizedBox(height: 12),

              // 详细大小
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    percent >= 100 ? '下载完毕，正在存入相册...' : '正在下载视频...',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF6A7970)),
                  ),
                  if (sizeText.isNotEmpty)
                    Text(
                      sizeText,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF8C9B91), fontWeight: FontWeight.w500),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 温馨提示
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💡', style: TextStyle(fontSize: 14)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '如遇超长视频下载较慢，可停止后复制下载链接用手机浏览器下载。',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6C7C72), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 停止下载按钮
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFFA39E)),
                    backgroundColor: const Color(0xFFFFF1F0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '停止下载',
                    style: TextStyle(
                      color: Color(0xFFCF1322),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

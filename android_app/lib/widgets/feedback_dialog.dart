import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../services/api_service.dart';

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({super.key});

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _contactCtrl = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _submitting = false;

  void _submit() async {
    final text = _contentCtrl.text.trim();
    if (text.isEmpty) {
      Fluttertoast.showToast(msg: '请填写反馈内容');
      return;
    }

    setState(() => _submitting = true);
    try {
      final ok = await _apiService.submitFeedback(
        content: text,
        contact: _contactCtrl.text.trim(),
      );
      if (ok) {
        Fluttertoast.showToast(msg: '感谢您的反馈，我们已收到！');
        if (mounted) Navigator.pop(context);
      } else {
        Fluttertoast.showToast(msg: '提交失败，请重试');
      }
    } catch (e) {
      Fluttertoast.showToast(msg: '网络连接异常');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '意见反馈',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF202B23)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF8C9B91)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _contentCtrl,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: '请详细描述您遇到的问题或宝贵建议...',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9EAFA5)),
                fillColor: const Color(0xFFF7FAF8),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactCtrl,
              decoration: InputDecoration(
                hintText: '联系方式：微信号 / 邮箱（选填）',
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9EAFA5)),
                fillColor: const Color(0xFFF7FAF8),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF127C44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        '提交反馈',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../widgets/feedback_dialog.dart';

class ProfilePage extends StatefulWidget {
  final bool isActive;

  const ProfilePage({super.key, this.isActive = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ApiService _apiService = ApiService();
  int _quota = 10;
  bool _isVip = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void didUpdateWidget(covariant ProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadUser();
    }
  }

  Future<void> _loadUser() async {
    final uid = await StorageService.getUserId();
    final info = await _apiService.fetchUserInfo(uid);
    if (mounted) {
      setState(() {
        _userId = uid;
        _quota = info['total_quota'] ?? 10;
        _isVip = info['is_vip'] ?? false;
      });
    }
  }

  void _showPlatforms() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已支持解析平台', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E2822))),
            const SizedBox(height: 14),
            const Text(
              '• 短视频巨头：抖音、快手、小红书（视频/高清原图集）、B站\n'
              '• 腾讯生态：微信视频号 (channels.weixin.qq.com)\n'
              '• 字节创作与AI：剪映 (ulikecam)、即梦 (jimeng)、豆包 AI\n'
              '• 资讯与短剧：今日头条、红果短剧、番茄短剧\n'
              '• 国际平台：TikTok、X (推特)、YouTube',
              style: TextStyle(fontSize: 14, height: 1.8, color: Color(0xFF4A5C50)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF127C44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('我知道了', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTutorial() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('使用教程', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. 在抖音、小红书、B站等 App 中点击【分享】→【复制链接】；', style: TextStyle(fontSize: 14, height: 1.5)),
            SizedBox(height: 8),
            Text('2. 打开本 App，点击【一键粘贴】，然后点击【开始提取】；', style: TextStyle(fontSize: 14, height: 1.5)),
            SizedBox(height: 8),
            Text('3. 解析成功后，点击【保存到相册】即可极速下载无水印原画视频/图集。', style: TextStyle(fontSize: 14, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的', style: TextStyle(color: Color(0xFF127C44), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: 'sd0739@sd0739.top'));
    Fluttertoast.showToast(msg: '已复制联系邮箱: sd0739@sd0739.top');
  }

  void _copyUserId() {
    if (_userId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _userId));
    Fluttertoast.showToast(msg: '专属 ID 已复制');
  }

  Future<void> _showRedeemDialog() async {
    final controller = TextEditingController();
    bool submitting = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('卡密兑换', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                enabled: !submitting,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: '请输入授权卡密兑换码',
                  prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('输入管理员发放的卡密，可增加使用次数或开通不限次服务。', style: TextStyle(fontSize: 12, color: Color(0xFF6A7970), height: 1.5)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final key = controller.text.trim();
                      if (key.isEmpty) {
                        Fluttertoast.showToast(msg: '请输入卡密兑换码');
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final uid = _userId.isNotEmpty ? _userId : await StorageService.getUserId();
                        final message = await _apiService.redeemCard(userId: uid, cardKey: key);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        await _loadUser();
                        if (!mounted) return;
                        await showDialog<void>(
                          context: this.context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('兑换成功'),
                            content: Text(message),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定'))],
                          ),
                        );
                      } catch (e) {
                        final message = e.toString().replaceFirst('Exception: ', '');
                        if (dialogContext.mounted) {
                          setDialogState(() => submitting = false);
                          Fluttertoast.showToast(msg: message, toastLength: Toast.LENGTH_LONG);
                        }
                      }
                    },
              child: submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('立即兑换'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _showAccountRecoveryDialog() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('账号备份与恢复', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入您之前使用的用户ID，或曾经充值过的任意卡密。也可使用已保存的恢复码。', style: TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: '输入老用户ID(如wp_xxx)或充值卡密...',
                prefixIcon: const Icon(Icons.key_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              try {
                final uid = _userId.isNotEmpty ? _userId : await StorageService.getUserId();
                final code = await _apiService.createRecoveryCode(uid);
                await Clipboard.setData(ClipboardData(text: code));
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('恢复码已生成'),
                    content: SelectableText('$code\n\n已自动复制。新生成恢复码后，旧恢复码将失效。'),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我已保存'))],
                  ),
                );
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('生成恢复码'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) {
                Fluttertoast.showToast(msg: '请先输入恢复码');
                return;
              }
              try {
                final currentUserId = _userId.isNotEmpty ? _userId : await StorageService.getUserId();
                final info = await _apiService.recoverAccount(
                  currentUserId: currentUserId,
                  credential: controller.text,
                );
                final restoredUserId = (info['user_id'] ?? '').toString();
                if (restoredUserId.isEmpty) throw Exception('服务器未返回用户编号');
                await StorageService.setUserId(restoredUserId);
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                await _loadUser();
                Fluttertoast.showToast(msg: '账号和剩余次数已恢复');
              } catch (e) {
                Fluttertoast.showToast(msg: e.toString().replaceFirst('Exception: ', ''));
              }
            },
            child: const Text('立即找回并绑定'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void _showPrivacyPolicy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('隐私与使用说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: const SingleChildScrollView(
          child: Text(
            '仅在你主动点击粘贴时读取剪贴板，在点击保存时请求相册或文件权限。\n\n'
            '服务使用本机生成的专属 ID 记录额度；仅在您主动使用恢复码时同步账号状态，不要求手机号、头像、昵称或通讯录。\n\n'
            '图片修复等云端任务会将您主动选择的素材加密传输至服务器临时处理；视频号链接会发送给腾讯元宝完成处理。临时素材最多保存24小时。\n\n'
            '我们不会将素材用于AI训练、对外展示或分发，法律法规另有要求或您另行授权的除外。\n\n'
            '您可以撤回系统权限或清空本地历史；清空本地历史不影响剩余次数。\n\n'
            '隐私联系邮箱：sd0739@sd0739.top',
            style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF405047)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我知道了')),
        ],
      ),
    );
  }

  void _showUserAgreement() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('用户协议与知识产权说明', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const SingleChildScrollView(
          child: Text(
            '1. 使用本服务前，您承诺对所处理的图片、视频享有著作权，或已经取得权利人的合法授权。\n\n'
            '2. 不得处理未获授权的第三方素材，不得擅自删除、遮盖他人作品上的水印、作者标识或权利管理信息，也不得传播、搬运或商用侵权内容。\n\n'
            '3. 因用户处理无合法权属的素材而侵犯著作权、商标权、肖像权等权益的，相应责任由用户承担。\n\n'
            '4. 本服务仅提供内容处理技术，不对素材权属进行实质审查。请仅处理本人或已获授权的内容。\n\n'
            '5. 权利人投诉请将权属证明、侵权位置等材料发送至 sd0739@sd0739.top。收到合格通知后，我们将依法核查并采取必要措施。',
            style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF405047)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('我知道了'))],
      ),
    );
  }

  void _confirmClearHistory() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text('确定要清空手机本地保存的全部历史记录吗？此操作无法撤销，不会影响剩余次数。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await StorageService.clearHistory();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              Fluttertoast.showToast(msg: '本地历史已清空');
            },
            child: const Text('确认清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('我的', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2822),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2ECE5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: Color(0xFF127C44)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('我的专属 ID', style: TextStyle(fontSize: 12, color: Color(0xFF6A7970))),
                        const SizedBox(height: 3),
                        Text(
                          _userId.isEmpty ? '正在读取…' : _userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF263A2D)),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: _copyUserId, child: const Text('复制')),
                  TextButton(onPressed: _showAccountRecoveryDialog, child: const Text('找回/切换')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // 额度绿卡
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE8F3EC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD4E6DA)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('今日可用次数', style: TextStyle(fontSize: 13, color: Color(0xFF42634E), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _isVip ? '无限' : '$_quota',
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Color(0xFF127C44)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isVip ? '特权' : '次',
                        style: const TextStyle(fontSize: 16, color: Color(0xFF127C44), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isVip ? '已开通不限次服务' : '每日免费 10 次 (00:00 自动刷新)',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6A8E77)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 功能菜单卡片
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                children: [
                  _MenuItem(
                    icon: Icons.menu_book_rounded,
                    title: '使用教程',
                    onTap: _showTutorial,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.layers_rounded,
                    title: '支持平台',
                    onTap: _showPlatforms,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.feedback_outlined,
                    title: '意见反馈',
                    onTap: () => showDialog(context: context, builder: (_) => const FeedbackDialog()),
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.confirmation_number_outlined,
                    title: '卡密兑换',
                    onTap: _showRedeemDialog,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.key_outlined,
                    title: '账号备份与恢复',
                    onTap: _showAccountRecoveryDialog,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.shield_outlined,
                    title: '隐私政策',
                    onTap: _showPrivacyPolicy,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.description_outlined,
                    title: '用户协议',
                    onTap: _showUserAgreement,
                  ),
                  const Divider(height: 1, indent: 50, color: Color(0xFFF0F4F1)),
                  _MenuItem(
                    icon: Icons.mail_outline_rounded,
                    title: '联系邮箱',
                    trailingText: 'sd0739@sd0739.top',
                    onTap: _copyEmail,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: _MenuItem(
                icon: Icons.delete_outline_rounded,
                title: '清空历史记录',
                onTap: _confirmClearHistory,
              ),
            ),
            const SizedBox(height: 24),

            // 版本信息
            const Text(
              '一贴取影 v1.0.0 (Android版)\n多媒体内容提取与图片修复工具',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFFA5B8AC), height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailingText;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF127C44), size: 22),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF202B23))),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Text(trailingText!, style: const TextStyle(fontSize: 12, color: Color(0xFF8A9990))),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 20, color: Color(0xFFC0CEC6)),
        ],
      ),
      onTap: onTap,
    );
  }
}

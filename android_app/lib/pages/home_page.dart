import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:image_picker/image_picker.dart';

import '../models/parse_result.dart';
import '../models/history_item.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../widgets/download_dialog.dart';
import 'image_repair_page.dart';

class HomePage extends StatefulWidget {
  final Function(int) onTabChange;

  const HomePage({super.key, required this.onTabChange});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ApiService _apiService = ApiService();
  final DownloadService _downloadService = DownloadService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _parsing = false;
  ParseResult? _result;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  int _remainingQuota = 10;
  bool _isVip = false;
  bool _isLocalVideo = false;

  final List<String> _platforms = [
    '抖音', '小红书', '快手', 'B站', '视频号',
    'TikTok', 'X(推特)', 'YouTube', '剪映/即梦', '今日头条', '豆包', '红果/番茄'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLegalAccepted());
  }

  Future<bool> _ensureLegalAccepted() async {
    if (await StorageService.isLegalAccepted()) return true;
    if (!mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('重要版权提示'),
        content: const Text(
          '仅可处理本人享有著作权或已取得权利人授权的素材。未经许可，不得删除他人作品的水印、作者标识或权利管理信息，不得搬运、传播或商用侵权内容。\n\n继续使用即表示您已阅读并同意“我的”页面中的《用户协议》和《隐私政策》。',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('暂不使用')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('同意并继续')),
        ],
      ),
    );
    if (accepted == true) {
      await StorageService.acceptLegalAgreement();
      return true;
    }
    return false;
  }

  void _loadUserInfo() async {
    final uid = await StorageService.getUserId();
    final info = await _apiService.fetchUserInfo(uid);
    if (mounted) {
      setState(() {
        _remainingQuota = info['total_quota'] ?? 10;
        _isVip = info['is_vip'] ?? false;
      });
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
  }

  // 1. 读取系统剪贴板并粘贴
  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _inputCtrl.text = text;
      Fluttertoast.showToast(msg: '已粘贴剪贴板内容');
    } else {
      Fluttertoast.showToast(msg: '剪贴板为空');
    }
  }

  // 2. 开始提取
  void _startParse() async {
    if (!await _ensureLegalAccepted()) return;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) {
      Fluttertoast.showToast(msg: '请先粘贴或输入视频/图集链接');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _parsing = true;
      _result = null;
      _isLocalVideo = false;
    });
    _disposePlayer();

    try {
      final uid = await StorageService.getUserId();
      final res = await _apiService.parseUrl(text, userId: uid);

      if (mounted) {
        setState(() {
          _result = res;
          _parsing = false;
        });

        // 保存到历史记录
        StorageService.addHistory(HistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          platform: res.platform,
          type: res.type,
          title: res.title,
          coverUrl: res.coverUrl,
          videoUrl: res.videoUrl,
          images: res.images,
          createdAt: DateTime.now(),
        ));

        // 如果是视频，初始化播放器
        if (res.type == 'video' && res.videoUrl.isNotEmpty) {
          _initVideoPlayer(res.videoUrl);
        }

        Fluttertoast.showToast(msg: '解析成功！');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _parsing = false);
        _showErrorDialog(e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  void _initVideoPlayer(String url, {bool local = false}) async {
    _disposePlayer();
    _videoPlayerController = local
        ? VideoPlayerController.file(File(url))
        : VideoPlayerController.networkUrl(Uri.parse(url));
    await _videoPlayerController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      autoPlay: false,
      looping: false,
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      allowFullScreen: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: const Color(0xFF127C44),
        handleColor: const Color(0xFF127C44),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickLocalVideo() async {
    if (!await _ensureLegalAccepted()) return;
    final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final result = ParseResult(
      platform: '本地素材',
      type: 'video',
      title: '已选择本地视频',
      author: '',
      coverUrl: '',
      videoUrl: picked.path,
      originUrl: picked.path,
      images: const [],
    );
    setState(() {
      _result = result;
      _isLocalVideo = true;
    });
    await _initVideoPlayer(picked.path, local: true);
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('解析提示', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text(msg, style: const TextStyle(fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了', style: TextStyle(color: Color(0xFF127C44), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // 3. 原生保存视频到系统相册
  Future<void> _saveVideoToAlbum() async {
    if (_result == null || _result!.videoUrl.isEmpty) return;
    if (_isLocalVideo) {
      try {
        await _downloadService.saveLocalVideo(_result!.videoUrl);
        Fluttertoast.showToast(msg: '视频已保存到手机相册');
      } catch (e) {
        Fluttertoast.showToast(msg: '保存失败: $e');
      }
      return;
    }

    double currentProgress = 0.0;
    String currentSizeText = '';
    StateSetter? dialogSetState;
    BuildContext? progressDialogContext;
    bool progressDialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          progressDialogContext = ctx;
          dialogSetState = setDialogState;
          return DownloadDialog(
            progress: currentProgress,
            sizeText: currentSizeText,
            onCancel: () {
              _downloadService.cancelDownload();
              if (progressDialogOpen) {
                progressDialogOpen = false;
                Navigator.of(ctx).pop();
              }
              Fluttertoast.showToast(msg: '已停止下载');
            },
          );
        },
      ),
    ).whenComplete(() => progressDialogOpen = false);

    try {
      final ok = await _downloadService.downloadAndSaveVideo(
        videoUrl: _result!.videoUrl,
        onProgress: (received, total, progress) {
          currentProgress = progress;
          if (total > 0) {
            final recM = (received / 1024 / 1024).toStringAsFixed(1);
            final totM = (total / 1024 / 1024).toStringAsFixed(1);
            currentSizeText = '$recM MB / $totM MB';
          }
          if (progressDialogOpen) dialogSetState?.call(() {});
        },
      );
      if (progressDialogOpen && progressDialogContext != null && progressDialogContext!.mounted) {
        progressDialogOpen = false;
        Navigator.of(progressDialogContext!).pop();
      }
      if (ok) {
        Fluttertoast.showToast(msg: '视频已成功保存到手机相册！');
      }
    } catch (err) {
      if (progressDialogOpen && progressDialogContext != null && progressDialogContext!.mounted) {
        progressDialogOpen = false;
        Navigator.of(progressDialogContext!).pop();
      }
      Fluttertoast.showToast(msg: '保存失败: $err');
    }
  }

  // 4. 批量保存图集
  void _saveAllImages() async {
    if (_result == null || _result!.images.isEmpty) return;

    Fluttertoast.showToast(msg: '开始保存图集到相册...');
    final count = await _downloadService.downloadAndSaveImages(
      imageUrls: _result!.images,
      onProgress: (curr, total) {},
    );
    Fluttertoast.showToast(msg: '成功保存 $count 张图片到手机相册');
  }

  // 5. 复制下载链接
  void _copyLink() {
    if (_result == null) return;
    if (_isLocalVideo) {
      Fluttertoast.showToast(msg: '本地视频没有网络下载链接');
      return;
    }
    final url = _result!.videoUrl.isNotEmpty ? _result!.videoUrl : (_result!.images.isNotEmpty ? _result!.images.first : '');
    Clipboard.setData(ClipboardData(text: url));
    Fluttertoast.showToast(msg: '下载链接已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF8),
      appBar: AppBar(
        title: const Text('一键提取', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E2822),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEDF7F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4EBDC)),
              ),
              child: const Text(
                '仅可处理本人享有著作权或已取得权利人授权的素材。不得擅自删除他人作品的水印、作者标识或权利管理信息。',
                style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF1F6F43)),
              ),
            ),
            const SizedBox(height: 14),
            // 平台支持标签栏
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _platforms.map((p) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2ECE5)),
                ),
                child: Text(p, style: const TextStyle(fontSize: 11, color: Color(0xFF4A5C50), fontWeight: FontWeight.w500)),
              )).toList(),
            ),
            const SizedBox(height: 16),

            // 输入卡片
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4)),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _inputCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '粘贴短视频、图集、AI视频分享链接，支持全网自动识别...',
                      hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9EAFA5)),
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF0F4F1)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded, size: 16, color: Color(0xFF127C44)),
                        label: const Text('一键粘贴', style: TextStyle(color: Color(0xFF127C44), fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      if (_inputCtrl.text.isNotEmpty)
                        TextButton(
                          onPressed: () => setState(() => _inputCtrl.clear()),
                          child: const Text('清空', style: TextStyle(color: Color(0xFF8C9B91), fontSize: 13)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                onPressed: _parsing ? null : _startParse,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF127C44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                child: _parsing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('正在深度提取中...', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      )
                    : const Text('开始提取', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _parsing ? null : _pickLocalVideo,
                    icon: const Icon(Icons.video_library_outlined, size: 17),
                    label: const Text('本地视频'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF127C44),
                      backgroundColor: const Color(0xFFE8F3EC),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 局部修复快捷入口
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageRepairPage())),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFF6246A8)),
                label: const Text('图片局部修复（擦除多余元素）', style: TextStyle(color: Color(0xFF6246A8), fontSize: 13, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2EDFF),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 额度指示条
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(_isVip ? '👑' : '🕒', style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      _isVip ? '无限次解析特权' : '当前剩余 $_remainingQuota 次',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2B3A30)),
                    ),
                  ],
                ),
                Text(
                  _isVip ? '不限次服务' : '每日免费 10 次',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6A7970)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 解析结果展示卡片
            if (_result != null) _buildResultCard(),

            const SizedBox(height: 24),

            // 使用说明
            _buildTutorialCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x0C000000), blurRadius: 18, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF7EF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _result!.platform,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F7841)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _result!.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF202B23)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 视频展示
          if (_result!.type == 'video') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: _chewieController!)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_result!.coverUrl.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: _result!.coverUrl,
                              fit: BoxFit.cover,
                            ),
                          const Center(
                            child: CircularProgressIndicator(color: Color(0xFF127C44)),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _saveVideoToAlbum,
                icon: const Icon(Icons.download_rounded, color: Colors.white, size: 18),
                label: const Text('保存视频到手机相册', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          // 图集展示
          if (_result!.type != 'video' && _result!.images.isNotEmpty) ...[
            Text('检测到图集共 ${_result!.images.length} 张：', style: const TextStyle(fontSize: 12, color: Color(0xFF6A7970))),
            const SizedBox(height: 10),
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _result!.images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (ctx, idx) {
                  final imgUrl = _result!.images[idx];
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CachedNetworkImage(
                          imageUrl: imgUrl,
                          width: 90,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ImageRepairPage(initialImageUrl: imgUrl)),
                          );
                        },
                        child: const Text('局部修复', style: TextStyle(fontSize: 11, color: Color(0xFF6246A8), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _saveAllImages,
                icon: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 18),
                label: const Text('批量保存全部图片到相册', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: TextButton.icon(
              onPressed: _copyLink,
              icon: const Icon(Icons.link_rounded, size: 16, color: Color(0xFF4B6255)),
              label: const Text('复制直链下载地址', style: TextStyle(color: Color(0xFF4B6255), fontSize: 13)),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8F0EA)),
      ),
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('使用方法', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E2822))),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StepWidget(num: '1', title: '复制链接', desc: '平台分享中'),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFC0CEC6), size: 18),
              _StepWidget(num: '2', title: '粘贴解析', desc: '填入上方框'),
              Icon(Icons.chevron_right_rounded, color: Color(0xFFC0CEC6), size: 18),
              _StepWidget(num: '3', title: '保存相册', desc: '极速无水印'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepWidget extends StatelessWidget {
  final String num;
  final String title;
  final String desc;

  const _StepWidget({required this.num, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: const BoxDecoration(
            color: Color(0xFF127C44),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2B3A30))),
        const SizedBox(height: 2),
        Text(desc, style: const TextStyle(fontSize: 10, color: Color(0xFF8A9990))),
      ],
    );
  }
}

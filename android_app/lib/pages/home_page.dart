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
import 'image_resize_page.dart';

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
  bool _extractingAudio = false;
  bool _processingVideo = false;
  ParseResult? _result;
  VideoPlayerController? _videoPlayerController;
  VideoPlayerController? _audioPlayerController;
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

  Future<void> _loadUserInfo() async {
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
    _audioPlayerController?.dispose();
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

  void _copyWechatId() {
    Clipboard.setData(const ClipboardData(text: 'web0739'));
    Fluttertoast.showToast(msg: '微信号 web0739 已复制');
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
          if (!_isVip && _remainingQuota > 0) {
            _remainingQuota--;
          }
        });

        // 立即向服务器拉取最新剩余额度并刷新 UI
        _loadUserInfo();

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

        await _loadUserInfo();
        Fluttertoast.showToast(msg: '提取成功，已扣除 1 次额度');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _parsing = false);
        final message = e.toString().replaceAll('Exception: ', '');
        if (message.contains('次数已用尽') || message.contains('次数不足')) {
          _showQuotaLimitDialog();
        } else {
          _showErrorDialog(message);
        }
      }
    }
  }

  void _showQuotaLimitDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('今日次数已用完', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const Text('今日次数已用完，请明日再试或通过意见反馈/联系我们。'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('我知道了')),
        ],
      ),
    );
  }

  Future<void> _initVideoPlayer(String url, {bool local = false}) async {
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

  Future<void> _runLocalVideoProcess(
    String endpoint,
    Map<String, dynamic> fields,
    String resultLabel, {
    File? image,
  }) async {
    if (_result == null || !_isLocalVideo || _processingVideo) return;
    setState(() => _processingVideo = true);
    try {
      final url = await _apiService.processLocalVideo(
        File(_result!.videoUrl), endpoint, fields, image: image,
      );
      final uid = await StorageService.getUserId();
      await _apiService.consumeQuota(userId: uid, feature: endpoint.split('/').last);
      await StorageService.addOperationHistory(category: '视频处理', title: resultLabel);
      final old = _result!;
      await _initVideoPlayer(url);
      if (!mounted) return;
      setState(() {
        _result = ParseResult(
          platform: '本地素材', type: 'video',
          title: '${old.title} · $resultLabel', author: old.author,
          coverUrl: '', videoUrl: url, originUrl: url, images: const [],
        );
        _isLocalVideo = false;
        _processingVideo = false;
      });
      await _loadUserInfo();
      Fluttertoast.showToast(msg: '$resultLabel完成，可预览并保存');
    } catch (error) {
      if (!mounted) return;
      setState(() => _processingVideo = false);
      final message = error.toString().replaceFirst('Exception: ', '');
      if (message.contains('次数已用尽') || message.contains('次数不足')) {
        _showQuotaLimitDialog();
      } else {
        _showErrorDialog(message);
      }
    }
  }

  Future<void> _showTrimDialog() async {
    final startCtrl = TextEditingController(text: '0');
    final endCtrl = TextEditingController(text: '15');
    final values = await showDialog<List<double>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('时长裁剪'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: startCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '开始时间（秒）')),
          TextField(controller: endCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '结束时间（秒）')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () {
            final start = double.tryParse(startCtrl.text.trim());
            final end = double.tryParse(endCtrl.text.trim());
            if (start == null || end == null || start < 0 || end <= start) {
              Fluttertoast.showToast(msg: '结束时间必须大于开始时间');
              return;
            }
            Navigator.pop(ctx, [start, end]);
          }, child: const Text('开始处理')),
        ],
      ),
    );
    startCtrl.dispose();
    endCtrl.dispose();
    if (values == null) return;
    await _runLocalVideoProcess('/api/video/trim', {
      'start': values[0].toString(), 'end': values[1].toString(),
    }, '时长裁剪');
  }

  Future<void> _showAreaProcessDialog() async {
    var position = 'bottom_right';
    var method = 'blur';
    final values = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('局部处理'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: position, decoration: const InputDecoration(labelText: '区域位置'),
              items: const [
                DropdownMenuItem(value: 'top_left', child: Text('左上角')),
                DropdownMenuItem(value: 'top_right', child: Text('右上角')),
                DropdownMenuItem(value: 'center', child: Text('画面中央')),
                DropdownMenuItem(value: 'bottom_left', child: Text('左下角')),
                DropdownMenuItem(value: 'bottom_right', child: Text('右下角')),
              ],
              onChanged: (value) => setDialogState(() => position = value!),
            ),
            DropdownButtonFormField<String>(
              value: method, decoration: const InputDecoration(labelText: '处理方式'),
              items: const [
                DropdownMenuItem(value: 'blur', child: Text('柔化处理')),
                DropdownMenuItem(value: 'delogo', child: Text('智能修补')),
              ],
              onChanged: (value) => setDialogState(() => method = value!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, [position, method]), child: const Text('开始处理')),
          ],
        ),
      ),
    );
    if (values == null) return;
    await _runLocalVideoProcess('/api/video/remove_mark', {
      'position': values[0], 'method': values[1],
    }, '局部处理');
  }

  Future<void> _showAddSignDialog() async {
    final type = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('添加内容标识', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(leading: const Icon(Icons.text_fields_rounded), title: const Text('添加文字标识'), onTap: () => Navigator.pop(ctx, 'text')),
        ListTile(leading: const Icon(Icons.image_outlined), title: const Text('添加图片标识'), onTap: () => Navigator.pop(ctx, 'image')),
      ])),
    );
    if (type == 'text') {
      final ctrl = TextEditingController();
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('文字标识'),
          content: TextField(controller: ctrl, maxLength: 30, decoration: const InputDecoration(hintText: '请输入要添加的文字')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () {
              final value = ctrl.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            }, child: const Text('开始处理')),
          ],
        ),
      );
      ctrl.dispose();
      if (text == null) return;
      await _runLocalVideoProcess('/api/video/add_sign', {
        'text': text, 'position': 'bottom_right',
      }, '添加文字标识');
    } else if (type == 'image') {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 95);
      if (picked == null) return;
      await _runLocalVideoProcess('/api/video/add_sign', {
        'text': '', 'position': 'bottom_right',
      }, '添加图片标识', image: File(picked.path));
    }
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
        _loadUserInfo();
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
    _loadUserInfo();
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

  // 6. 从解析结果提取标准 MP3 音频
  Future<void> _extractAudio() async {
    if (_result == null || _extractingAudio) return;
    if (_isLocalVideo) {
      setState(() => _extractingAudio = true);
      try {
        final data = await _apiService.extractLocalVideoAudio(File(_result!.videoUrl));
        final url = (data['download_url'] ?? '').toString();
        if (url.isEmpty) throw Exception('服务器没有返回 MP3 下载地址');
        final uid = await StorageService.getUserId();
        await _apiService.consumeQuota(userId: uid, feature: 'local_video_audio');
        await StorageService.addOperationHistory(category: '音频处理', title: '本地视频转换 MP3');
        await _loadUserInfo();
        if (mounted) {
          setState(() => _extractingAudio = false);
          await _showAudioActions(url, (data['title'] ?? '本地视频原声.mp3').toString());
        }
      } catch (error) {
        if (mounted) {
          setState(() => _extractingAudio = false);
          final message = error.toString().replaceFirst('Exception: ', '');
          if (message.contains('次数已用尽') || message.contains('次数不足') || message.contains('今日可用次数')) {
            _showQuotaLimitDialog();
          } else {
            _showErrorDialog(message);
          }
        }
      }
      return;
    }
    var targetUrl = _result!.originUrl.trim();
    if (targetUrl.isEmpty) targetUrl = _result!.videoUrl.trim();
    if (!targetUrl.startsWith('http')) {
      Fluttertoast.showToast(msg: '当前结果没有可用的音频来源');
      return;
    }

    setState(() => _extractingAudio = true);
    try {
      final taskId = await _apiService.createAudioTask(url: targetUrl, quality: '192K');
      Map<String, dynamic>? completed;
      for (var attempt = 0; attempt < 60; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final task = await _apiService.fetchAudioTask(taskId);
        final status = (task['status'] ?? '').toString();
        if (status == 'success') {
          completed = task;
          break;
        }
        if (status == 'failed') {
          throw Exception((task['message'] ?? '音频提取失败').toString());
        }
      }
      if (completed == null) throw Exception('音频提取超时，请稍后重试');
      final url = (completed['download_url'] ?? '').toString();
      if (url.isEmpty) throw Exception('服务器没有返回 MP3 下载地址');
      if (mounted) {
        setState(() => _extractingAudio = false);
        await _showAudioActions(url, (completed['filename'] ?? '').toString());
      }
    } catch (error) {
      if (mounted) {
        setState(() => _extractingAudio = false);
        _showErrorDialog(error.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _showAudioActions(String url, String filename) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('MP3 音频已准备好', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('文件将在服务器临时保留24小时'),
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Color(0xFF127C44)),
              title: const Text('保存到系统下载目录'),
              onTap: () => Navigator.pop(ctx, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFF127C44)),
              title: const Text('在线试听'),
              onTap: () => Navigator.pop(ctx, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.link_rounded, color: Color(0xFF127C44)),
              title: const Text('复制 MP3 下载链接'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') {
      await _saveAudio(url, filename);
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: url));
      Fluttertoast.showToast(msg: 'MP3 下载链接已复制');
    } else if (action == 'play') {
      await _playAudio(url);
    }
  }

  Future<void> _playAudio(String url) async {
    await _audioPlayerController?.dispose();
    final player = VideoPlayerController.networkUrl(Uri.parse(url));
    _audioPlayerController = player;
    try {
      await player.initialize();
      await player.play();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('正在试听 MP3'),
          content: const Text('音频正在播放，关闭窗口即可停止试听。'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('停止播放'))],
        ),
      );
    } catch (_) {
      Fluttertoast.showToast(msg: '音频播放失败，请改用下载或复制链接');
    } finally {
      await player.pause();
      await player.dispose();
      if (identical(_audioPlayerController, player)) _audioPlayerController = null;
    }
  }

  Future<void> _saveAudio(String url, String filename) async {
    double progress = 0;
    String sizeText = '';
    StateSetter? dialogSetState;
    var dialogOpen = true;
    BuildContext? dialogContext;
    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (_, setState) {
        dialogContext = ctx;
        dialogSetState = setState;
        return DownloadDialog(
          progress: progress,
          sizeText: sizeText,
          onCancel: () {
            _downloadService.cancelDownload();
            if (dialogOpen && Navigator.of(ctx).canPop()) {
              dialogOpen = false;
              Navigator.of(ctx).pop();
            }
          },
        );
      }),
    );
    dialogFuture.whenComplete(() => dialogOpen = false);
    try {
      await _downloadService.downloadAndSaveAudio(
        audioUrl: url,
        filename: filename,
        onProgress: (received, total, value) {
          progress = value;
          if (total > 0) {
            sizeText = '${(received / 1048576).toStringAsFixed(1)} MB / ${(total / 1048576).toStringAsFixed(1)} MB';
          }
          if (dialogOpen) dialogSetState?.call(() {});
        },
      );
      if (dialogOpen && dialogContext != null && dialogContext!.mounted && Navigator.of(dialogContext!).canPop()) {
        dialogOpen = false;
        Navigator.of(dialogContext!).pop();
      }
      Fluttertoast.showToast(msg: 'MP3 已保存到“下载/一链取影”目录');
    } catch (error) {
      if (dialogOpen && dialogContext != null && dialogContext!.mounted && Navigator.of(dialogContext!).canPop()) {
        dialogOpen = false;
        Navigator.of(dialogContext!).pop();
      }
      final message = error.toString().replaceFirst('Exception: ', '');
      if (message != '已停止下载') _showErrorDialog(message);
    }
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
                '仅可处理本人享有著作权或已取得权利人授权的素材。\n未经许可，不得删除他人作品的水印、作者标识或权利管理信息，不得搬运、传播或商用侵权内容。',
                style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF1F6F43)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _copyWechatId,
                icon: const Icon(Icons.wechat, size: 16, color: Color(0xFF127C44)),
                label: const Text(
                  '保存视频或图集 · 微信号：web0739（点击复制）',
                  style: TextStyle(fontSize: 12, color: Color(0xFF4A6A56)),
                ),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
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

            // 图片修复快捷入口
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageRepairPage())),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16, color: Color(0xFF6246A8)),
                label: const Text('图片修复', style: TextStyle(color: Color(0xFF6246A8), fontSize: 13, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2EDFF),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImageResizePage())),
                icon: const Icon(Icons.aspect_ratio_rounded, size: 16, color: Color(0xFF127C44)),
                label: const Text('常用头像与封面尺寸转换', style: TextStyle(color: Color(0xFF127C44), fontSize: 13, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFEAF7EF),
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
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _extractingAudio ? null : _extractAudio,
                  icon: _extractingAudio
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.music_note_rounded, size: 18),
                  label: Text(_extractingAudio ? '正在转换 MP3...' : '提取 MP3 纯音频'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF127C44),
                    backgroundColor: const Color(0xFFEAF6EE),
                    side: const BorderSide(color: Color(0xFFCBE7D5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (_isLocalVideo) ...[
              const SizedBox(height: 10),
              if (_processingVideo)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('视频处理中，请勿退出...'),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(child: OutlinedButton(onPressed: _showTrimDialog, child: const Text('时长裁剪'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: _showAreaProcessDialog, child: const Text('局部处理'))),
                    const SizedBox(width: 8),
                    Expanded(child: OutlinedButton(onPressed: _showAddSignDialog, child: const Text('添加标识'))),
                  ],
                ),
            ],
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
                        child: const Text('图片修复', style: TextStyle(fontSize: 11, color: Color(0xFF6246A8), fontWeight: FontWeight.w600)),
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

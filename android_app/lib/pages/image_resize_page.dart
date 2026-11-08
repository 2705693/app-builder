import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class ImageResizePage extends StatefulWidget {
  const ImageResizePage({super.key});

  @override
  State<ImageResizePage> createState() => _ImageResizePageState();
}

class _ImagePreset {
  final String name;
  final String description;
  final int width;
  final int height;

  const _ImagePreset(this.name, this.description, this.width, this.height);

  double get ratio => width / height;
}

class _ImageResizePageState extends State<ImageResizePage> {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _previewKey = GlobalKey();
  final ApiService _apiService = ApiService();
  final TextEditingController _widthController = TextEditingController(text: '144');
  final TextEditingController _heightController = TextEditingController(text: '144');

  static const _presets = [
    _ImagePreset('2K 横图', '4K图片缩小', 2560, 1440),
    _ImagePreset('1080P 横图', '高清横版图片', 1920, 1080),
    _ImagePreset('小头像', '常用144像素', 144, 144),
    _ImagePreset('方形头像', '通用社交头像', 800, 800),
    _ImagePreset('高清头像', '高清方形头像', 1080, 1080),
    _ImagePreset('竖版封面', '短视频/图文封面', 1080, 1440),
    _ImagePreset('全屏竖图', '手机全屏展示', 1080, 1920),
    _ImagePreset('横版封面', '通用16:9封面', 1920, 1080),
    _ImagePreset('公众号首图', '文章头图比例', 900, 383),
    _ImagePreset('社交封面', '个人主页横图', 1080, 720),
    _ImagePreset('视频封面', '通用16:10封面', 1146, 717),
  ];

  File? _source;
  _ImagePreset _preset = _presets.first;
  BoxFit _fit = BoxFit.cover;
  Alignment _alignment = Alignment.center;
  Color _background = Colors.white;
  bool _saving = false;

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyCustomSize() {
    final width = int.tryParse(_widthController.text.trim());
    final height = int.tryParse(_heightController.text.trim());
    if (width == null || height == null || width < 16 || height < 16 || width > 4096 || height > 4096) {
      Fluttertoast.showToast(msg: '宽高请输入 16～4096');
      return;
    }
    setState(() => _preset = _ImagePreset('自定义尺寸', '按输入尺寸生成', width, height));
  }

  Future<void> _showQuotaLimit() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('今日次数已用完'),
        content: const Text('今日次数已用完，请明日再试或通过意见反馈/联系我们。'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('我知道了')),
        ],
      ),
    );
  }

  Future<void> _chooseImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (file == null || !mounted) return;
    setState(() => _source = File(file.path));
  }

  Future<void> _save() async {
    if (_source == null || _saving) return;
    setState(() => _saving = true);
    try {
      final userId = await StorageService.getUserId();
      await _apiService.consumeQuota(userId: userId, feature: 'image_resize');
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || boundary.size.width <= 0) throw Exception('预览尚未准备好');
      final pixelRatio = _preset.width / boundary.size.width;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('图片生成失败');
      final result = await ImageGallerySaverPlus.saveImage(
        bytes.buffer.asUint8List(),
        quality: 100,
        name: '一链取影_${_preset.name}_${_preset.width}x${_preset.height}_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (result is Map && result['isSuccess'] == false) throw Exception('相册写入失败');
      Fluttertoast.showToast(msg: '${_preset.width}×${_preset.height} 图片已保存');
    } catch (error) {
      final message = error.toString();
      if (message.contains('次数已用尽') || message.contains('次数不足')) {
        await _showQuotaLimit();
      } else {
        Fluttertoast.showToast(msg: '保存失败: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('图片尺寸转换', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        actions: [IconButton(onPressed: _chooseImage, icon: const Icon(Icons.photo_library_outlined))],
      ),
      body: _source == null ? _buildEmpty() : _buildEditor(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 42,
              backgroundColor: Color(0xFF127C44),
              child: Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 38),
            ),
            const SizedBox(height: 20),
            const Text('常用图片尺寸转换', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('头像、竖版封面、横版封面、文章首图等\n图片只在手机本地处理', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, height: 1.5)),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _chooseImage, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('从相册选择图片')),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                final preset = _presets[index];
                final selected = identical(preset, _preset);
                return InkWell(
                  onTap: () => setState(() => _preset = preset),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 135,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? const Color(0xFFEDF8F1) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? const Color(0xFF127C44) : const Color(0xFFE1E8E3), width: selected ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${preset.width}×${preset.height}', style: const TextStyle(color: Color(0xFF127C44), fontSize: 12)),
                      Text(preset.description, style: const TextStyle(color: Colors.black45, fontSize: 10)),
                    ]),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('自定义像素尺寸', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: _widthController, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: '宽度', border: OutlineInputBorder(), isDense: true))),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('×')),
                  Expanded(child: TextField(controller: _heightController, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: '高度', border: OutlineInputBorder(), isDense: true))),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: _applyCustomSize, child: const Text('应用')),
                ]),
                const SizedBox(height: 6),
                const Text('支持 16～4096 像素，例如 144×144', style: TextStyle(fontSize: 11, color: Colors.black45)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                SegmentedButton<BoxFit>(
                  segments: const [
                    ButtonSegment(value: BoxFit.cover, label: Text('铺满裁剪')),
                    ButtonSegment(value: BoxFit.contain, label: Text('完整留白')),
                  ],
                  selected: {_fit},
                  onSelectionChanged: (value) => setState(() => _fit = value.first),
                ),
                const SizedBox(height: 10),
                if (_fit == BoxFit.cover)
                  SegmentedButton<Alignment>(
                    segments: const [
                      ButtonSegment(value: Alignment.topCenter, label: Text('靠上')),
                      ButtonSegment(value: Alignment.center, label: Text('居中')),
                      ButtonSegment(value: Alignment.bottomCenter, label: Text('靠下')),
                    ],
                    selected: {_alignment},
                    onSelectionChanged: (value) => setState(() => _alignment = value.first),
                  )
                else
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('留白颜色：'),
                    _colorButton(Colors.white),
                    _colorButton(Colors.black),
                  ]),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 430),
              child: AspectRatio(
                aspectRatio: _preset.ratio,
                child: RepaintBoundary(
                  key: _previewKey,
                  child: ColoredBox(
                    color: _background,
                    child: Image.file(_source!, fit: _fit, alignment: _alignment),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _chooseImage, child: const Text('换一张'))),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_alt_rounded),
                label: Text(_saving ? '正在生成...' : '保存 ${_preset.width}×${_preset.height}'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _colorButton(Color color) {
    return GestureDetector(
      onTap: () => setState(() => _background = color),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: _background == color ? const Color(0xFF127C44) : Colors.black26, width: _background == color ? 3 : 1),
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../services/storage_service.dart';

class ImageTextPage extends StatefulWidget {
  const ImageTextPage({super.key});

  @override
  State<ImageTextPage> createState() => _ImageTextPageState();
}

class _ImageTextPageState extends State<ImageTextPage> {
  final _picker = ImagePicker();
  final _exportKey = GlobalKey();
  final _textController = TextEditingController(text: '点击输入自定义文字');
  File? _source;
  double _aspect = 1;
  Offset _position = const Offset(45, 150);
  double _fontSize = 28;
  Color _color = Colors.white;
  bool _shadow = true;
  bool _saving = false;

  static const _colors = [Colors.white, Colors.black, Color(0xFFEF4444), Color(0xFFEAB308), Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFF97316), Color(0xFFA855F7)];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _choose() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;
    final file = File(picked.path);
    final image = await ui.decodeImageFromList(await file.readAsBytes());
    if (!mounted) return;
    setState(() {
      _source = file;
      _aspect = image.width / image.height;
      _position = const Offset(45, 150);
    });
  }

  Future<void> _save() async {
    if (_source == null || _saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('画布尚未准备好');
      final sourceImage = await ui.decodeImageFromList(await _source!.readAsBytes());
      final ratio = sourceImage.width / boundary.size.width;
      final image = await boundary.toImage(pixelRatio: ratio.clamp(1, 8).toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('图片生成失败');
      await ImageGallerySaverPlus.saveImage(data.buffer.asUint8List(), quality: 100, name: '一链取影_图片加文字_${DateTime.now().millisecondsSinceEpoch}');
      await StorageService.addOperationHistory(category: '图片加文字', title: '原图高清文字合成');
      Fluttertoast.showToast(msg: '文字图片已保存到相册');
    } catch (error) {
      Fluttertoast.showToast(msg: '保存失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('图片加文字'), centerTitle: true, actions: [IconButton(onPressed: _choose, icon: const Icon(Icons.photo_library_outlined))]),
      body: _source == null ? _empty() : _editor(),
    );
  }

  Widget _empty() => Center(child: FilledButton.icon(onPressed: _choose, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('选择图片')));

  Widget _editor() => ListView(padding: const EdgeInsets.all(16), children: [
    Center(child: AspectRatio(aspectRatio: _aspect, child: RepaintBoundary(key: _exportKey, child: LayoutBuilder(builder: (context, size) => Stack(clipBehavior: Clip.hardEdge, fit: StackFit.expand, children: [
      Image.file(_source!, fit: BoxFit.cover),
      Positioned(left: _position.dx.clamp(0, size.maxWidth - 30).toDouble(), top: _position.dy.clamp(0, size.maxHeight - 30).toDouble(), child: GestureDetector(
        onPanUpdate: (event) => setState(() => _position += event.delta),
        child: Text(_textController.text, style: TextStyle(fontSize: _fontSize, color: _color, fontWeight: FontWeight.w700, shadows: _shadow ? const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 2))] : null)),
      )),
    ]))))),
    const SizedBox(height: 16),
    TextField(controller: _textController, maxLength: 50, decoration: const InputDecoration(labelText: '文字内容', border: OutlineInputBorder()), onChanged: (_) => setState(() {})),
    Row(children: [const Text('字号'), Expanded(child: Slider(value: _fontSize, min: 14, max: 72, divisions: 58, label: _fontSize.round().toString(), onChanged: (value) => setState(() => _fontSize = value)))]),
    Wrap(spacing: 10, children: _colors.map((color) => InkWell(onTap: () => setState(() => _color = color), child: CircleAvatar(radius: 15, backgroundColor: color, child: _color == color ? const Icon(Icons.check, size: 17, color: Colors.grey) : null))).toList()),
    SwitchListTile(value: _shadow, onChanged: (value) => setState(() => _shadow = value), title: const Text('文字阴影')),
    FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_alt), label: Text(_saving ? '正在生成...' : '保存高清图片')),
  ]);
}

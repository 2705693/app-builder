import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';

class IdPhotoPage extends StatefulWidget {
  const IdPhotoPage({super.key});

  @override
  State<IdPhotoPage> createState() => _IdPhotoPageState();
}

class _PhotoSize {
  final String name;
  final int width;
  final int height;
  const _PhotoSize(this.name, this.width, this.height);
}

class _Suit {
  final String name;
  final String? asset;
  const _Suit(this.name, this.asset);
}

class _IdPhotoPageState extends State<IdPhotoPage> {
  final _picker = ImagePicker();
  final _api = ApiService();
  final _exportKey = GlobalKey();
  final _sheetKey = GlobalKey();
  File? _source;
  String? _mattedUrl;
  bool _processing = false;
  bool _saving = false;
  double _personScale = 1;
  Offset _personOffset = Offset.zero;

  static const _sizes = [
    _PhotoSize('一寸', 295, 413),
    _PhotoSize('二代身份证', 358, 441),
    _PhotoSize('二寸', 413, 579),
    _PhotoSize('小一寸', 260, 378),
    _PhotoSize('大一寸', 390, 567),
    _PhotoSize('小二寸', 413, 531),
  ];
  static const _colors = [Colors.white, Color(0xFF438EDB), Color(0xFFC00000), Color(0xFF666666), Color(0xFF69B2FF), Color(0xFFF6F4EE)];
  static const _suits = [
    _Suit('不换装', null),
    _Suit('男黑西装', 'assets/suits/male_suit_1.png'),
    _Suit('男藏青西装', 'assets/suits/male_suit_2.png'),
    _Suit('男白衬衫', 'assets/suits/male_shirt_1.png'),
    _Suit('女黑西装', 'assets/suits/female_suit_1.png'),
    _Suit('女深蓝职业装', 'assets/suits/female_suit_2.png'),
    _Suit('女白衬衫', 'assets/suits/female_shirt_1.png'),
  ];
  _PhotoSize _size = _sizes.first;
  Color _background = const Color(0xFF438EDB);
  _Suit _suit = _suits.first;

  Future<void> _choose() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null) return;
    setState(() {
      _source = File(picked.path);
      _mattedUrl = null;
      _personScale = 1;
      _personOffset = Offset.zero;
    });
  }

  Future<void> _matting() async {
    if (_source == null || _processing) return;
    setState(() => _processing = true);
    try {
      final userId = await StorageService.getUserId();
      final hex = '#${_background.value.toRadixString(16).substring(2).toUpperCase()}';
      final url = await _api.portraitMatting(imageFile: _source!, userId: userId, backgroundColor: hex);
      if (!mounted) return;
      setState(() => _mattedUrl = url);
      Fluttertoast.showToast(msg: '人像抠图完成，可换底色和服装');
    } catch (error) {
      Fluttertoast.showToast(msg: error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _save() async {
    if (_source == null || _saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('证件照画布尚未准备好');
      final ratio = _size.width / boundary.size.width;
      final image = await boundary.toImage(pixelRatio: ratio.clamp(1, 8).toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('证件照生成失败');
      await ImageGallerySaverPlus.saveImage(data.buffer.asUint8List(), quality: 100, name: '一链取影_${_size.name}_${_size.width}x${_size.height}_${DateTime.now().millisecondsSinceEpoch}');
      await StorageService.addOperationHistory(category: '智能证件照', title: '${_size.name} ${_size.width}×${_size.height}');
      Fluttertoast.showToast(msg: '${_size.name}证件照已保存到相册');
    } catch (error) {
      Fluttertoast.showToast(msg: '保存失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSheet() async {
    if (_source == null || _saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _sheetKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('排版画布尚未准备好');
      final image = await boundary.toImage(pixelRatio: (1500 / boundary.size.width).clamp(1, 8).toDouble());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('排版生成失败');
      await ImageGallerySaverPlus.saveImage(data.buffer.asUint8List(), quality: 100, name: '一链取影_5寸证件照排版_${DateTime.now().millisecondsSinceEpoch}');
      await StorageService.addOperationHistory(category: '5寸证件照排版', title: '8张${_size.name}冲印版 1500×1050');
      Fluttertoast.showToast(msg: '5寸8张排版已保存到相册');
    } catch (error) {
      Fluttertoast.showToast(msg: '排版保存失败: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('智能证件照'), centerTitle: true, actions: [IconButton(onPressed: _choose, icon: const Icon(Icons.photo_library_outlined))]),
    body: _source == null ? Center(child: FilledButton.icon(onPressed: _choose, icon: const Icon(Icons.add_a_photo_outlined), label: const Text('选择正面照片'))) : _editor(),
  );

  Widget _editor() => ListView(padding: const EdgeInsets.all(16), children: [
    Center(child: SizedBox(width: 260, child: AspectRatio(aspectRatio: _size.width / _size.height, child: RepaintBoundary(key: _exportKey, child: _photoLayer(interactive: true))))),
    const SizedBox(height: 14),
    DropdownButtonFormField<_PhotoSize>(value: _size, decoration: const InputDecoration(labelText: '证件照规格'), items: _sizes.map((item) => DropdownMenuItem(value: item, child: Text('${item.name} ${item.width}×${item.height}'))).toList(), onChanged: (value) => setState(() => _size = value!)),
    const SizedBox(height: 12),
    const Text('背景颜色'),
    Wrap(spacing: 10, children: _colors.map((color) => InkWell(onTap: () => setState(() => _background = color), child: CircleAvatar(radius: 17, backgroundColor: color, child: color == _background ? const Icon(Icons.check, size: 18, color: Colors.black54) : null))).toList()),
    const SizedBox(height: 12),
    DropdownButtonFormField<_Suit>(value: _suit, decoration: const InputDecoration(labelText: '职业装模板'), items: _suits.map((item) => DropdownMenuItem(value: item, child: Text(item.name))).toList(), onChanged: (value) => setState(() => _suit = value!)),
    Row(children: [const Text('人物大小'), Expanded(child: Slider(value: _personScale, min: .8, max: 1.4, onChanged: (value) => setState(() => _personScale = value)))]),
    OutlinedButton.icon(onPressed: _processing ? null : _matting, icon: const Icon(Icons.auto_awesome), label: Text(_processing ? 'AI抠图处理中...' : 'AI智能抠图换底')),
    const SizedBox(height: 8),
    FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_alt), label: Text(_saving ? '正在生成...' : '保存证件照')),
    const SizedBox(height: 16),
    const Text('5寸冲印排版预览（8张）', style: TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    RepaintBoundary(key: _sheetKey, child: AspectRatio(aspectRatio: 10 / 7, child: Container(color: Colors.white, padding: const EdgeInsets.all(8), child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(), itemCount: 8,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: _size.width / _size.height, crossAxisSpacing: 5, mainAxisSpacing: 5),
      itemBuilder: (_, __) => _photoLayer(),
    )))),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: _saving ? null : _saveSheet, icon: const Icon(Icons.grid_view_rounded), label: const Text('保存5寸8张冲印排版')),
  ]);

  Widget _photoLayer({bool interactive = false}) {
    final content = Stack(fit: StackFit.expand, children: [
      Transform.translate(offset: _personOffset, child: Transform.scale(scale: _personScale, child: _mattedUrl != null ? Image.network(_mattedUrl!, fit: BoxFit.cover) : Image.file(_source!, fit: BoxFit.cover))),
      if (_suit.asset != null) Align(alignment: Alignment.bottomCenter, child: FractionallySizedBox(widthFactor: 1.06, heightFactor: .72, child: Image.asset(_suit.asset!, fit: BoxFit.fill))),
    ]);
    return Container(
      color: _background,
      child: interactive ? GestureDetector(onPanUpdate: (event) => setState(() => _personOffset += event.delta), child: content) : content,
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/storage_service.dart';

class ImageRepairPage extends StatefulWidget {
  final String? initialImageUrl;

  const ImageRepairPage({super.key, this.initialImageUrl});

  @override
  State<ImageRepairPage> createState() => _ImageRepairPageState();
}

class _ImageRepairPageState extends State<ImageRepairPage> {
  final GlobalKey _paintKey = GlobalKey();
  final GlobalKey _exportKey = GlobalKey();
  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  String? _imageUrl;
  File? _localImageFile;
  String? _repairedResultUrl;
  bool _processing = false;

  final List<List<Offset>> _strokes = [];
  final List<Rect> _repairRects = [];
  _RepairTool _repairTool = _RepairTool.rect;
  Offset? _repairStart;
  Rect? _currentRepairRect;
  double _strokeWidth = 24.0;
  _ImageWorkMode _workMode = _ImageWorkMode.repair;
  _MarkupTool _markupTool = _MarkupTool.circle;
  Color _markupColor = const Color(0xFFFF334B);
  double _markupWidth = 6.0;
  final List<_MarkupShape> _markupShapes = [];
  List<Offset> _currentMarkupPoints = [];
  _MosaicTool _mosaicTool = _MosaicTool.rect;
  double _mosaicBlockSize = 12.0;
  final List<_MosaicShape> _mosaicShapes = [];
  bool _exporting = false;

  static const List<Color> _markupColors = [
    Color(0xFFFF334B), Color(0xFFFF9500), Color(0xFFFFD60A),
    Color(0xFF34C759), Color(0xFF007AFF), Color(0xFF8E44AD),
    Colors.white, Colors.black,
  ];

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

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.initialImageUrl;
    if (_imageUrl != null) {
      _cacheRemoteImageToLocal(_imageUrl!);
    }
  }

  void _cacheRemoteImageToLocal(String url) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/repair_source_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(url, path);
      setState(() {
        _localImageFile = File(path);
      });
    } catch (_) {}
  }

  Future<void> _chooseLocalImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null || !mounted) return;
    setState(() {
      _localImageFile = File(picked.path);
      _imageUrl = null;
      _repairedResultUrl = null;
      _strokes.clear();
      _repairRects.clear();
      _repairStart = null;
      _currentRepairRect = null;
      _markupShapes.clear();
      _mosaicShapes.clear();
      _currentMarkupPoints = [];
    });
  }

  void _setWorkMode(_ImageWorkMode mode) {
    if (_workMode == mode) return;
    setState(() {
      _workMode = mode;
      _strokes.clear();
      _repairRects.clear();
      _repairStart = null;
      _currentRepairRect = null;
      _markupShapes.clear();
      _mosaicShapes.clear();
      _currentMarkupPoints = [];
      _repairedResultUrl = null;
    });
  }

  void _undo() {
    setState(() {
      if (_workMode == _ImageWorkMode.markup) {
        if (_markupShapes.isNotEmpty) _markupShapes.removeLast();
      } else if (_workMode == _ImageWorkMode.mosaic) {
        if (_mosaicShapes.isNotEmpty) _mosaicShapes.removeLast();
      } else if (_repairTool == _RepairTool.rect && _repairRects.isNotEmpty) {
        _repairRects.removeLast();
      } else if (_strokes.isNotEmpty) {
        _strokes.removeLast();
      }
    });
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _repairRects.clear();
      _repairStart = null;
      _currentRepairRect = null;
      _markupShapes.clear();
      _mosaicShapes.clear();
      _currentMarkupPoints = [];
      _repairedResultUrl = null;
    });
  }

  // 生成黑底白线遮罩并提交给后端
  void _submitRepair() async {
    if (_localImageFile == null || !await _localImageFile!.exists()) {
      Fluttertoast.showToast(msg: '图片加载中，请稍候');
      return;
    }
    if (_strokes.isEmpty && _repairRects.isEmpty) {
      Fluttertoast.showToast(msg: '请框选或涂抹需要修复的区域');
      return;
    }

    setState(() => _processing = true);

    try {
      final userId = await StorageService.getUserId();
      await _apiService.consumeQuota(userId: userId, feature: 'image_repair');
      // 1. 将手指涂抹的画板渲染为黑底白字遮罩 Mask PNG
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final size = _paintKey.currentContext?.size ?? const Size(300, 300);

      // 填充纯黑底
      final bgPaint = Paint()..color = Colors.black;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

      // 绘制纯白涂抹轨迹
      final maskPaint = Paint()
        ..color = Colors.white
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = _strokeWidth
        ..style = PaintingStyle.stroke;

      for (final rect in _repairRects) {
        canvas.drawRect(rect, maskPaint..style = PaintingStyle.fill);
      }
      maskPaint.style = PaintingStyle.stroke;

      for (var stroke in _strokes) {
        if (stroke.length > 1) {
          for (int i = 0; i < stroke.length - 1; i++) {
            canvas.drawLine(stroke[i], stroke[i + 1], maskPaint);
          }
        } else if (stroke.isNotEmpty) {
          canvas.drawCircle(stroke.first, _strokeWidth / 2, maskPaint..style = PaintingStyle.fill);
          maskPaint.style = PaintingStyle.stroke;
        }
      }

      final picture = recorder.endRecording();
      final img = await picture.toImage(size.width.toInt(), size.height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      final maskBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final maskFile = File('${tempDir.path}/mask_${DateTime.now().millisecondsSinceEpoch}.png');
      await maskFile.writeAsBytes(maskBytes);

      // 2. 提交给 FastAPI 端的 OpenCV Telea 修复
      final resultUrl = await _apiService.inpaintImage(
        imageFile: _localImageFile!,
        maskFile: maskFile,
      );

      setState(() {
        _repairedResultUrl = resultUrl;
        _processing = false;
        _strokes.clear();
        _repairRects.clear();
        _repairStart = null;
        _currentRepairRect = null;
      });

      await StorageService.addOperationHistory(category: '图片处理', title: '图片修复');

      Fluttertoast.showToast(msg: '修复完成！');
    } catch (e) {
      setState(() => _processing = false);
      final message = e.toString();
      if (message.contains('次数已用尽') || message.contains('次数不足')) {
        await _showQuotaLimit();
      } else {
        Fluttertoast.showToast(msg: '修复失败: $e');
      }
    }
  }

  // 保存修复后的图片到相册
  void _saveResultToAlbum() async {
    if (_repairedResultUrl == null) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/repaired_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(_repairedResultUrl!, path);
      await ImageGallerySaverPlus.saveFile(path);
      Fluttertoast.showToast(msg: '已成功保存修复图片到手机相册！');
    } catch (e) {
      Fluttertoast.showToast(msg: '保存失败: $e');
    }
  }

  void _finishMarkupGesture() {
    if (_currentMarkupPoints.length < 2) {
      setState(() => _currentMarkupPoints = []);
      return;
    }
    final points = List<Offset>.from(_currentMarkupPoints);
    _MarkupShape? shape;
    if (_markupTool == _MarkupTool.circle) {
      final xs = points.map((e) => e.dx);
      final ys = points.map((e) => e.dy);
      final left = xs.reduce((a, b) => a < b ? a : b);
      final right = xs.reduce((a, b) => a > b ? a : b);
      final top = ys.reduce((a, b) => a < b ? a : b);
      final bottom = ys.reduce((a, b) => a > b ? a : b);
      if (right - left >= 8 && bottom - top >= 8) {
        shape = _MarkupShape.circle(Rect.fromLTRB(left, top, right, bottom), _markupColor, _markupWidth);
      }
    } else if (_markupTool == _MarkupTool.arrow) {
      if ((points.last - points.first).distance >= 12) {
        shape = _MarkupShape.arrow(points.first, points.last, _markupColor, _markupWidth);
      }
    } else {
      shape = _MarkupShape.free(points, _markupColor, _markupWidth);
    }
    setState(() {
      if (shape != null) _markupShapes.add(shape!);
      _currentMarkupPoints = [];
    });
  }

  void _finishMosaicGesture() {
    if (_currentMarkupPoints.length < 2) {
      setState(() => _currentMarkupPoints = []);
      return;
    }
    final points = List<Offset>.from(_currentMarkupPoints);
    final xs = points.map((e) => e.dx);
    final ys = points.map((e) => e.dy);
    final left = xs.reduce((a, b) => a < b ? a : b);
    final right = xs.reduce((a, b) => a > b ? a : b);
    final top = ys.reduce((a, b) => a < b ? a : b);
    final bottom = ys.reduce((a, b) => a > b ? a : b);
    setState(() {
      if (right - left >= 8 && bottom - top >= 8) {
        _mosaicShapes.add(_MosaicShape(
          rect: Rect.fromLTRB(left, top, right, bottom),
          circle: _mosaicTool == _MosaicTool.circle,
          blockSize: _mosaicBlockSize,
        ));
      }
      _currentMarkupPoints = [];
    });
  }

  Future<void> _saveMarkedImage() async {
    final isMosaic = _workMode == _ImageWorkMode.mosaic;
    if ((!isMosaic && _markupShapes.isEmpty) || (isMosaic && _mosaicShapes.isEmpty)) {
      Fluttertoast.showToast(msg: isMosaic ? '请先框选马赛克区域' : '请先添加圆圈、箭头或画笔标注');
      return;
    }
    try {
      final userId = await StorageService.getUserId();
      await _apiService.consumeQuota(
        userId: userId,
        feature: isMosaic ? 'image_mosaic' : 'image_markup',
      );
      if (isMosaic) {
        setState(() => _exporting = true);
        await WidgetsBinding.instance.endOfFrame;
      }
      final boundary = _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('标注画布尚未准备好');
      const ratio = 2.5;
      ui.Image image = await boundary.toImage(pixelRatio: ratio);
      if (isMosaic) image = await _pixelateImage(image, ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('图片生成失败');
      final result = await ImageGallerySaverPlus.saveImage(
        data.buffer.asUint8List(),
        quality: 100,
        name: '一链取影_${isMosaic ? '马赛克' : '标注'}_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (result is Map && result['isSuccess'] == false) throw Exception('相册写入失败');
      await StorageService.addOperationHistory(
        category: '图片处理',
        title: isMosaic ? '图片马赛克处理' : '图片标注',
      );
      Fluttertoast.showToast(msg: isMosaic ? '马赛克图片已保存到相册' : '标注图片已保存到相册');
    } catch (error) {
      final message = error.toString();
      if (message.contains('次数已用尽') || message.contains('次数不足')) {
        await _showQuotaLimit();
      } else {
        Fluttertoast.showToast(msg: '保存失败: $error');
      }
    } finally {
      if (mounted && _exporting) setState(() => _exporting = false);
    }
  }

  Future<ui.Image> _pixelateImage(ui.Image source, double ratio) async {
    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw Exception('无法读取图片像素');
    final pixels = data.buffer.asUint8List();
    final width = source.width;
    final height = source.height;
    for (final shape in _mosaicShapes) {
      final left = (shape.rect.left * ratio).floor().clamp(0, width - 1).toInt();
      final top = (shape.rect.top * ratio).floor().clamp(0, height - 1).toInt();
      final right = (shape.rect.right * ratio).ceil().clamp(left + 1, width).toInt();
      final bottom = (shape.rect.bottom * ratio).ceil().clamp(top + 1, height).toInt();
      final block = (shape.blockSize * ratio).round().clamp(5, 80).toInt();
      final cx = (left + right) / 2;
      final cy = (top + bottom) / 2;
      final rx = (right - left) / 2;
      final ry = (bottom - top) / 2;
      bool inside(int x, int y) => !shape.circle ||
          (((x - cx) * (x - cx)) / (rx * rx) + ((y - cy) * (y - cy)) / (ry * ry) <= 1);
      for (var by = top; by < bottom; by += block) {
        for (var bx = left; bx < right; bx += block) {
          var sr = 0, sg = 0, sb = 0, sa = 0, count = 0;
          for (var y = by; y < (by + block).clamp(top, bottom); y++) {
            for (var x = bx; x < (bx + block).clamp(left, right); x++) {
              if (!inside(x, y)) continue;
              final i = (y * width + x) * 4;
              sr += pixels[i]; sg += pixels[i + 1]; sb += pixels[i + 2]; sa += pixels[i + 3]; count++;
            }
          }
          if (count == 0) continue;
          final r = sr ~/ count, g = sg ~/ count, b = sb ~/ count, a = sa ~/ count;
          for (var y = by; y < (by + block).clamp(top, bottom); y++) {
            for (var x = bx; x < (bx + block).clamp(left, right); x++) {
              if (!inside(x, y)) continue;
              final i = (y * width + x) * 4;
              pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = a;
            }
          }
        }
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final hasSource = _localImageFile != null || _imageUrl != null;
    return Scaffold(
      backgroundColor: const Color(0xFF1E2022),
      appBar: AppBar(
        title: Text(
          _workMode == _ImageWorkMode.repair
              ? '图片修复'
              : (_workMode == _ImageWorkMode.markup ? '图片智能标注' : '区域马赛克'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF16181A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: '从相册选图',
            onPressed: _chooseLocalImage,
          ),
          if (_repairedResultUrl != null)
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Color(0xFF07C160)),
              onPressed: _saveResultToAlbum,
            ),
        ],
      ),
      body: Column(
        children: [
          // 画板显示区域
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black,
                    child: RepaintBoundary(
                      key: _exportKey,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                        // 底图
                        if (_repairedResultUrl != null)
                          CachedNetworkImage(
                            imageUrl: _repairedResultUrl!,
                            fit: BoxFit.contain,
                          )
                        else if (_imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: _imageUrl!,
                            fit: BoxFit.contain,
                          )
                        else if (_localImageFile != null)
                          Image.file(_localImageFile!, fit: BoxFit.contain)
                        else
                          const Center(
                            child: Text(
                              '暂未选择图片\n请先从提取页面带入或选图',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                          ),

                        // 手指涂抹交互层
                        if (_repairedResultUrl == null && hasSource)
                          RepaintBoundary(
                            key: _paintKey,
                            child: GestureDetector(
                              onPanStart: (details) {
                                setState(() {
                                  if (_workMode != _ImageWorkMode.repair) {
                                    _currentMarkupPoints = [details.localPosition];
                                  } else if (_repairTool == _RepairTool.rect) {
                                    _repairStart = details.localPosition;
                                    _currentRepairRect = Rect.fromPoints(_repairStart!, _repairStart!);
                                  } else {
                                    _strokes.add([details.localPosition]);
                                  }
                                });
                              },
                              onPanUpdate: (details) {
                                setState(() {
                                  if (_workMode != _ImageWorkMode.repair) {
                                    _currentMarkupPoints.add(details.localPosition);
                                  } else if (_repairTool == _RepairTool.rect && _repairStart != null) {
                                    _currentRepairRect = Rect.fromPoints(_repairStart!, details.localPosition);
                                  } else if (_strokes.isNotEmpty) {
                                    _strokes.last.add(details.localPosition);
                                  }
                                });
                              },
                              onPanEnd: (_) {
                                if (_workMode == _ImageWorkMode.markup) _finishMarkupGesture();
                                if (_workMode == _ImageWorkMode.mosaic) _finishMosaicGesture();
                                if (_workMode == _ImageWorkMode.repair && _repairTool == _RepairTool.rect) {
                                  setState(() {
                                    final rect = _currentRepairRect;
                                    if (rect != null && rect.width >= 8 && rect.height >= 8) _repairRects.add(rect);
                                    _repairStart = null;
                                    _currentRepairRect = null;
                                  });
                                }
                              },
                              child: CustomPaint(
                                painter: _RepairAndMarkupPainter(
                                  strokes: _strokes,
                                  repairRects: _repairRects,
                                  currentRepairRect: _currentRepairRect,
                                  strokeWidth: _strokeWidth,
                                  markupShapes: _markupShapes,
                                  currentMarkupPoints: _currentMarkupPoints,
                                  currentMarkupColor: _markupColor,
                                  currentMarkupWidth: _markupWidth,
                                  mosaicShapes: _mosaicShapes,
                                  showMosaicGuides: !_exporting,
                                ),
                                size: Size.infinite,
                              ),
                            ),
                          ),

                        if (_processing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF127C44)),
                                  SizedBox(height: 12),
                                  Text('AI 算法正在消除填补中...', style: TextStyle(color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 底部控制工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: const Color(0xFF16181A),
            child: SafeArea(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('图片修复'),
                          selected: _workMode == _ImageWorkMode.repair,
                          onSelected: (_) => _setWorkMode(_ImageWorkMode.repair),
                          selectedColor: const Color(0xFF6246A8),
                          labelStyle: TextStyle(color: _workMode == _ImageWorkMode.repair ? Colors.white : Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('智能标注'),
                          selected: _workMode == _ImageWorkMode.markup,
                          onSelected: (_) => _setWorkMode(_ImageWorkMode.markup),
                          selectedColor: const Color(0xFF127C44),
                          labelStyle: TextStyle(color: _workMode == _ImageWorkMode.markup ? Colors.white : Colors.white70),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('马赛克'),
                          selected: _workMode == _ImageWorkMode.mosaic,
                          onSelected: (_) => _setWorkMode(_ImageWorkMode.mosaic),
                          selectedColor: const Color(0xFF1769AA),
                          labelStyle: TextStyle(color: _workMode == _ImageWorkMode.mosaic ? Colors.white : Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_workMode == _ImageWorkMode.repair) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('矩形框选'),
                          selected: _repairTool == _RepairTool.rect,
                          onSelected: (_) => setState(() {
                            _repairTool = _RepairTool.rect;
                            _repairStart = null;
                            _currentRepairRect = null;
                          }),
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('画笔涂抹'),
                          selected: _repairTool == _RepairTool.brush,
                          onSelected: (_) => setState(() {
                            _repairTool = _RepairTool.brush;
                            _repairStart = null;
                            _currentRepairRect = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_workMode == _ImageWorkMode.markup) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('自动圆圈'),
                            selected: _markupTool == _MarkupTool.circle,
                            onSelected: (_) => setState(() => _markupTool = _MarkupTool.circle),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('自动箭头'),
                            selected: _markupTool == _MarkupTool.arrow,
                            onSelected: (_) => setState(() => _markupTool = _MarkupTool.arrow),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('自由画笔'),
                            selected: _markupTool == _MarkupTool.free,
                            onSelected: (_) => setState(() => _markupTool = _MarkupTool.free),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _markupColors.map((color) => GestureDetector(
                        onTap: () => setState(() => _markupColor = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _markupColor == color ? const Color(0xFF07C160) : Colors.white38,
                              width: _markupColor == color ? 3 : 1,
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                  if (_workMode == _ImageWorkMode.mosaic) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text('矩形框选'),
                          selected: _mosaicTool == _MosaicTool.rect,
                          onSelected: (_) => setState(() => _mosaicTool = _MosaicTool.rect),
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('手画圆圈'),
                          selected: _mosaicTool == _MosaicTool.circle,
                          onSelected: (_) => setState(() => _mosaicTool = _MosaicTool.circle),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('颗粒', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Expanded(
                          child: Slider(
                            min: 6,
                            max: 30,
                            value: _mosaicBlockSize,
                            activeColor: const Color(0xFF1769AA),
                            onChanged: (value) => setState(() => _mosaicBlockSize = value),
                          ),
                        ),
                        Text(_mosaicBlockSize.round().toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ],
                  // 工具按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _undo,
                        icon: const Icon(Icons.undo_rounded, color: Colors.white70),
                        tooltip: '撤销上一笔',
                      ),
                      IconButton(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                        tooltip: '清空涂抹',
                      ),
                      // 画笔大小切换
                      if (_workMode != _ImageWorkMode.mosaic) DropdownButton<double>(
                        value: _workMode == _ImageWorkMode.markup ? _markupWidth : _strokeWidth,
                        dropdownColor: const Color(0xFF2B2E33),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 4.0, child: Text('细线', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 6.0, child: Text('标准线', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 10.0, child: Text('粗线', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 12.0, child: Text('细画笔', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 24.0, child: Text('标准画笔', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 40.0, child: Text('粗画笔', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() {
                            if (_workMode == _ImageWorkMode.markup) {
                              _markupWidth = v;
                            } else {
                              _strokeWidth = v;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 执行按钮
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: _workMode != _ImageWorkMode.repair
                        ? ElevatedButton.icon(
                            onPressed: hasSource && (_workMode == _ImageWorkMode.markup ? _markupShapes.isNotEmpty : _mosaicShapes.isNotEmpty)
                                ? _saveMarkedImage
                                : null,
                            icon: const Icon(Icons.save_alt_rounded, color: Colors.white),
                            label: Text(
                              _workMode == _ImageWorkMode.mosaic ? '保存马赛克图片到手机相册' : '保存标注图片到手机相册',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF127C44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : _repairedResultUrl != null
                        ? ElevatedButton.icon(
                            onPressed: _saveResultToAlbum,
                            icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                            label: const Text('保存修复图片到手机相册', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF07C160),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: _processing ? null : _submitRepair,
                            icon: const Icon(Icons.auto_fix_high_rounded, color: Colors.white),
                            label: const Text('开始智能消除修复', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6246A8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ImageWorkMode { repair, markup, mosaic }

enum _RepairTool { rect, brush }

enum _MarkupTool { circle, arrow, free }

enum _MosaicTool { rect, circle }

class _MosaicShape {
  final Rect rect;
  final bool circle;
  final double blockSize;

  const _MosaicShape({required this.rect, required this.circle, required this.blockSize});
}

enum _MarkupShapeType { circle, arrow, free }

class _MarkupShape {
  final _MarkupShapeType type;
  final Color color;
  final double width;
  final Rect? rect;
  final Offset? start;
  final Offset? end;
  final List<Offset>? points;

  const _MarkupShape._(this.type, this.color, this.width, {this.rect, this.start, this.end, this.points});

  factory _MarkupShape.circle(Rect rect, Color color, double width) =>
      _MarkupShape._(_MarkupShapeType.circle, color, width, rect: rect);

  factory _MarkupShape.arrow(Offset start, Offset end, Color color, double width) =>
      _MarkupShape._(_MarkupShapeType.arrow, color, width, start: start, end: end);

  factory _MarkupShape.free(List<Offset> points, Color color, double width) =>
      _MarkupShape._(_MarkupShapeType.free, color, width, points: points);
}

class _RepairAndMarkupPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Rect> repairRects;
  final Rect? currentRepairRect;
  final double strokeWidth;
  final List<_MarkupShape> markupShapes;
  final List<Offset> currentMarkupPoints;
  final Color currentMarkupColor;
  final double currentMarkupWidth;
  final List<_MosaicShape> mosaicShapes;
  final bool showMosaicGuides;

  _RepairAndMarkupPainter({
    required this.strokes,
    required this.repairRects,
    required this.currentRepairRect,
    required this.strokeWidth,
    required this.markupShapes,
    required this.currentMarkupPoints,
    required this.currentMarkupColor,
    required this.currentMarkupWidth,
    required this.mosaicShapes,
    required this.showMosaicGuides,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x99FF334B) // 半透明荧光粉红指示
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    for (var stroke in strokes) {
      if (stroke.length > 1) {
        for (int i = 0; i < stroke.length - 1; i++) {
          canvas.drawLine(stroke[i], stroke[i + 1], paint);
        }
      } else if (stroke.isNotEmpty) {
        canvas.drawCircle(stroke.first, strokeWidth / 2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
      }
    }

    final rectFill = Paint()
      ..color = const Color(0x55FF334B)
      ..style = PaintingStyle.fill;
    final rectBorder = Paint()
      ..color = const Color(0xDDFF334B)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final rect in repairRects) {
      canvas.drawRect(rect, rectFill);
      canvas.drawRect(rect, rectBorder);
    }
    if (currentRepairRect != null) {
      canvas.drawRect(currentRepairRect!, rectFill);
      canvas.drawRect(currentRepairRect!, rectBorder);
    }

    for (final shape in markupShapes) {
      _drawMarkupShape(canvas, shape);
    }

    if (currentMarkupPoints.isNotEmpty) {
      final previewPaint = Paint()
        ..color = currentMarkupColor.withValues(alpha: 0.8)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = currentMarkupWidth
        ..style = PaintingStyle.stroke;
      _drawPath(canvas, currentMarkupPoints, previewPaint);
    }

    if (showMosaicGuides) {
      for (final shape in mosaicShapes) {
        _drawMosaicGuide(canvas, shape);
      }
    }
  }

  void _drawMarkupShape(Canvas canvas, _MarkupShape shape) {
    final paint = Paint()
      ..color = shape.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = shape.width
      ..style = PaintingStyle.stroke;
    if (shape.type == _MarkupShapeType.circle && shape.rect != null) {
      canvas.drawOval(shape.rect!, paint);
    } else if (shape.type == _MarkupShapeType.arrow && shape.start != null && shape.end != null) {
      final start = shape.start!;
      final end = shape.end!;
      canvas.drawLine(start, end, paint);
      final angle = (end - start).direction;
      final headLength = ((end - start).distance * 0.22).clamp(14.0, 30.0);
      final first = end - Offset.fromDirection(angle - 0.55, headLength);
      final second = end - Offset.fromDirection(angle + 0.55, headLength);
      canvas.drawLine(end, first, paint);
      canvas.drawLine(end, second, paint);
    } else if (shape.type == _MarkupShapeType.free && shape.points != null) {
      _drawPath(canvas, shape.points!, paint);
    }
  }

  void _drawPath(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawMosaicGuide(Canvas canvas, _MosaicShape shape) {
    final clipPath = Path();
    if (shape.circle) {
      clipPath.addOval(shape.rect);
    } else {
      clipPath.addRect(shape.rect);
    }
    canvas.save();
    canvas.clipPath(clipPath);
    final block = shape.blockSize.clamp(6.0, 30.0);
    for (double y = shape.rect.top; y < shape.rect.bottom; y += block) {
      for (double x = shape.rect.left; x < shape.rect.right; x += block) {
        final even = (((x - shape.rect.left) / block).floor() + ((y - shape.rect.top) / block).floor()).isEven;
        final paint = Paint()..color = even ? const Color(0x88999999) : const Color(0x88666666);
        canvas.drawRect(Rect.fromLTWH(x, y, block, block), paint);
      }
    }
    canvas.restore();
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (shape.circle) {
      canvas.drawOval(shape.rect, border);
    } else {
      canvas.drawRect(shape.rect, border);
    }
  }

  @override
  bool shouldRepaint(covariant _RepairAndMarkupPainter oldDelegate) => true;
}

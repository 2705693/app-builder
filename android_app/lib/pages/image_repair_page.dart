import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../services/api_service.dart';

class ImageRepairPage extends StatefulWidget {
  final String? initialImageUrl;

  const ImageRepairPage({super.key, this.initialImageUrl});

  @override
  State<ImageRepairPage> createState() => _ImageRepairPageState();
}

class _ImageRepairPageState extends State<ImageRepairPage> {
  final GlobalKey _paintKey = GlobalKey();
  final ApiService _apiService = ApiService();

  String? _imageUrl;
  File? _localImageFile;
  String? _repairedResultUrl;
  bool _processing = false;

  final List<List<Offset>> _strokes = [];
  double _strokeWidth = 24.0;

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

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _strokes.removeLast();
      });
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _repairedResultUrl = null;
    });
  }

  // 生成黑底白线遮罩并提交给后端
  void _submitRepair() async {
    if (_localImageFile == null || !await _localImageFile!.exists()) {
      Fluttertoast.showToast(msg: '图片加载中，请稍候');
      return;
    }
    if (_strokes.isEmpty) {
      Fluttertoast.showToast(msg: '请在图片上涂抹需要消除的区域');
      return;
    }

    setState(() => _processing = true);

    try {
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
      });

      Fluttertoast.showToast(msg: '修复完成！');
    } catch (e) {
      setState(() => _processing = false);
      Fluttertoast.showToast(msg: '修复失败: $e');
    }
  }

  // 保存修复后的图片到相册
  void _saveResultToAlbum() async {
    if (_repairedResultUrl == null) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/repaired_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Dio().download(_repairedResultUrl!, path);
      await Gal.putImage(path, album: '钞机汇玩');
      Fluttertoast.showToast(msg: '已成功保存修复图片到手机相册！');
    } catch (e) {
      Fluttertoast.showToast(msg: '保存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E2022),
      appBar: AppBar(
        title: const Text('图片局部修复', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        backgroundColor: const Color(0xFF16181A),
        foregroundColor: Colors.white,
        actions: [
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
                        else
                          const Center(
                            child: Text(
                              '暂未选择图片\n请先从提取页面带入或选图',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                          ),

                        // 手指涂抹交互层
                        if (_repairedResultUrl == null && _imageUrl != null)
                          RepaintBoundary(
                            key: _paintKey,
                            child: GestureDetector(
                              onPanStart: (details) {
                                setState(() {
                                  _strokes.add([details.localPosition]);
                                });
                              },
                              onPanUpdate: (details) {
                                setState(() {
                                  _strokes.last.add(details.localPosition);
                                });
                              },
                              child: CustomPaint(
                                painter: _DoodlePainter(
                                  strokes: _strokes,
                                  strokeWidth: _strokeWidth,
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

          // 底部控制工具栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: const Color(0xFF16181A),
            child: SafeArea(
              child: Column(
                children: [
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
                      DropdownButton<double>(
                        value: _strokeWidth,
                        dropdownColor: const Color(0xFF2B2E33),
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 12.0, child: Text('细画笔', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 24.0, child: Text('标准', style: TextStyle(color: Colors.white))),
                          DropdownMenuItem(value: 40.0, child: Text('粗画笔', style: TextStyle(color: Colors.white))),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _strokeWidth = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 执行按钮
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: _repairedResultUrl != null
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

class _DoodlePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final double strokeWidth;

  _DoodlePainter({required this.strokes, required this.strokeWidth});

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
  }

  @override
  bool shouldRepaint(covariant _DoodlePainter oldDelegate) => true;
}

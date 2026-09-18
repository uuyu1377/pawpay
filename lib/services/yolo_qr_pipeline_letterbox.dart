import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloQrPipeline {
  YoloQrPipeline._();

  static final YoloQrPipeline instance = YoloQrPipeline._();

  static const String _modelAssetPath = 'assets/yolov9t_invoice_float32.tflite';
  static const int _inputSize = 640;

  Interpreter? _interpreter;
  Future<void>? _loadingFuture;

  Future<void> loadModel() {
    if (_interpreter != null) return Future.value();
    _loadingFuture ??= _loadModelInternal();
    return _loadingFuture!;
  }

  Future<void> _loadModelInternal() async {
    if (_interpreter != null) return;

    final stopwatch = Stopwatch()..start(); // [新增 Log] 測量載入時間
    final options = InterpreterOptions()..threads = 2;
    _interpreter = await Interpreter.fromAsset(
      _modelAssetPath,
      options: options,
    );
    stopwatch.stop();

    debugPrint('========== YOLO 模型初始化 ==========');
    debugPrint('YOLO QR：模型載入成功 (${stopwatch.elapsedMilliseconds} ms) : $_modelAssetPath');
    debugPrint('YOLO input shape: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('YOLO output shape: ${_interpreter!.getOutputTensor(0).shape}');
    debugPrint('====================================');
  }



  Future<List<YoloQrDetection>> detectQrBoxesForGuide(
    File imageFile, {
    double confidenceThreshold = 0.18,
    int maxBoxes = 6,
  }) async {
    try {
      await loadModel();
      final bytes = await imageFile.readAsBytes();
      final source = img.decodeImage(bytes);
      if (source == null) return const <YoloQrDetection>[];

      final boxes = _detectQrBoxes(
        source,
        confidenceThreshold: confidenceThreshold,
      ).take(maxBoxes).toList();

      return boxes
          .map((b) => YoloQrDetection(rect: b.rect, score: b.score))
          .toList(growable: false);
    } catch (e, st) {
      debugPrint('YOLO 輔助定位失敗：$e');
      debugPrint('$st');
      return const <YoloQrDetection>[];
    }
  }

  Future<String?> tryScanInvoiceQr(
      File imageFile, {
        double confidenceThreshold = 0.25,
        int maxBoxes = 6,
      }) async {
    debugPrint('\n========== YOLO QR 辨識流程開始 ==========');
    final totalStopwatch = Stopwatch()..start();

    try {
      await loadModel();

      final decodeStopwatch = Stopwatch()..start();
      final bytes = await imageFile.readAsBytes();
      final source = img.decodeImage(bytes);
      decodeStopwatch.stop();

      if (source == null) {
        debugPrint('❌ YOLO QR：圖片解碼失敗');
        return null;
      }
      debugPrint('🖼️ 圖片解碼成功: 寬 ${source.width} x 高 ${source.height} (${decodeStopwatch.elapsedMilliseconds} ms)');

      final yoloStopwatch = Stopwatch()..start();
      final boxes = _detectQrBoxes(
        source,
        confidenceThreshold: confidenceThreshold,
      ).take(maxBoxes).toList();
      yoloStopwatch.stop();

      debugPrint('🎯 YOLO 推論與 NMS 完成，共耗時 ${yoloStopwatch.elapsedMilliseconds} ms');
      debugPrint('📊 最終保留 ${boxes.length} 個候選框 (門檻: $confidenceThreshold)');

      if (boxes.isEmpty) {
        debugPrint('⚠️ YOLO 沒抓到任何大於門檻的框，交由後續 OCR 備援。');
        return null;
      }

      final scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
      final tempFiles = <File>[];
      final rawValues = <String>[];

      try {
        boxes.sort((a, b) => a.rect.left.compareTo(b.rect.left));

        for (var i = 0; i < boxes.length; i++) {
          debugPrint('\n--- 處理第 ${i + 1} 個候選框 ---');
          debugPrint('📐 信心度: ${boxes[i].score.toStringAsFixed(3)}');
          debugPrint('📍 座標: [Left: ${boxes[i].rect.left.toInt()}, Top: ${boxes[i].rect.top.toInt()}, Right: ${boxes[i].rect.right.toInt()}, Bottom: ${boxes[i].rect.bottom.toInt()}]');

          final cropFile = await _cropToTempFile(
            source,
            boxes[i].rect,
            imageFile.parent.path,
            i,
          );

          if (cropFile == null) {
            debugPrint('❌ 裁切失敗 (座標可能超出邊界或長寬為0)');
            continue;
          }
          tempFiles.add(cropFile);
          debugPrint('✂️ 裁切成功，準備交給 QR 解碼器解碼...');

          final values = await _scanQrFile(scanner, cropFile);
          rawValues.addAll(values);
        }
      } finally {
        await scanner.close();
        for (final f in tempFiles) {
          try {
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }

      final payload = _buildInvoiceQrPayload(rawValues);
      totalStopwatch.stop();

      debugPrint('\n========== YOLO QR 流程總結 ==========');
      debugPrint('⏱️ 總耗時: ${totalStopwatch.elapsedMilliseconds} ms');
      if (payload != null) {
        debugPrint('✅ 成功組合電子發票 QR Payload！');
        debugPrint('======================================\n');
        return payload;
      } else {
        debugPrint('❌ 有框但 QR 解碼器沒解出有效內容，交由後續 OCR 備援。');
        debugPrint('======================================\n');
        return null;
      }
    } catch (e, st) {
      debugPrint('❌ YOLO QR 流程發生異常：$e');
      debugPrint('$st');
      return null;
    }
  }

  List<_YoloBox> _detectQrBoxes(
      img.Image source, {
        required double confidenceThreshold,
      }) {
    final interpreter = _interpreter;
    if (interpreter == null) return [];

    final letterbox = _letterbox(source);
    debugPrint('📏 Letterbox 處理: 縮放比例=${letterbox.scale.toStringAsFixed(3)}, 補邊X=${letterbox.padX}, 補邊Y=${letterbox.padY}');

    final input = [
      List.generate(_inputSize, (y) {
        return List.generate(_inputSize, (x) {
          final p = letterbox.image.getPixel(x, y);
          return <double>[
            p.r.toDouble() / 255.0,
            p.g.toDouble() / 255.0,
            p.b.toDouble() / 255.0,
          ];
        });
      }),
    ];

    final outputShape = interpreter.getOutputTensor(0).shape;
    final output = _createOutputTensor(outputShape);

    debugPrint('🧠 YOLO 神經網路運算中...');
    interpreter.run(input, output);
    debugPrint('🧠 YOLO 神經網路運算結束，開始解析輸出...');

    final boxes = _parseYoloOutput(
      output,
      outputShape,
      source.width,
      source.height,
      letterbox: letterbox,
      confidenceThreshold: confidenceThreshold,
    );

    debugPrint('🔍 原始輸出過濾後剩餘 ${boxes.length} 個框，準備執行 NMS (非極大值抑制)...');
    return _nms(boxes, iouThreshold: 0.45);
  }

  _LetterboxResult _letterbox(img.Image source) {
    final scale = math.min(
      _inputSize / source.width,
      _inputSize / source.height,
    );

    final resizedW = (source.width * scale).round().clamp(1, _inputSize);
    final resizedH = (source.height * scale).round().clamp(1, _inputSize);

    final resized = img.copyResize(
      source,
      width: resizedW,
      height: resizedH,
      interpolation: img.Interpolation.linear,
    );

    final canvas = img.Image(width: _inputSize, height: _inputSize);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));

    final padX = ((_inputSize - resizedW) / 2).round();
    final padY = ((_inputSize - resizedH) / 2).round();

    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    return _LetterboxResult(
      image: canvas,
      scale: scale,
      padX: padX.toDouble(),
      padY: padY.toDouble(),
    );
  }

  dynamic _createOutputTensor(List<int> shape) {
    if (shape.length == 3) {
      return List.generate(
        shape[0],
            (_) => List.generate(
          shape[1],
              (_) => List.filled(shape[2], 0.0),
        ),
      );
    }

    if (shape.length == 2) {
      return List.generate(
        shape[0],
            (_) => List.filled(shape[1], 0.0),
      );
    }

    if (shape.length == 1) {
      return List.filled(shape[0], 0.0);
    }

    throw UnsupportedError('不支援的 YOLO output shape: $shape');
  }

  List<_YoloBox> _parseYoloOutput(
      dynamic output,
      List<int> shape,
      int originalW,
      int originalH, {
        required _LetterboxResult letterbox,
        required double confidenceThreshold,
      }) {
    final boxes = <_YoloBox>[];
    if (shape.length != 3 || shape[0] != 1) return boxes;

    final dim1 = shape[1];
    final dim2 = shape[2];

    if (dim1 <= 20 && dim2 > dim1) {
      for (var i = 0; i < dim2; i++) {
        final cx = _toDouble(output[0][0][i]);
        final cy = _toDouble(output[0][1][i]);
        final w = _toDouble(output[0][2][i]);
        final h = _toDouble(output[0][3][i]);
        final score = _toDouble(output[0][4][i]);
        _addBoxIfValid(
          boxes, cx, cy, w, h, score, originalW, originalH, letterbox, confidenceThreshold,
        );
      }
    } else {
      for (var i = 0; i < dim1; i++) {
        final row = output[0][i];
        final cx = _toDouble(row[0]);
        final cy = _toDouble(row[1]);
        final w = _toDouble(row[2]);
        final h = _toDouble(row[3]);
        final score = _toDouble(row[4]);
        _addBoxIfValid(
          boxes, cx, cy, w, h, score, originalW, originalH, letterbox, confidenceThreshold,
        );
      }
    }

    boxes.sort((a, b) => b.score.compareTo(a.score));
    return boxes;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  void _addBoxIfValid(
      List<_YoloBox> boxes,
      double cx,
      double cy,
      double w,
      double h,
      double score,
      int originalW,
      int originalH,
      _LetterboxResult letterbox,
      double confidenceThreshold,
      ) {
    if (score < confidenceThreshold) return;
    if (w <= 0 || h <= 0) return;

    final normalized = cx <= 2 && cy <= 2 && w <= 2 && h <= 2;

    final cx640 = normalized ? cx * _inputSize : cx;
    final cy640 = normalized ? cy * _inputSize : cy;
    final w640 = normalized ? w * _inputSize : w;
    final h640 = normalized ? h * _inputSize : h;

    final left640 = cx640 - w640 / 2;
    final top640 = cy640 - h640 / 2;

    final left = (left640 - letterbox.padX) / letterbox.scale;
    final top = (top640 - letterbox.padY) / letterbox.scale;
    final width = w640 / letterbox.scale;
    final height = h640 / letterbox.scale;

    final rect = _expandAndClamp(
      Rect.fromLTWH(left, top, width, height),
      originalW,
      originalH,
      paddingRatio: 0.22,
    );

    if (rect.width < 20 || rect.height < 20) return;
    boxes.add(_YoloBox(rect: rect, score: score));
  }

  Rect _expandAndClamp(
      Rect rect,
      int imageW,
      int imageH, {
        required double paddingRatio,
      }) {
    final padX = rect.width * paddingRatio;
    final padY = rect.height * paddingRatio;

    final left = math.max(0.0, rect.left - padX);
    final top = math.max(0.0, rect.top - padY);
    final right = math.min(imageW.toDouble(), rect.right + padX);
    final bottom = math.min(imageH.toDouble(), rect.bottom + padY);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  List<_YoloBox> _nms(List<_YoloBox> boxes, {required double iouThreshold}) {
    final picked = <_YoloBox>[];
    final candidates = [...boxes]..sort((a, b) => b.score.compareTo(a.score));

    while (candidates.isNotEmpty) {
      final current = candidates.removeAt(0);
      picked.add(current);
      candidates.removeWhere((b) => _iou(current.rect, b.rect) > iouThreshold);
    }

    return picked;
  }

  double _iou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);

    final interW = math.max(0.0, right - left);
    final interH = math.max(0.0, bottom - top);
    final interArea = interW * interH;
    final unionArea = a.width * a.height + b.width * b.height - interArea;

    if (unionArea <= 0) return 0;
    return interArea / unionArea;
  }

  Future<File?> _cropToTempFile(
      img.Image source,
      Rect rect,
      String parentDir,
      int index,
      ) async {
    final x = rect.left.round().clamp(0, source.width - 1);
    final y = rect.top.round().clamp(0, source.height - 1);
    final right = rect.right.round().clamp(x + 1, source.width);
    final bottom = rect.bottom.round().clamp(y + 1, source.height);
    final width = right - x;
    final height = bottom - y;

    if (width <= 0 || height <= 0) return null;

    final cropped = img.copyCrop(
      source,
      x: x,
      y: y,
      width: width,
      height: height,
    );

    final path = '$parentDir/yolo_qr_crop_${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
    final file = File(path);
    await file.writeAsBytes(img.encodeJpg(cropped, quality: 95));
    return file;
  }

  Future<List<String>> _scanQrFile(BarcodeScanner scanner, File file) async {
    final inputImage = InputImage.fromFilePath(file.path);
    final barcodes = await scanner.processImage(inputImage);

    debugPrint('👁️ QR 解碼器在此裁切圖中掃描到 ${barcodes.length} 個結果');
    for (var b in barcodes) {
      debugPrint('   -> 內容: ${b.rawValue}');
    }

    return barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String? _buildInvoiceQrPayload(List<String> rawValues) {
    final unique = <String>[];
    final seen = <String>{};

    for (final raw in rawValues) {
      final t = raw.trim();
      if (t.isEmpty || _isGarbageQr(t)) continue;
      if (seen.add(t)) unique.add(t);
    }

    String? left;
    String? right;

    for (final raw in unique) {
      if (left == null && _looksLikeLeftEInvoiceQr(raw)) {
        left = raw;
      } else if (right == null && _looksLikeRightEInvoiceQr(raw)) {
        right = raw;
      }
    }

    if (left == null) return null;

    return [
      '[MODE] E_INVOICE_QR',
      '[EINV_LEFT_QR] $left',
      if (right != null) '[EINV_RIGHT_QR] $right',
    ].join('\n');
  }

  bool _isGarbageQr(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (t == '**') return true;
    if (RegExp(r'^\*{6,}$').hasMatch(t)) return true;
    if (RegExp(r'^[\*\s:]+$').hasMatch(t)) return true;
    return false;
  }

  bool _looksLikeLeftEInvoiceQr(String s) {
    final t = s.trim();
    if (!RegExp(r'^[A-Z]{2}\d{8}').hasMatch(t)) return false;
    return t.length >= 77;
  }

  bool _looksLikeRightEInvoiceQr(String s) {
    final t = s.trim();
    if (!t.startsWith('**')) return false;
    return t.length > 2;
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
    _loadingFuture = null;
  }
}


class YoloQrDetection {
  final Rect rect;
  final double score;

  const YoloQrDetection({
    required this.rect,
    required this.score,
  });
}

class _LetterboxResult {
  final img.Image image;
  final double scale;
  final double padX;
  final double padY;

  const _LetterboxResult({
    required this.image,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

class _YoloBox {
  final Rect rect;
  final double score;

  const _YoloBox({
    required this.rect,
    required this.score,
  });
}
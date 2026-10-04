import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 送 Google Cloud Vision 前的發票影像前處理。
///
/// 刻意「不做」二值化 / 強銳利化：Vision 是深度學習模型，這些處理對它幫助有限，
/// 而且容易把熱感應紙上褪色的筆畫吃掉、讓數字更容易誤判。
///
/// 只做三件對 Vision 確實有幫助的事：
/// 1. 修正 EXIF 方向（避免橫躺的圖送上去）
/// 2. 限制長邊尺寸（夠清楚、又不會上傳太大）
/// 3. 傳統發票「彩色印刷去除」：預印的紅色 / 綠色格線、欄位標題、發票章等「彩色」部分
///    變成接近白色；黑字、灰色（褪色感熱字）、藍筆、紫色複寫字保留 → 去掉格線干擾。
///    （不用單純取紅色通道，因為綠色發票在紅色通道裡反而會變黑。）
/// 另外計算模糊分數，讓拍糊的照片可以先重拍，不浪費一次 Vision 呼叫。
class InvoiceImagePreprocessor {
  InvoiceImagePreprocessor._();

  /// 傳統發票是否去除彩色印刷（紅 / 綠格線、發票章）。若 A/B 測試結果不如原圖，改成 false 即可。
  static const bool useColorDropoutForTraditional = false;

  /// 上傳圖片的長邊上限（像素）。
  static const int maxLongSide = 2400;

  /// 模糊門檻（Laplacian variance，在長邊 800px 的縮圖上計算）。
  /// 低於此值視為太糊。請用實際手機拍幾張清楚 / 模糊的發票，看 log 印出的分數再微調。
  static const double blurThreshold = 60.0;

  static Future<PreprocessResult> process(File input, {required bool traditional}) async {
    final bytes = await input.readAsBytes();
    final out = await compute(
      _processInIsolate,
      _PreprocessArgs(bytes, traditional && useColorDropoutForTraditional),
    );
    if (out == null) {
      // 解碼失敗就原圖上傳，不要擋住流程
      return PreprocessResult(file: input, blurScore: double.infinity, isBlurry: false);
    }

    final outPath = '${input.parent.path}/ocr_pre_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = await File(outPath).writeAsBytes(out.jpg, flush: true);
    debugPrint('OCR 前處理：${out.width}x${out.height}, blur=${out.blurScore.toStringAsFixed(1)}');
    return PreprocessResult(
      file: outFile,
      blurScore: out.blurScore,
      isBlurry: out.blurScore < blurThreshold,
    );
  }
}

class PreprocessResult {
  final File file;
  final double blurScore;
  final bool isBlurry;
  const PreprocessResult({required this.file, required this.blurScore, required this.isBlurry});
}

class _PreprocessArgs {
  final Uint8List bytes;
  final bool colorDropout;
  const _PreprocessArgs(this.bytes, this.colorDropout);
}

class _PreprocessOut {
  final Uint8List jpg;
  final int width;
  final int height;
  final double blurScore;
  const _PreprocessOut(this.jpg, this.width, this.height, this.blurScore);
}

_PreprocessOut? _processInIsolate(_PreprocessArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);

  final longSide = math.max(image.width, image.height);
  if (longSide > InvoiceImagePreprocessor.maxLongSide) {
    final scale = InvoiceImagePreprocessor.maxLongSide / longSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final blur = _laplacianVariance(image);

  if (args.colorDropout) {
    _dropColoredPrint(image);
  }

  final jpg = img.encodeJpg(image, quality: 92);
  return _PreprocessOut(jpg, image.width, image.height, blur);
}

/// 把彩色印刷（紅、粉紅、橘、黃、綠、青）淡化成白色，其餘轉成一般灰階。
/// 藍色到紫色（色相 190°~290°）視為原子筆 / 複寫字，保留。
/// 飽和度 0.2 以下（黑、灰、白紙）不處理；0.2~0.4 之間漸進淡化，避免邊緣鋸齒。
void _dropColoredPrint(img.Image image) {
  for (final p in image) {
    final r = p.r.toDouble();
    final g = p.g.toDouble();
    final b = p.b.toDouble();
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    var out = 0.299 * r + 0.587 * g + 0.114 * b;

    if (mx > 60) {
      final sat = (mx - mn) / mx;
      if (sat > 0.2) {
        final d = mx - mn;
        double hue;
        if (mx == r) {
          hue = 60 * (((g - b) / d) % 6);
        } else if (mx == g) {
          hue = 60 * ((b - r) / d + 2);
        } else {
          hue = 60 * ((r - g) / d + 4);
        }
        final isInk = hue >= 190 && hue <= 290;
        if (!isInk) {
          final k = ((sat - 0.2) / 0.2).clamp(0.0, 1.0);
          out = out + (255 - out) * k;
        }
      }
    }

    final v = out.round().clamp(0, 255);
    p.r = v;
    p.g = v;
    p.b = v;
  }
}

/// 在長邊 800px 的灰階縮圖上算 Laplacian 變異數，數值越低越模糊。
double _laplacianVariance(img.Image src) {
  final longSide = math.max(src.width, src.height);
  final scale = longSide > 800 ? 800 / longSide : 1.0;
  final small = scale < 1.0
      ? img.copyResize(src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average)
      : src;

  final w = small.width, h = small.height;
  if (w < 3 || h < 3) return double.infinity;

  final gray = Float64List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = small.getPixel(x, y);
      gray[i++] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
  }

  double sum = 0, sumSq = 0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = y * w + x;
      final lap = gray[c - w] + gray[c + w] + gray[c - 1] + gray[c + 1] - 4 * gray[c];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}
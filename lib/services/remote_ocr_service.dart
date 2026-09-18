import 'dart:io';
import 'package:dio/dio.dart';

import '../config/api_config.dart';

class RemoteOcrService {
  RemoteOcrService._();

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      // ✅ OCR 上傳圖片，給久一點（避免 15 秒就死）
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  /// mode: "electronic" / "traditional"
  static Future<String> visionOcr(File imageFile, {required String mode}) async {
    final filename = imageFile.path.split(Platform.pathSeparator).last;

    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(imageFile.path, filename: filename),
      'mode': mode,
    });

    final resp = await _dio.post(
      '/vision/ocr',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );

    final data = resp.data;
    if (data is Map && data['status'] == 'success') {
      return (data['text'] ?? '').toString();
    }
    throw Exception((data is Map ? data['message'] : null) ?? 'vision ocr failed');
  }
}
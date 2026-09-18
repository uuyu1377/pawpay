import 'package:user_interface/config/backend_config.dart';

class ApiConfig {
  /// 與 BackendConfig.serverIp 共用同一個 IP，只需在 backend_config.dart 修改一次
  static const String pcLanIp = "120.126.16.227";

  /// ✅ 如果你用 Android Emulator 才改成 true
  static const bool isEmulator = false;

  static String get baseUrl =>
      isEmulator ? 'http://10.0.2.2:5000' : 'http://$pcLanIp:5000';

  static String get health => '$baseUrl/health';
  static String get visionOcr => '$baseUrl/vision/ocr';
  static String get classify => '$baseUrl/classify';

  // 🚀 新增這行：把 CSV 匯入的 API 加進來
  static String get importCsv => '$baseUrl/api/import-csv';

  // 登入取得 Token 的 API
  static String get login => '$baseUrl/api/login';
// 刪除所有資料的 API
  static String get deleteData => '$baseUrl/api/privacy/delete-data';
}

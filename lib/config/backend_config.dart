class BackendConfig {
  /// ⚠️ 改成你「電腦」的區網 IP
  /// - 真機要連到你電腦：把這裡改成同一個 Wi‑Fi 內你的電腦 IP
  /// - Android 模擬器不看這個，會用 10.0.2.2
  static const String serverIp = "120.126.16.227";

  /// 你朋友原本的 OCR/AI 後端（Flask/FastAPI）埠號
  static const int ocrPort = 5000;

  /// ✅ 新增：MySQL API（FastAPI）埠號
  static const int mysqlApiPort = 8000;

  /// Android 模擬器要連你電腦要用 10.0.2.2
  static const bool androidEmulator = false;

  static String get baseUrl => "http://$serverIp:$ocrPort";

  static String get mysqlApiBaseUrl => "http://$serverIp:$mysqlApiPort";
}

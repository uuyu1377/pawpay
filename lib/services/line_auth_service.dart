import 'dart:convert';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/backend_config.dart';

/// ★★★ 新增：LINE 登入服務 ★★★
/// 用 flutter_line_sdk 登入 LINE 拿到 access token，
/// 送到後端 /api/auth/line，換回內部 9 位數 user_id + JWT。
/// 存的 key 跟 Firebase 一樣 (user_id / jwt_token)，其他功能不用改就能沿用。
class LineAuthService {
  /// 用 LINE 登入 → 回傳 access token (失敗會 throw)
  static Future<String> signInWithLine() async {
    final result = await LineSDK.instance.login(scopes: ['profile']);
    return result.accessToken.value;
  }

  /// 把 LINE access token 送到後端 → 換回內部 user_id + JWT，並存進手機
  static Future<void> exchangeTokenWithBackend(String accessToken) async {
    final url = Uri.parse('${BackendConfig.baseUrl}/api/auth/line');
    final response = await http
        .post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"access_token": accessToken}),
    )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('後端登入失敗 (${response.statusCode})：${response.body}');
    }

    final resJson = jsonDecode(response.body);
    final String? token = resJson['token'];
    final String? userId = resJson['user_id']?.toString();
    if (token == null || userId == null) {
      throw Exception('後端回傳格式不正確');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId); // ★ 內部數字 id
    await prefs.setString('jwt_token', token); // ★ 跟原本相同的 key，其他功能直接沿用
  }

  /// 登出
  static Future<void> signOut() async {
    try {
      await LineSDK.instance.logout();
    } catch (_) {}
  }
}
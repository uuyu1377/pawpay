import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ★★★ 新增：用來讀取儲存在手機裡的 JWT Token ★★★
import 'dart:convert'; // ★ 合併自朋友版(C)：幣別覆蓋表序列化
import 'package:shared_preferences/shared_preferences.dart';
import 'package:user_interface/models/transaction_model.dart' as model;
import 'package:user_interface/config/backend_config.dart';
import 'package:user_interface/services/currency_service.dart';

/// 重要觀念：Flutter App **不要直接連 MySQL**（資安/網路/權限問題）。
///
/// 正確做法：App -> 後端 API -> MySQL。
///
/// 這個 Service 專門負責「呼叫 MySQL API」。
class MysqlApiService {
  Future<String> _loadDefaultCurrencyCode() async {
    try {
      return await CurrencyService.loadDefaultCode();
    } catch (_) {
      return CurrencyService.defaultCode;
    }
  }
  MysqlApiService._();
  static final MysqlApiService instance = MysqlApiService._();

  /// API Base URL
  /// - Android 模擬器：用 10.0.2.2 才能連到你電腦
  /// - Windows/macOS/Linux 桌面：localhost
  /// - 真機：改成你電腦的 LAN IP，例如 http://192.168.0.10:8000
  static String get baseUrl {
    if (kIsWeb) return "http://localhost:${BackendConfig.mysqlApiPort}";

    if (Platform.isAndroid) {
      if (BackendConfig.androidEmulator) {
        return "http://10.0.2.2:${BackendConfig.mysqlApiPort}";
      }
      return BackendConfig.mysqlApiBaseUrl;
    }

    return "http://localhost:${BackendConfig.mysqlApiPort}";
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  // =========================
  // Bootstrap / User
  // =========================

  Future<void> ensureSeeded({
    int userId = 1,
    required String target,
  }) async {
    await _dio.post(
      '${baseUrl}/bootstrap/seed',
      data: {
        'user_id': userId,
        'target': target,
      },
    );
  }

  Future<void> setUserIdentity({
    int userId = 1,
    required String target,
  }) async {
    await _dio.post(
      '${baseUrl}/users/identity',
      data: {
        'user_id': userId,
        'target': target,
      },
    );
  }

  Future<void> updateUserInfo({
    int userId = 1,
    required String nickname,
    String provider = 'local',
  }) async {
    await _dio.post(
      '${baseUrl}/users/info',
      data: {
        'user_id': userId,
        'nickname': nickname,
        'provider': provider,
      },
    );
  }

  // =========================
  // Categories
  // =========================

  Future<List<Map<String, dynamic>>> fetchPickerCategories({
    int userId = 1,
    required String direction,
    required String target,
  }) async {
    final res = await _dio.get(
      '${baseUrl}/categories/picker',
      queryParameters: {
        'user_id': userId,
        'direction': direction,
        'target': target,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchQuickCategories({
    int userId = 1,
    required String direction,
    required String target,
  }) async {
    final res = await _dio.get(
      '${baseUrl}/categories/quick',
      queryParameters: {
        'user_id': userId,
        'direction': direction,
        'target': target,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> fetchCategoryByName({
    int userId = 1,
    required String name,
    required String direction,
    required String target,
  }) async {
    final res = await _dio.get(
      '${baseUrl}/categories/by-name',
      queryParameters: {
        'user_id': userId,
        'name': name,
        'direction': direction,
        'target': target,
      },
    );
    final data = res.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<int> createCustomCategory({
    int userId = 1,
    required String name,
    required String direction,
    required String target,
    int? parentId,
    String? iconKey,
    bool isUserCreated = true,
  }) async {
    final res = await _dio.post(
      '${baseUrl}/categories/custom',
      data: {
        'user_id': userId,
        'name': name,
        'direction': direction,
        'target': target,
        'parent_id': parentId,
        'icon_key': iconKey,
        'is_user_created': isUserCreated,
      },
    );
    final data = res.data;
    if (data is Map && data['id'] != null) {
      return int.tryParse(data['id'].toString()) ?? 0;
    }
    return 0;
  }

  Future<bool> unlockCategory({
    int userId = 1,
    required String name,
    required String direction,
    required String target,
    required int customUnlockThreshold,
    bool isUserCreated = false,
  }) async {
    final res = await _dio.post(
      '${baseUrl}/categories/unlock',
      data: {
        'user_id': userId,
        'name': name,
        'direction': direction,
        'target': target,
        'custom_unlock_threshold': customUnlockThreshold,
        'is_user_created': isUserCreated,
      },
    );
    final data = res.data;
    if (data is Map) {
      return (data['unlocked'] == true) || (data['unlocked']?.toString() == '1');
    }
    return false;
  }

  // ★ 合併自朋友版(C)：交易幣別本地覆蓋表（後端不保證保存原始幣別時的補強）
  Future<Map<String, String>> _loadCurrencyOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('transaction_currency_overrides');
    if (raw == null || raw.isEmpty) return <String, String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((key, value) {
        return MapEntry(key.toString(), value.toString());
      });
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveCurrencyOverride(String transactionId, String currency) async {
    final normalized = CurrencyService.tryNormalizeCode(currency) ?? 'TWD';
    if (transactionId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final overrides = await _loadCurrencyOverrides();
    overrides[transactionId.toString()] = normalized;
    await prefs.setString('transaction_currency_overrides', jsonEncode(overrides));
  }

  Future<void> _removeCurrencyOverride(String transactionId) async {
    final prefs = await SharedPreferences.getInstance();
    final overrides = await _loadCurrencyOverrides();
    overrides.remove(transactionId.toString());
    await prefs.setString('transaction_currency_overrides', jsonEncode(overrides));
  }

  // =========================
  // Transactions
  // =========================

  Future<int> createManualTransaction({
    int userId = 1,
    required String target,
    required model.Transaction tx,
  }) async {
    final direction = tx.type == model.TransactionType.income ? 'income' : 'expense';
    final res = await _dio.post(
      '${baseUrl}/transactions/manual',
      data: {
        'user_id': userId,
        'target': target,
        'direction': direction,
        'category': tx.category,
        'amount': tx.originalAmount, // ★ 合併自朋友版(C)：送原始金額，載入時再換算 TWD
        'currency': tx.currency, // ★ 合併自朋友版(C)：送原始幣別
        'note': tx.note,
        'occurred_at': tx.date.toIso8601String(),
      },
    );
    final data = res.data;
    if (data is Map && data['id'] != null) {
      final id = int.tryParse(data['id'].toString()) ?? 0;
      if (id > 0) {
        await _saveCurrencyOverride(id.toString(), tx.currency); // ★ 合併自朋友版(C)
      }
      return id;
    }
    return 0;
  }

  Future<int> createAiTransaction({
    int userId = 1,
    required String target,
    required double amount,
    String currency = 'TWD',
    required String direction,
    required String selectedMainCategory,
    required String selectedSubCategory,
    String? suggestedSubCategory,
    double? aiConfidence,
    String entryMethod = 'scan',
    String source = 'backend',
    String? merchantName,
    String? note,
    DateTime? occurredAt,
    String captureMethod = 'scan',
    String? rawInput,
    String? parsedJson,
    String? invoiceNumber,
    String? aiModel,
    String? aiShortComment,
    String? aiItemsSummary,
    List<String>? tags,
  }) async {
    final res = await _dio.post(
      '${baseUrl}/transactions/ai',
      data: {
        'user_id': userId,
        'target': target,
        'direction': direction,
        'amount': amount,
        'currency': currency, // ★ 合併自朋友版(C)：送原始幣別
        'selected_main_category': selectedMainCategory,
        'selected_sub_category': selectedSubCategory,
        'suggested_sub_category': suggestedSubCategory,
        'ai_confidence': aiConfidence,
        'entry_method': entryMethod,
        'source': source,
        'merchant_name': merchantName,
        'note': note,
        'occurred_at': (occurredAt ?? DateTime.now()).toIso8601String(),
        'capture_method': captureMethod,
        'raw_input': rawInput,
        'parsed_json': parsedJson,
        'invoice_number': invoiceNumber,
        'ai_model': aiModel,
        'ai_short_comment': aiShortComment,
        'ai_items_summary': aiItemsSummary,
        'tags': tags,
      },
    );
    final data = res.data;
    if (data is Map && data['id'] != null) {
      final id = int.tryParse(data['id'].toString()) ?? 0;
      if (id > 0) {
        await _saveCurrencyOverride(id.toString(), currency); // ★ 合併自朋友版(C)
      }
      return id;
    }
    return 0;
  }

  // Backwards compatible names (older patches)
  Future<void> uploadManualTransaction({
    int userId = 1,
    required String target,
    required model.Transaction tx,
  }) async {
    await createManualTransaction(userId: userId, target: target, tx: tx);
  }

  Future<void> uploadAiTransaction({
    int userId = 1,
    required String target,
    required double amount,
    String currency = 'TWD',
    required String direction,
    required String selectedMainCategory,
    required String selectedSubCategory,
    String? suggestedSubCategory,
    double? aiConfidence,
    String entryMethod = 'scan',
    String source = 'backend',
    String? merchantName,
    String? note,
    DateTime? occurredAt,
    String captureMethod = 'scan',
    String? rawInput,
    String? parsedJson,
    String? invoiceNumber,
    String? aiModel,
    String? aiShortComment,
    String? aiItemsSummary,
    List<String>? tags,
  }) async {
    await createAiTransaction(
      userId: userId,
      target: target,
      amount: amount,
      currency: currency,
      direction: direction,
      selectedMainCategory: selectedMainCategory,
      selectedSubCategory: selectedSubCategory,
      suggestedSubCategory: suggestedSubCategory,
      aiConfidence: aiConfidence,
      entryMethod: entryMethod,
      source: source,
      merchantName: merchantName,
      note: note,
      occurredAt: occurredAt,
      captureMethod: captureMethod,
      rawInput: rawInput,
      parsedJson: parsedJson,
      invoiceNumber: invoiceNumber,
      aiModel: aiModel,
      aiShortComment: aiShortComment,
      aiItemsSummary: aiItemsSummary,
      tags: tags,
    );
  }

  Future<List<model.Transaction>> fetchTransactions({int userId = 1, int limit = 300}) async {
    final res = await _dio.get(
      '${baseUrl}/transactions',
      queryParameters: {'user_id': userId, 'limit': limit},
    );
    final data = res.data;
    if (data is! List) return [];

    // ★ 合併自朋友版(C)：載入時以（覆蓋優先的）原始幣別查即時匯率換算成 TWD 統計基準，並保留原始金額/幣別
    final overrides = await _loadCurrencyOverrides();

    // 統計基準一律換算成 TWD；每筆明細仍保留原始幣別與原始金額。
    // 首頁再把 TWD 基準金額顯示成使用者的「預設幣別」，避免旅行幣別干擾舊資料。
    final rateCache = <String, double>{};

    Future<double> rateToTwd(String fromCode) async {
      if (fromCode == 'TWD') return 1.0;
      if (rateCache.containsKey(fromCode)) return rateCache[fromCode]!;
      final rate = await CurrencyService.instance.getRate(fromCode, 'TWD');
      rateCache[fromCode] = rate;
      return rate;
    }

    final result = <model.Transaction>[];
    for (final rawRow in data) {
      if (rawRow is! Map) continue;
      final row = Map<String, dynamic>.from(rawRow);
      final id = row['id'].toString();
      final amountValue = row['amount'];
      final originalAmount = amountValue is num
          ? amountValue.toDouble()
          : (double.tryParse(amountValue?.toString() ?? '') ?? 0.0);

      final backendCurrency = CurrencyService.tryNormalizeCode(row['currency']?.toString()) ?? 'TWD';
      final rawCurrency = CurrencyService.tryNormalizeCode(overrides[id]) ?? backendCurrency;
      final rate = await rateToTwd(rawCurrency);
      final normalizedAmount = originalAmount * rate;

      final dateStr = (row['date'] ?? '').toString();
      DateTime dt;
      try {
        dt = DateTime.parse(dateStr);
      } catch (_) {
        dt = DateTime.now();
      }
      final note = (row['note'] ?? '').toString();
      final typeStr = (row['type'] ?? 'expense').toString();
      final txType = typeStr == 'income' ? model.TransactionType.income : model.TransactionType.expense;
      final category = (row['category'] ?? '未知').toString();

      result.add(model.Transaction(
        id: id,
        note: note,
        amount: normalizedAmount,
        originalAmount: originalAmount,
        currency: rawCurrency,
        date: dt,
        category: category,
        categoryIcon: _guessIconByName(category),
        type: txType,
      ));
    }
    return result;
  }

  Future<void> deleteTransaction({required int id, int userId = 1}) async {
    await _dio.delete(
      '${baseUrl}/transactions/$id',
      queryParameters: {'user_id': userId},
    );
    await _removeCurrencyOverride(id.toString()); // ★ 合併自朋友版(C)
  }

  Future<void> updateTransaction({
    int userId = 1,
    required String target,
    required model.Transaction tx,
  }) async {
    final txId = int.tryParse(tx.id) ?? 0;
    if (txId <= 0) return;

    final direction = tx.type == model.TransactionType.income ? 'income' : 'expense';

    await _dio.put(
      '${baseUrl}/transactions/$txId',
      data: {
        'user_id': userId,
        'target': target,
        'direction': direction,
        'category': tx.category,
        'amount': tx.originalAmount, // ★ 合併自朋友版(C)：送原始金額
        'currency': tx.currency, // ★ 合併自朋友版(C)：送原始幣別
        'note': tx.note,
        'occurred_at': tx.date.toIso8601String(),
      },
    );
    await _saveCurrencyOverride(txId.toString(), tx.currency); // ★ 合併自朋友版(C)
  }

  Future<Map<String, dynamic>> fetchDailySummary({
    int userId = 1,
    required DateTime date,
  }) async {
    final d = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res = await _dio.get(
      '${baseUrl}/summary/daily',
      queryParameters: {'user_id': userId, 'date': d},
    );
    if (res.data is Map) return Map<String, dynamic>.from(res.data as Map);
    return {'count': 0, 'total': 0.0};
  }

  Future<bool> hasTransactionsOnDate({
    int userId = 1,
    required DateTime date,
  }) async {
    final d = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res = await _dio.get(
      '${baseUrl}/transactions/exists',
      queryParameters: {'user_id': userId, 'date': d},
    );
    final data = res.data;
    if (data is Map) return data['exists'] == true;
    return false;
  }

  static IconData _guessIconByName(String name) {
    if (name.contains("食") || name.contains("餐") || name.contains("飲") || name.contains("零")) return Icons.fastfood_rounded;
    if (name.contains("車") || name.contains("油") || name.contains("交通")) return Icons.directions_bus_rounded;
    if (name.contains("衣") || name.contains("服") || name.contains("飾")) return Icons.checkroom_rounded;
    if (name.contains("樂") || name.contains("遊")) return Icons.sports_esports_rounded;
    if (name.contains("醫") || name.contains("藥")) return Icons.medical_services_rounded;
    if (name.contains("住") || name.contains("房") || name.contains("電") || name.contains("居")) return Icons.home_rounded;
    if (name.contains("學") || name.contains("書") || name.contains("課")) return Icons.school_rounded;
    return Icons.receipt_long_rounded;
  }

  // ==========================================
  // ★★★ 新增：徹底刪除資料 API (GDPR / 隱私權防護) ★★★
  // ==========================================
  Future<void> deleteAllUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    // 注意：因為這個 API 是寫在 Flask (AI Server) 上，所以要用 BackendConfig.baseUrl (預設 Port 5000)
    final url = '${BackendConfig.baseUrl}/api/privacy/delete-data';

    try {
      await _dio.post(
        url,
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ 刪除資料 API 呼叫失敗: $e');
      rethrow;
    }
  }
}
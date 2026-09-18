import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recurring_api_service.dart';

class RecurringIncomeReview {
  const RecurringIncomeReview({
    required this.ruleId, required this.scheduledDate, required this.transactionId,
    required this.status, required this.version, required this.categoryName,
    required this.amount, required this.currency, required this.note,
  });
  final int ruleId;
  final String scheduledDate;
  final String transactionId;
  final String status;
  final int version;
  final String categoryName;
  final double amount;
  final String currency;
  final String note;
  String get key => '$ruleId/$scheduledDate';
  bool get isConfirmed => status == 'confirmed';
  bool get isCancelled => status == 'cancelled';

  factory RecurringIncomeReview.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString();
    final rule = int.tryParse(json['rule_id']?.toString() ?? '');
    final version = int.tryParse(json['version']?.toString() ?? '');
    final tx = json['transaction_id']?.toString() ?? '';
    final scheduled = json['scheduled_date']?.toString() ?? '';
    final date = DateTime.tryParse(scheduled);
    final amount = double.tryParse(json['amount']?.toString() ?? '');
    if (!{'pending', 'confirmed', 'cancelled'}.contains(status) ||
        rule == null || rule <= 0 || version == null || version < 0 ||
        !RegExp(r'^[1-9]\d{0,18}$').hasMatch(tx) || date == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(scheduled) ||
        date.toIso8601String().substring(0, 10) != scheduled ||
        amount == null || !amount.isFinite || amount < 0) {
      throw const FormatException('固定收入資料格式無效');
    }
    return RecurringIncomeReview(
      ruleId: rule, scheduledDate: scheduled, transactionId: tx,
      status: status!, version: version,
      categoryName: json['category_name']?.toString() ?? '固定收入',
      amount: amount,
      currency: json['currency']?.toString() ?? 'TWD',
      note: json['note']?.toString() ?? '',
    );
  }
}

enum IncomeReviewFailure { unavailable, login, network, conflict, server, invalidData }

class RecurringIncomeReviewException implements Exception {
  const RecurringIncomeReviewException(this.message, {
    this.kind = IncomeReviewFailure.server, this.statusCode, this.code = 'review_error'});
  final String message, code;
  final IncomeReviewFailure kind;
  final int? statusCode;
  String get help => switch (kind) {
    IncomeReviewFailure.unavailable => '目前連線的服務尚未提供固定收入確認。請專題管理者安裝更新包內的 backend_update，並重新啟動服務，再按重試。原有固定收支規則不會因此被修改。',
    IncomeReviewFailure.login => '登入憑證缺少、過期或與目前帳號不符。請從設定登出後，以原本的登入方式重新登入。',
    IncomeReviewFailure.network => '請確認手機能連上專題伺服器；若伺服器在區域網路內，手機也需要連上可存取它的網路。',
    IncomeReviewFailure.conflict => '這筆收入可能已在其他裝置更新，或原始交易已被修改。請重新載入最新狀態後再操作。',
    IncomeReviewFailure.invalidData => '服務回傳的資料格式不符合此版本，請將下方診斷資訊交給專題管理者。',
    IncomeReviewFailure.server => '服務目前無法完成要求，請稍後重試。若持續發生，請專題管理者查看後端紀錄與資料庫連線。',
  };
  String get diagnostic => '$code${statusCode == null ? '' : ' · HTTP $statusCode'}';
  @override
  String toString() => message;

  static RecurringIncomeReviewException from(Object error) {
    if (error is RecurringIncomeReviewException) return error;
    if (error is FormatException || error is TypeError) {
      return const RecurringIncomeReviewException('固定收入資料格式需要更新',
        kind: IncomeReviewFailure.invalidData, code: 'review_invalid_data');
    }
    return const RecurringIncomeReviewException('固定收入確認未完成，請重試', code: 'review_unexpected');
  }
}

class IncomeReviewIdentity {
  const IncomeReviewIdentity(this.userId, this.token);
  final String userId, token;
}

class RecurringIncomeReviewService {
  RecurringIncomeReviewService._() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  )), _identityLoader = _readIdentity, _baseUrlOverride = null;

  @visibleForTesting
  RecurringIncomeReviewService.forTesting({required Dio dio,
    required Future<IncomeReviewIdentity> Function() identity,
    String baseUrl = 'https://example.invalid'}) : _dio = dio,
    _identityLoader = identity, _baseUrlOverride = baseUrl;

  static final instance = RecurringIncomeReviewService._();
  final Dio _dio;
  final Future<IncomeReviewIdentity> Function() _identityLoader;
  final String? _baseUrlOverride;
  String get _baseUrl => _baseUrlOverride ?? RecurringApiService.baseUrl;

  static Future<IncomeReviewIdentity> _readIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token')?.trim() ?? '';
    final user = prefs.getString('user_id')?.trim() ?? '';
    if (token.isEmpty || user.isEmpty) {
      throw const RecurringIncomeReviewException('請重新登入以讀取固定收入確認',
        kind: IncomeReviewFailure.login, code: 'review_login_required');
    }
    return IncomeReviewIdentity(user, token);
  }

  Future<void> _checkAccount(IncomeReviewIdentity identity) async {
    final current = await _identityLoader();
    if (current.userId != identity.userId || current.token != identity.token) {
      throw const RecurringIncomeReviewException('登入狀態已變更，請重新載入',
        kind: IncomeReviewFailure.login, code: 'review_account_changed');
    }
  }

  Future<Map<String, dynamic>> _request(String path, IncomeReviewIdentity identity,
      {Map<String, dynamic>? data}) async {
    await _checkAccount(identity);
    try {
      final options = Options(headers: {'Authorization': 'Bearer ${identity.token}'},
        responseType: ResponseType.json);
      final response = data == null
        ? await _dio.get('$_baseUrl$path', options: options)
        : await _dio.post('$_baseUrl$path', data: data, options: options);
      await _checkAccount(identity);
      if (response.data is! Map || response.data['status'] != 'success') {
        throw const RecurringIncomeReviewException('固定收入服務回傳的內容無法辨識',
          kind: IncomeReviewFailure.invalidData, code: 'review_invalid_response');
      }
      return Map<String, dynamic>.from(response.data as Map);
    } on DioException catch (error) {
      final failure = classify(error);
      // Never log the token, Authorization headers, or financial response body.
      debugPrint('[income-review] ${failure.diagnostic} $_baseUrl$path');
      throw failure;
    }
  }

  @visibleForTesting
  static RecurringIncomeReviewException classify(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    // JSON 404 from the installed endpoint means a missing occurrence. An
    // HTML/router 404 or a 405 means that the endpoint was not installed.
    if ((status == 404 && !(body is Map && body['status'] == 'error')) || status == 405) {
      return RecurringIncomeReviewException('固定收入確認服務尚未啟用',
        kind: IncomeReviewFailure.unavailable, statusCode: status, code: 'review_service_missing');
    }
    if (status == 401 || status == 403) {
      return RecurringIncomeReviewException('請重新登入以讀取固定收入確認',
        kind: IncomeReviewFailure.login, statusCode: status, code: 'review_login_required');
    }
    if (status == 409 || status == 404) {
      return RecurringIncomeReviewException('收入狀態已變更，請重新載入',
        kind: IncomeReviewFailure.conflict, statusCode: status, code: 'review_conflict');
    }
    if (status == 400 || status == 422) {
      return RecurringIncomeReviewException('固定收入資料格式需要更新',
        kind: IncomeReviewFailure.invalidData, statusCode: status, code: 'review_invalid_request');
    }
    if (status == null && error.type != DioExceptionType.badResponse) {
      return const RecurringIncomeReviewException('無法連上固定收入服務，請檢查網路後重試',
        kind: IncomeReviewFailure.network, code: 'review_connection_failed');
    }
    return RecurringIncomeReviewException('固定收入服務目前無法完成要求',
      kind: IncomeReviewFailure.server, statusCode: status,
      code: body is Map && body['code'] == 'review_database_unavailable'
        ? 'review_database_unavailable' : 'review_server_error');
  }

  List<RecurringIncomeReview> _parseRows(Map<String, dynamic> body) {
    try {
      final rows = body['reviews'];
      if (rows is! List) throw const FormatException('缺少固定收入資料');
      return rows.map((row) => RecurringIncomeReview.fromJson(
        Map<String, dynamic>.from(row as Map))).toList();
    } catch (error) { throw RecurringIncomeReviewException.from(error); }
  }

  Future<Map<String, RecurringIncomeReview>> fetchIndex(List<String> transactionIds) async {
    final ids = transactionIds.where((id) => RegExp(r'^[1-9]\d{0,18}$').hasMatch(id)).toSet().toList();
    if (ids.isEmpty) return {};
    final identity = await _identityLoader();
    final result = <String, RecurringIncomeReview>{};
    // The backend's request limit is 500. Batching prevents an entire ledger
    // from failing when a caller supplies more than 500 IDs.
    for (var offset = 0; offset < ids.length; offset += 200) {
      final batch = ids.sublist(offset, math.min(offset + 200, ids.length));
      final body = await _request('/api/recurring-income/reviews', identity,
        data: {'transaction_ids': batch});
      for (final row in _parseRows(body)) {
        if (batch.contains(row.transactionId)) result[row.transactionId] = row;
      }
    }
    await _checkAccount(identity);
    return result;
  }

  Future<List<RecurringIncomeReview>> fetchHistory(DateTime month) async {
    final identity = await _identityLoader();
    final key = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
    return _parseRows(await _request('/api/recurring-income/history?month=$key', identity));
  }

  Future<RecurringIncomeReview> apply(RecurringIncomeReview row, String action) async {
    if (!{'confirm', 'cancel', 'restore'}.contains(action)) throw ArgumentError.value(action, 'action');
    final identity = await _identityLoader();
    final body = await _request('/api/recurring-income/${row.key}/review', identity,
      data: {'action': action, 'expected_version': row.version});
    try {
      return RecurringIncomeReview.fromJson(Map<String, dynamic>.from(body['review'] as Map));
    } catch (error) { throw RecurringIncomeReviewException.from(error); }
  }
}

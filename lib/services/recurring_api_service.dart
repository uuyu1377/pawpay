import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_config.dart';

class RecurringTransactionRule {
  final int? id;
  final String direction;
  final String categoryName;
  final double amount;
  final String currency;
  final String note;
  final String cadence;
  final DateTime startDate;
  final DateTime nextRunDate;
  final DateTime? endDate;
  final bool isActive;

  const RecurringTransactionRule({
    this.id,
    required this.direction,
    required this.categoryName,
    required this.amount,
    required this.currency,
    required this.note,
    required this.cadence,
    required this.startDate,
    required this.nextRunDate,
    this.endDate,
    required this.isActive,
  });

  factory RecurringTransactionRule.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) =>
        DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    return RecurringTransactionRule(
      id: int.tryParse(json['id']?.toString() ?? ''),
      direction: json['direction']?.toString() == 'income' ? 'income' : 'expense',
      categoryName: json['category_name']?.toString() ?? '其他',
      amount: (json['amount'] as num?)?.toDouble() ??
          double.tryParse(json['amount']?.toString() ?? '') ??
          0,
      currency: json['currency']?.toString() ?? 'TWD',
      note: json['note']?.toString() ?? '',
      cadence: json['cadence']?.toString() ?? 'monthly',
      startDate: parseDate(json['start_date']),
      nextRunDate: parseDate(json['next_run_date']),
      endDate: DateTime.tryParse(json['end_date']?.toString() ?? ''),
      isActive: json['is_active'] == true || json['is_active']?.toString() == '1',
    );
  }

  Map<String, dynamic> toJson(String userId) => {
        'user_id': userId,
        'direction': direction,
        'category_name': categoryName,
        'amount': amount,
        'currency': currency,
        'note': note,
        'cadence': cadence,
        'start_date': _dateKey(startDate),
        'next_run_date': _dateKey(nextRunDate),
        'end_date': endDate == null ? null : _dateKey(endDate!),
        'is_active': isActive,
      };

  RecurringTransactionRule copyWith({bool? isActive}) => RecurringTransactionRule(
        id: id,
        direction: direction,
        categoryName: categoryName,
        amount: amount,
        currency: currency,
        note: note,
        cadence: cadence,
        startDate: startDate,
        nextRunDate: nextRunDate,
        endDate: endDate,
        isActive: isActive ?? this.isActive,
      );

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class RecurringApiService {
  RecurringApiService._();
  static final RecurringApiService instance = RecurringApiService._();

  static String get baseUrl {
    if (kIsWeb) return 'http://localhost:${BackendConfig.ocrPort}';
    if (Platform.isAndroid && BackendConfig.androidEmulator) {
      return 'http://10.0.2.2:${BackendConfig.ocrPort}';
    }
    if (Platform.isAndroid) return BackendConfig.baseUrl;
    return 'http://localhost:${BackendConfig.ocrPort}';
  }

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 12),
    headers: {'Content-Type': 'application/json'},
  ));

  Future<({String userId, Options options})> _identity() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id')?.trim();
    final token = prefs.getString('jwt_token')?.trim();
    return (
      userId: userId == null || userId.isEmpty ? '1' : userId,
      options: Options(headers: {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      }),
    );
  }

  Future<List<RecurringTransactionRule>> fetchRules() async {
    final identity = await _identity();
    final response = await _dio.get(
      '$baseUrl/api/recurring-transactions',
      queryParameters: {'user_id': identity.userId},
      options: identity.options,
    );
    final body = response.data;
    final rows = body is Map ? body['rules'] : null;
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map((row) => RecurringTransactionRule.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> saveRule(RecurringTransactionRule rule) async {
    final identity = await _identity();
    if (rule.id == null) {
      await _dio.post(
        '$baseUrl/api/recurring-transactions',
        data: rule.toJson(identity.userId),
        options: identity.options,
      );
    } else {
      await _dio.put(
        '$baseUrl/api/recurring-transactions/${rule.id}',
        data: rule.toJson(identity.userId),
        options: identity.options,
      );
    }
  }

  Future<void> deleteRule(int id) async {
    final identity = await _identity();
    await _dio.delete(
      '$baseUrl/api/recurring-transactions/$id',
      queryParameters: {'user_id': identity.userId},
      options: identity.options,
    );
  }

  Future<int> processDue() async {
    final identity = await _identity();
    final response = await _dio.post(
      '$baseUrl/api/recurring-transactions/process-due',
      data: {'user_id': identity.userId},
      options: identity.options,
    );
    final body = response.data;
    return int.tryParse(body is Map ? body['created_count']?.toString() ?? '0' : '0') ?? 0;
  }
}

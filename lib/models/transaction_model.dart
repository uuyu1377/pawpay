import 'package:flutter/material.dart';

// 定義交易類型 (支出或收入)
enum TransactionType {
  expense,
  income,
}

// 定義一筆交易的資料結構
class Transaction {
  final String id;
  final String note;          // 備註 (例如：迷克夏)
  final double amount;        // 金額（統計基準，統一換算成 TWD）
  final double originalAmount; // ★ 合併自朋友版：原始輸入/掃描金額（原始幣別）
  final DateTime date;        // 時間
  final String category;      // 分類 (例如：飲食)
  final IconData categoryIcon; // 分類圖示 (暫時用)
  final TransactionType type; // 類型
  final String currency; // 幣別，例如 TWD、USD
  final bool isForeignCard; // 是否為國外刷卡消費
  final double foreignFeeRate; // 國外交易手續費率，例如 0.015
  final double foreignFeeAmountTwd; // 預估手續費（TWD）
  final double exchangeRateToTwd; // 1 單位原幣約等於多少 TWD
  final String exchangeRateSource;
  final String exchangeRateType;
  final String? exchangeRateDate;

  Transaction({
    required this.id,
    required this.note,
    required this.amount,
    double? originalAmount, // ★ 合併自朋友版：不傳則等於 amount
    required this.date,
    required this.category,
    required this.categoryIcon,
    required this.type,
    this.currency = 'TWD',
    this.isForeignCard = false,
    this.foreignFeeRate = 0,
    this.foreignFeeAmountTwd = 0,
    this.exchangeRateToTwd = 1,
    this.exchangeRateSource = '',
    this.exchangeRateType = '',
    this.exchangeRateDate,
  }) : originalAmount = originalAmount ?? amount; // ★ 合併自朋友版

  // ★ 合併自朋友版：複製並覆寫部分欄位
  Transaction copyWith({
    String? id,
    String? note,
    double? amount,
    double? originalAmount,
    String? currency,
    DateTime? date,
    String? category,
    IconData? categoryIcon,
    TransactionType? type,
    bool? isForeignCard,
    double? foreignFeeRate,
    double? foreignFeeAmountTwd,
    double? exchangeRateToTwd,
    String? exchangeRateSource,
    String? exchangeRateType,
    String? exchangeRateDate,
  }) {
    return Transaction(
      id: id ?? this.id,
      note: note ?? this.note,
      amount: amount ?? this.amount,
      originalAmount: originalAmount ?? this.originalAmount,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      category: category ?? this.category,
      categoryIcon: categoryIcon ?? this.categoryIcon,
      type: type ?? this.type,
      isForeignCard: isForeignCard ?? this.isForeignCard,
      foreignFeeRate: foreignFeeRate ?? this.foreignFeeRate,
      foreignFeeAmountTwd: foreignFeeAmountTwd ?? this.foreignFeeAmountTwd,
      exchangeRateToTwd: exchangeRateToTwd ?? this.exchangeRateToTwd,
      exchangeRateSource: exchangeRateSource ?? this.exchangeRateSource,
      exchangeRateType: exchangeRateType ?? this.exchangeRateType,
      exchangeRateDate: exchangeRateDate ?? this.exchangeRateDate,
    );
  }
}

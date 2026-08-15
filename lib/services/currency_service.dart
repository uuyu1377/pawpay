import 'dart:convert'; // ★ 合併自朋友版：解析匯率 API 回傳

import 'package:http/http.dart' as http; // ★ 合併自朋友版：即時匯率
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ★★★ 以下整段 CurrencyDisplaySettings 為合併自朋友版（旅遊匯率顯示設定） ★★★
class CurrencyDisplaySettings {
  final String code;
  final String label;
  final String symbol;
  final double rateFromTwd;
  final String? rateDate;
  final bool isTravelMode;
  final String defaultCode;

  const CurrencyDisplaySettings({
    required this.code,
    required this.label,
    required this.symbol,
    required this.rateFromTwd,
    required this.rateDate,
    required this.isTravelMode,
    required this.defaultCode,
  });

  factory CurrencyDisplaySettings.twd() {
    return const CurrencyDisplaySettings(
      code: 'TWD',
      label: 'TWD / 新台幣',
      symbol: 'NT\$',
      rateFromTwd: 1.0,
      rateDate: null,
      isTravelMode: false,
      defaultCode: 'TWD',
    );
  }

  double convertFromTwd(num amount) => amount.toDouble() * rateFromTwd;

  String format(num twdAmount, {bool showCode = false}) {
    final converted = convertFromTwd(twdAmount);
    final decimals = CurrencyService.decimalsFor(code);
    final nf = NumberFormat.decimalPattern();
    String number;
    if (decimals == 0) {
      number = nf.format(converted.round());
    } else {
      final decimalZeros = List.filled(decimals, '0').join();
      number = NumberFormat('#,##0.$decimalZeros').format(converted);
    }
    return showCode ? '$symbol$number $code' : '$symbol$number';
  }
}

class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._(); // ★ 合併自朋友版：單例

  static const String defaultCode = 'TWD';

  static const List<String> currencyLabels = [
    'TWD / 新台幣',
    'USD / 美元',
    'JPY / 日圓',
    'KRW / 韓圓',
    'CNY / 人民幣',
  ];

  static const Map<String, String> _symbols = {
    'TWD': 'NT\$',
    'USD': 'US\$',
    'JPY': '¥',
    'KRW': '₩',
    'CNY': '¥',
  };

  static String codeFromSetting(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return defaultCode;
    final code = text.contains('/') ? text.split('/').first.trim() : text;
    return _symbols.containsKey(code) ? code : defaultCode;
  }

  static String labelForCode(String code) {
    final normalized = codeFromSetting(code);
    return currencyLabels.firstWhere(
          (label) => label.startsWith(normalized),
      orElse: () => currencyLabels.first,
    );
  }

  static String symbolForCode(String? code) {
    return _symbols[codeFromSetting(code)] ?? _symbols[defaultCode]!;
  }

  static Future<String> loadDefaultCode() async {
    // ★ 收斂到朋友版邏輯：以 getDefaultCurrencyCode() 為單一資料來源
    // （原本直接讀 setting_currency_code 的實作已停用，改由朋友版方法決定預設幣別）
    return CurrencyService.instance.getDefaultCurrencyCode();
  }

  static Future<String> loadDefaultLabel() async {
    final code = await loadDefaultCode();
    return labelForCode(code);
  }

  static Future<void> saveDefaultLabel(String label) async {
    // ★ 收斂到朋友版邏輯：以 setDefaultCurrency() 為準
    // （setDefaultCurrency 會寫入 setting_default_currency_code 與 setting_currency）
    final code = codeFromSetting(label);
    await CurrencyService.instance.setDefaultCurrency(code);
    // 過渡相容：部分現有頁面仍直接讀舊 key setting_currency_code，這裡一併同步，
    // 待那些頁面合併成朋友版、改走她的 API 後即可移除此行。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('setting_currency_code', code);
  }

  static String format(
      num value, {
        String? currencyCode,
        bool showSign = false,
        bool isIncome = false,
      }) {
    // ★ 收斂到朋友版邏輯：數字格式化改走 formatAmount（會依幣別小數位，如 USD/CNY 顯示 2 位）
    final code = codeFromSetting(currencyCode);
    final body = formatAmount(value, code);
    final sign = showSign ? (isIncome ? '+' : '-') : '';
    return '$sign$body';
  }

  // ★★★★★ 以下全部為合併自朋友版（旅遊匯率 / 即時匯率 / 預設幣別 keys） ★★★★★
  // 保留你原有成員不動；這裡只「新增」你沒有、朋友有的東西。
  // 註：labelForCode / symbolForCode 兩個同名成員沿用你原本的版本，未加入朋友的重複版。

  static const String defaultCurrencyCodeKey = 'setting_default_currency_code';
  static const String legacyCurrencyLabelKey = 'setting_currency';
  static const String travelEnabledKey = 'setting_travel_currency_enabled';
  static const String travelCurrencyCodeKey = 'setting_travel_currency_code';
  static const String travelStartDateKey = 'setting_travel_currency_start';
  static const String travelEndDateKey = 'setting_travel_currency_end';

  static const Map<String, String> labels = {
    'TWD': 'TWD / 新台幣',
    'USD': 'USD / 美元',
    'JPY': 'JPY / 日圓',
    'KRW': 'KRW / 韓圓',
    'CNY': 'CNY / 人民幣',
  };

  static List<String> get supportedCodes => labels.keys.toList(growable: false);
  static List<String> get supportedLabels => labels.values.toList(growable: false);

  /// 若字串能辨識為支援幣別就回傳代碼，否則回傳 null。
  /// 和 codeFromLabel 不同：這個函式不會把未知值硬當成 TWD。
  static String? tryNormalizeCode(String? labelOrCode) {
    final raw = (labelOrCode ?? '').trim().toUpperCase();
    if (raw.isEmpty) return null;
    if (labels.containsKey(raw)) return raw;
    for (final entry in labels.entries) {
      final label = entry.value.toUpperCase();
      if (label == raw || label.startsWith('$raw /')) return entry.key;
    }
    if (raw.contains('TWD') || raw.contains('新台幣') || raw.contains('台幣')) return 'TWD';
    if (raw.contains('USD') || raw.contains('美元')) return 'USD';
    if (raw.contains('JPY') || raw.contains('日圓') || raw.contains('日元')) return 'JPY';
    if (raw.contains('KRW') || raw.contains('韓圓') || raw.contains('韓元')) return 'KRW';
    if (raw.contains('CNY') || raw.contains('人民幣') || raw.contains('人民幣')) return 'CNY';
    return null;
  }

  static String formatAmount(num amount, String code, {bool showCode = false}) {
    final normalized = labels.containsKey(code) ? code : 'TWD';
    final decimals = decimalsFor(normalized);
    final symbol = symbolForCode(normalized);
    final nf = NumberFormat.decimalPattern();
    String number;
    if (decimals == 0) {
      number = nf.format(amount.round());
    } else {
      final decimalZeros = List.filled(decimals, '0').join();
      number = NumberFormat('#,##0.$decimalZeros').format(amount);
    }
    return showCode ? '$symbol$number $normalized' : '$symbol$number';
  }

  static int decimalsFor(String code) {
    switch (code) {
      case 'USD':
      case 'CNY':
        return 2;
      case 'TWD':
      case 'JPY':
      case 'KRW':
      default:
        return 0;
    }
  }

  static String codeFromLabel(String? labelOrCode) {
    final raw = (labelOrCode ?? '').trim().toUpperCase();
    if (labels.containsKey(raw)) return raw;
    for (final entry in labels.entries) {
      if (entry.value.toUpperCase() == raw || entry.value.toUpperCase().startsWith('$raw /')) {
        return entry.key;
      }
    }
    if (raw.contains('USD')) return 'USD';
    if (raw.contains('JPY')) return 'JPY';
    if (raw.contains('KRW')) return 'KRW';
    if (raw.contains('CNY')) return 'CNY';
    return 'TWD';
  }

  Future<String> getDefaultCurrencyCode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(defaultCurrencyCodeKey);
    if (savedCode != null && labels.containsKey(savedCode)) return savedCode;

    final legacy = prefs.getString(legacyCurrencyLabelKey);
    final code = codeFromLabel(legacy);
    await setDefaultCurrency(code);
    return code;
  }

  Future<void> setDefaultCurrency(String code) async {
    final normalized = labels.containsKey(code) ? code : 'TWD';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(defaultCurrencyCodeKey, normalized);
    await prefs.setString(legacyCurrencyLabelKey, labelForCode(normalized));
  }

  Future<void> setTravelCurrency({
    required String code,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final normalized = labels.containsKey(code) ? code : 'TWD';
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(travelEnabledKey, true);
    await prefs.setString(travelCurrencyCodeKey, normalized);
    await prefs.setString(travelStartDateKey, _dateKey(start));
    await prefs.setString(travelEndDateKey, _dateKey(end));
    await prefs.setString(legacyCurrencyLabelKey, labelForCode(normalized));
  }

  Future<void> disableTravelCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(travelEnabledKey, false);
    final defaultCode = await getDefaultCurrencyCode();
    await prefs.setString(legacyCurrencyLabelKey, labelForCode(defaultCode));
  }

  Future<String> getActiveCurrencyCode() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultCode = await getDefaultCurrencyCode();
    final travelEnabled = prefs.getBool(travelEnabledKey) ?? false;
    if (!travelEnabled) return defaultCode;

    final travelCode = prefs.getString(travelCurrencyCodeKey) ?? defaultCode;
    final start = _parseDateKey(prefs.getString(travelStartDateKey));
    final end = _parseDateKey(prefs.getString(travelEndDateKey));
    if (start == null || end == null) return defaultCode;

    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    if (!d.isBefore(start) && !d.isAfter(end)) {
      return labels.containsKey(travelCode) ? travelCode : defaultCode;
    }
    return defaultCode;
  }

  Future<bool> isTravelCurrencyExpired() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(travelEnabledKey) ?? false)) return false;
    final end = _parseDateKey(prefs.getString(travelEndDateKey));
    if (end == null) return false;
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    return d.isAfter(end);
  }

  /// 首頁月總額、房子與圖表使用『預設幣別』，不跟著旅行幣別切換。
  Future<CurrencyDisplaySettings> loadDefaultDisplaySettings() async {
    final defaultCode = await getDefaultCurrencyCode();
    final rate = await getRateFromTwd(defaultCode);
    final prefs = await SharedPreferences.getInstance();
    final rateDate = prefs.getString(_rateDateKey('TWD', defaultCode));
    return CurrencyDisplaySettings(
      code: defaultCode,
      label: labelForCode(defaultCode),
      symbol: symbolForCode(defaultCode),
      rateFromTwd: rate,
      rateDate: rateDate,
      isTravelMode: false,
      defaultCode: defaultCode,
    );
  }

  Future<CurrencyDisplaySettings> loadDisplaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultCode = await getDefaultCurrencyCode();
    final activeCode = await getActiveCurrencyCode();
    final travelEnabled = prefs.getBool(travelEnabledKey) ?? false;
    final rate = await getRateFromTwd(activeCode);
    final rateDate = prefs.getString(_rateDateKey('TWD', activeCode));
    return CurrencyDisplaySettings(
      code: activeCode,
      label: labelForCode(activeCode),
      symbol: symbolForCode(activeCode),
      rateFromTwd: rate,
      rateDate: rateDate,
      isTravelMode: travelEnabled && activeCode != defaultCode,
      defaultCode: defaultCode,
    );
  }

  Future<String> travelSummaryText() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultCode = await getDefaultCurrencyCode();
    final travelEnabled = prefs.getBool(travelEnabledKey) ?? false;
    if (!travelEnabled) return '預設：${labelForCode(defaultCode)}';
    final code = prefs.getString(travelCurrencyCodeKey) ?? defaultCode;
    final start = prefs.getString(travelStartDateKey) ?? '-';
    final end = prefs.getString(travelEndDateKey) ?? '-';
    return '預設：${labelForCode(defaultCode)}｜旅行：${labelForCode(code)} ($start ~ $end)';
  }

  Future<double> getRateFromTwd(String toCode) async {
    return getRate('TWD', toCode);
  }

  Future<double> getRate(String fromCode, String toCode) async {
    final from = labels.containsKey(fromCode) ? fromCode : 'TWD';
    final to = labels.containsKey(toCode) ? toCode : 'TWD';
    if (from == to) return 1.0;

    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey(DateTime.now());
    final valueKey = _rateValueKey(from, to);
    final dateKey = _rateDateKey(from, to);
    final cachedDate = prefs.getString(dateKey);
    final cachedValue = prefs.getDouble(valueKey);
    if (cachedDate == today && cachedValue != null && cachedValue > 0) {
      return cachedValue;
    }

    try {
      final uri = Uri.parse('https://api.frankfurter.dev/v2/rate/$from/$to');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final rate = _toDouble(data['rate']);
        final apiDate = data['date']?.toString() ?? today;
        if (rate != null && rate > 0) {
          await prefs.setDouble(valueKey, rate);
          await prefs.setString(dateKey, apiDate);
          return rate;
        }
      }
    } catch (_) {
      // 如果即時匯率暫時失敗，就使用快取；沒有快取才退回 1.0，避免 App 當場壞掉。
    }

    if (cachedValue != null && cachedValue > 0) return cachedValue;
    return 1.0;
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static String _rateValueKey(String from, String to) => 'exchange_rate_${from}_$to';
  static String _rateDateKey(String from, String to) => 'exchange_rate_date_${from}_$to';

  static String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDateKey(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return DateTime(dt.year, dt.month, dt.day);
    } catch (_) {
      return null;
    }
  }
}
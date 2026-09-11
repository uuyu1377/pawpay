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

/// 一單位外幣約等於多少新台幣。
///
/// 臺灣銀行的「本行賣出」代表使用者用新台幣取得外幣，與旅遊消費換算方向一致。
/// 電子／刷卡估算優先採即期賣出；沒有即期牌價的幣別才退回現金賣出。
class ExchangeRateQuote {
  final String currencyCode;
  final double twdPerUnit;
  final String rateType;
  final String rateDate;
  final String source;
  final bool isStale;

  const ExchangeRateQuote({
    required this.currencyCode,
    required this.twdPerUnit,
    required this.rateType,
    required this.rateDate,
    required this.source,
    this.isStale = false,
  });

  Map<String, dynamic> toJson() => {
        'currency_code': currencyCode,
        'twd_per_unit': twdPerUnit,
        'rate_type': rateType,
        'rate_date': rateDate,
        'source': source,
      };

  factory ExchangeRateQuote.fromJson(Map<String, dynamic> json, {bool isStale = false}) {
    return ExchangeRateQuote(
      currencyCode: json['currency_code']?.toString() ?? 'TWD',
      twdPerUnit: (json['twd_per_unit'] as num?)?.toDouble() ??
          double.tryParse(json['twd_per_unit']?.toString() ?? '') ??
          0,
      rateType: json['rate_type']?.toString() ?? '未知',
      rateDate: json['rate_date']?.toString() ?? '',
      source: json['source']?.toString() ?? '未知來源',
      isStale: isStale,
    );
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
  static const String _botRateCacheKey = 'bot_exchange_rate_quotes_v1';
  static const String _botRateCacheDateKey = 'bot_exchange_rate_quotes_date_v1';

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

    final fromTwd = from == 'TWD' ? 1.0 : (await getTwdQuote(from)).twdPerUnit;
    final toTwd = to == 'TWD' ? 1.0 : (await getTwdQuote(to)).twdPerUnit;
    if (fromTwd <= 0 || toTwd <= 0) {
      throw StateError('無法取得 $from/$to 的有效匯率');
    }

    // 例：USD -> JPY = (1 USD 等於多少 TWD) / (1 JPY 等於多少 TWD)。
    final rate = fromTwd / toTwd;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_rateValueKey(from, to), rate);
    await prefs.setString(_rateDateKey(from, to), _dateKey(DateTime.now()));
    return rate;
  }

  /// 取得「1 單位外幣約等於多少 TWD」的牌告資訊。
  Future<ExchangeRateQuote> getTwdQuote(String currencyCode) async {
    final code = codeFromLabel(currencyCode);
    final today = _dateKey(DateTime.now());
    if (code == 'TWD') {
      return ExchangeRateQuote(
        currencyCode: 'TWD',
        twdPerUnit: 1,
        rateType: '基準幣別',
        rateDate: today,
        source: 'TWD',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = _readQuoteCache(prefs);
    final cachedDate = prefs.getString(_botRateCacheDateKey);
    final cachedQuote = _quoteFromCache(cached, code, isStale: cachedDate != today);
    if (cachedDate == today && cachedQuote != null) return cachedQuote;

    try {
      final quotes = await _fetchBankOfTaiwanQuotes();
      if (quotes.isNotEmpty) {
        await prefs.setString(
          _botRateCacheKey,
          jsonEncode(quotes.map((key, value) => MapEntry(key, value.toJson()))),
        );
        await prefs.setString(_botRateCacheDateKey, today);
        final quote = quotes[code];
        if (quote != null) return quote;
      }
    } catch (_) {
      // 臺銀暫時無法連線時，先使用上次成功快取；沒有快取才走次要公開匯率。
    }

    if (cachedQuote != null && cachedQuote.twdPerUnit > 0) return cachedQuote;

    final fallback = await _fetchReferenceFallback(code);
    final merged = <String, dynamic>{...cached, code: fallback.toJson()};
    await prefs.setString(_botRateCacheKey, jsonEncode(merged));
    await prefs.setString(_botRateCacheDateKey, today);
    return fallback;
  }

  Map<String, dynamic> _readQuoteCache(SharedPreferences prefs) {
    final raw = prefs.getString(_botRateCacheKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  ExchangeRateQuote? _quoteFromCache(
    Map<String, dynamic> cache,
    String code, {
    required bool isStale,
  }) {
    final raw = cache[code];
    if (raw is! Map) return null;
    final quote = ExchangeRateQuote.fromJson(Map<String, dynamic>.from(raw), isStale: isStale);
    return quote.twdPerUnit > 0 ? quote : null;
  }

  Future<Map<String, ExchangeRateQuote>> _fetchBankOfTaiwanQuotes() async {
    final uri = Uri.parse('https://rate.bot.com.tw/xrt/fltxt/0/day');
    final response = await http.get(uri).timeout(const Duration(seconds: 7));
    if (response.statusCode != 200) {
      throw StateError('臺灣銀行匯率服務回應 ${response.statusCode}');
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true).replaceFirst('\ufeff', '');
    final today = _dateKey(DateTime.now());
    final result = <String, ExchangeRateQuote>{};

    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('Currency')) continue;
      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.length < 7) continue;

      final code = tokens.first.toUpperCase();
      if (!labels.containsKey(code) || code == 'TWD') continue;
      final sellingIndex = tokens.indexOf('Selling');
      if (sellingIndex < 0 || sellingIndex + 2 >= tokens.length) continue;

      final cashSelling = double.tryParse(tokens[sellingIndex + 1]) ?? 0;
      final spotSelling = double.tryParse(tokens[sellingIndex + 2]) ?? 0;
      final useSpot = spotSelling > 0;
      final value = useSpot ? spotSelling : cashSelling;
      if (value <= 0) continue;

      result[code] = ExchangeRateQuote(
        currencyCode: code,
        twdPerUnit: value,
        rateType: useSpot ? '即期賣出' : '現金賣出（無即期牌價）',
        rateDate: today,
        source: '臺灣銀行牌告匯率',
      );
    }

    if (result.isEmpty) throw StateError('臺灣銀行匯率內容格式無法辨識');
    return result;
  }

  /// 臺銀與本機快取都不可用時才使用；不再把外幣錯當成 1:1 TWD。
  Future<ExchangeRateQuote> _fetchReferenceFallback(String code) async {
    final uri = Uri.parse('https://open.er-api.com/v6/latest/TWD');
    final response = await http.get(uri).timeout(const Duration(seconds: 7));
    if (response.statusCode != 200) {
      throw StateError('目前無法取得 $code 匯率，請連線後再試');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final rates = data is Map ? data['rates'] : null;
    final foreignPerTwd = rates is Map ? _toDouble(rates[code]) : null;
    if (foreignPerTwd == null || foreignPerTwd <= 0) {
      throw StateError('公開匯率服務沒有提供 $code');
    }
    return ExchangeRateQuote(
      currencyCode: code,
      twdPerUnit: 1 / foreignPerTwd,
      rateType: '市場參考匯率（備援）',
      rateDate: _dateKey(DateTime.now()),
      source: 'ExchangeRate-API',
    );
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

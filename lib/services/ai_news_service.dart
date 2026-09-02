import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:user_interface/models/transaction_model.dart';

class AiNewsService {
  static const String _openAiApiKey = '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';

  static Future<String> analyzeTransactions(List<Transaction> transactions) async {
    final now = DateTime.now();

    final recentTxs = transactions
        .where((tx) => tx.date.isAfter(now.subtract(const Duration(days: 30))))
        .take(30)
        .map((tx) {
      return {
        'category': tx.category,
        'note': tx.note,
        'amount': tx.amount,
        'type': tx.type.name,
        'date': tx.date.toIso8601String(),
      };
    }).toList();

    if (recentTxs.isEmpty) {
      return '目前記帳資料還不夠，新增幾筆後我就能幫你分析消費趨勢。';
    }

    final prompt = '''
你是一個智慧記帳 App 的 AI 財務助理。

請根據使用者最近 30 天記帳資料，產生一則首頁小喇叭公告。

要求：
1. 使用繁體中文
2. 30 字以內
3. 像 App 首頁公告，不要太長
4. 可以提醒使用者關注消費、物價、投資或預算
5. 不要給買進或賣出建議
6. 如果有股票、ETF、投資紀錄，只能說「可留意相關新聞」
7. 不要換行
8. 不要使用條列

使用者最近記帳資料：
${jsonEncode(recentTxs)}
''';

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAiApiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4.1-mini',
        'input': prompt,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('OpenAI 分析失敗：${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    return data['output_text'] ?? 'AI 分析暫時無法取得。';
  }
}
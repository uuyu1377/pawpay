import 'dart:math';

import 'game_api_service.dart';

/// ★ 新增：單人大富翁電腦玩家的台詞。
///
/// 開局時呼叫 [prepare]：先用內建台詞，同時請 5000 後端的 AI 生成一批新的台詞，
/// 回來後覆蓋上去。遊戲中用 [line] 依情境挑一句，不會每句都即時叫 AI（避免卡頓、浪費額度）。
class BotChatService {
  final _rng = Random();

  /// 電腦玩家的個性（id 對應 playground_page 的 Player.id）
  static const Map<int, String> personas = {
    1: '自信、愛放話、有點臭屁的兔子',
    2: '貪吃、天然呆、容易緊張的倉鼠',
    3: '說話像機器人系統公告、冷面笑匠的水獺',
  };

  /// 情境 key 跟後端 BOT_LINE_SITUATIONS 一致
  static const Map<int, Map<String, List<String>>> _builtIn = {
    1: {
      'game_start': ['這局我贏定了🐰', '準備好破產了嗎？', '今天手氣超好的感覺！'],
      'buy': ['這塊地歸我啦！', '眼光好，沒辦法😎', '地產大亨就是我'],
      'receive_rent': ['謝謝惠顧～💰', '租金收下，下次再來喔', '踩到我的地就要付錢！'],
      'pay_rent': ['可惡，下次換你付！', '這筆帳我記住了', '哼，小錢而已'],
      'chance_good': ['看吧，我就說手氣好', '運氣也是實力的一部分', '老天站在我這邊！'],
      'chance_bad': ['怎麼會這樣…', '這不算，重來！', '只是暖身失誤啦'],
      'mock': ['哈哈哈，好慘喔', '你今天是不是沒拜拜？', '要不要我借你錢😏'],
      'taunted': ['說大話誰不會～看骰子說話！', '哼，這點程度嚇不倒我', '等我買下整條街你就知道'],
      'bankrupt': ['我…我只是先回家休息', '下個月我會回來的！'],
    },
    2: {
      'game_start': ['大家好～我是來吃點心的🐹', '可以邊玩邊吃嗎？', '我會努力不破產的！'],
      'buy': ['買到了！可以在這裡開餐廳嗎', '這塊地看起來很好吃', '嘿嘿，我也有地了'],
      'receive_rent': ['謝謝你的點心錢🍪', '哇，有錢買零食了', '不好意思收你錢了啦'],
      'pay_rent': ['嗚嗚我的零食錢…', '好啦給你給你', '下次換你請我吃飯'],
      'chance_good': ['今天是幸運日！', '哇～可以買好多瓜子', '耶！好開心'],
      'chance_bad': ['嗚…我的錢包', '早知道不要出門', '我要去吃東西冷靜一下'],
      'mock': ['欸…你還好嗎？', '我分你一顆瓜子啦', '不要難過，下次會好的'],
      'taunted': ['不要兇我啦…我會哭喔', '好啦好啦你最厲害', '等我吃飽再跟你算帳'],
      'bankrupt': ['我去吃宵夜了，掰掰～', '下次我一定會贏的…吧'],
    },
    3: {
      'game_start': ['系統啟動。祝各位遊戲愉快。', '對戰程序載入完成。', '提示：破產不是一種策略。'],
      'buy': ['地產登記完成。', '資產配置已更新。', '本系統已取得該地使用權。'],
      'receive_rent': ['租金入帳，感謝您的配合。', '收款成功。', '系統提示：您剛剛變窮了。'],
      'pay_rent': ['支出已記錄，情緒穩定。', '這筆支出不在預算內。', '系統損失可接受。'],
      'chance_good': ['偵測到好運，已收下。', '機率站在系統這邊。', '收益超出預期。'],
      'chance_bad': ['錯誤代碼：運氣不足。', '損失已記錄，重新計算中。', '系統表示遺憾。'],
      'mock': ['已記錄您的不幸。', '建議您檢討投資策略。', '系統提示：記帳可以避免這種事。'],
      'taunted': ['已收到您的挑釁。勝率計算中……', '系統提示：嘴砲不會增加資產。', '請保持運動家精神。'],
      'bankrupt': ['系統資金歸零，準備關機…', '下個版本會更強。'],
    },
  };

  final Map<int, Map<String, List<String>>> _ai = {};
  bool _requested = false;

  /// 開局時呼叫一次。AI 失敗也沒關係，會一直用內建台詞。
  Future<void> prepare({required Map<int, String> botNames, required String opponentName}) async {
    if (_requested) return; // 同一個頁面只請一次 AI，換地圖重開時沿用
    _requested = true;
    try {
      final lines = await GameApiService.instance.fetchBotLines(
        bots: [
          for (final e in botNames.entries)
            {'id': '${e.key}', 'name': e.value, 'persona': personas[e.key] ?? ''},
        ],
        opponentName: opponentName,
      );
      for (final entry in lines.entries) {
        final id = int.tryParse(entry.key);
        final bySituation = entry.value;
        if (id == null || bySituation is! Map) continue;
        _ai[id] = {
          for (final s in bySituation.entries)
            if (s.value is List) s.key.toString(): (s.value as List).map((e) => e.toString()).toList(),
        };
      }
    } catch (_) {
      // 用內建台詞
    }
  }

  /// 依情境挑一句台詞。AI 台詞和內建台詞混著用，比較不會一直重複。
  String? line(int botId, String situation) {
    final pool = <String>[
      ...?_ai[botId]?[situation],
      ...?_builtIn[botId]?[situation],
    ];
    if (pool.isEmpty) return null;
    return pool[_rng.nextInt(pool.length)];
  }
}
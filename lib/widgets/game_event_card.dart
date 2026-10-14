import 'package:flutter/material.dart';

// ==========================================================
// ★ 新增：大富翁事件卡片（要按「確認」才會關閉，遊戲也會等你按完才繼續）
// ==========================================================
class GameEventCard {
  final String emoji;
  final String title;
  final String message;
  final bool negative;
  const GameEventCard({required this.emoji, required this.title, required this.message, this.negative = false});
}

class GameEventCardDialog extends StatelessWidget {
  final GameEventCard card;
  final List<String> extraLines;
  const GameEventCardDialog({super.key, required this.card, this.extraLines = const []});

  @override
  Widget build(BuildContext context) {
    final accent = card.negative ? const Color(0xFFE57373) : const Color(0xFF66BB6A);
    return PopScope(
      canPop: false, // 返回鍵也關不掉，一定要按確認
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withOpacity(0.15), shape: BoxShape.circle),
                child: Text(card.emoji, style: const TextStyle(fontSize: 40)),
              ),
              const SizedBox(height: 14),
              Text(card.title, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
              const SizedBox(height: 8),
              Text(card.message, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)),
              if (extraLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in extraLines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(l, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.4)),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('確認', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顯示一張事件卡片，等使用者按「確認」才回傳。
Future<void> showGameEventCard(BuildContext context, GameEventCard card, {List<String> extraLines = const []}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => GameEventCardDialog(card: card, extraLines: extraLines),
  );
}
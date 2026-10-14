import 'dart:async';

import 'package:flutter/material.dart';

import '../services/current_pet_manager.dart';

// =========================================================
// ★ 新增：大富翁聊天（單人跟電腦聊、好友對戰共用）
//   - 貼圖：用「目前上場寵物」的 6 張表情圖（assets/pets/<寵物>_happy.png 等）
//   - 嗆聲：預設短句一鍵送出
//   - 自由輸入：最多 30 字
// =========================================================

class PetSticker {
  final String key; // 跟後端 MP_CHAT_STICKERS 一致
  final String label;
  const PetSticker(this.key, this.label);
}

const List<PetSticker> kPetStickers = [
  PetSticker('happy', '得意'),
  PetSticker('angry', '生氣'),
  PetSticker('action', '衝啊！'),
  PetSticker('interact_1', '拜託～'),
  PetSticker('interact_2', '哈哈哈'),
  PetSticker('interact_3', '掰掰'),
];

const List<String> kQuickPhrases = [
  '這塊地我收下了😎',
  '快付租金啦～',
  '等著破產吧！',
  '下一回合換我發威🔥',
  '你運氣也太好了吧',
  '手下留情🙏',
  '我只是在暖身',
  '好啦你贏這把',
  'GG',
  '哈哈哈哈哈',
];

const int kChatMaxLength = 30;

/// 寵物 key → 貼圖圖片路徑，例如 shiba_dog + happy → assets/pets/shiba_happy.png
String? petStickerAsset(String? petKey, String stickerKey) {
  final base = CurrentPetManager.petImageMap[petKey ?? ''];
  if (base == null) return null;
  return base.replaceFirst(RegExp(r'\.png$'), '_$stickerKey.png');
}

String stickerLabel(String stickerKey) =>
    kPetStickers.firstWhere((s) => s.key == stickerKey, orElse: () => const PetSticker('', '')).label;

class GameChatMessage {
  final String id;
  final String name;
  final String? avatarPath;
  final String? emoji;
  final String? text;
  final String? stickerKey;
  final String? stickerAsset;
  final bool isMe;
  final Color color;

  const GameChatMessage({
    required this.id,
    required this.name,
    this.avatarPath,
    this.emoji,
    this.text,
    this.stickerKey,
    this.stickerAsset,
    this.isMe = false,
    this.color = const Color(0xFF90A4AE),
  });
}

/// 聊天紀錄 + 棋盤上正在顯示的泡泡（幾秒後自動消失）
class GameChatController extends ChangeNotifier {
  final List<GameChatMessage> history = [];
  final List<GameChatMessage> visible = [];
  final List<Timer> _timers = [];
  int unread = 0;
  bool panelOpen = false;

  /// silent=true：只放進聊天紀錄，不在棋盤上跳泡泡（例如剛進房間時的舊訊息）
  void add(GameChatMessage m, {bool silent = false}) {
    history.add(m);
    if (history.length > 100) history.removeAt(0);
    if (silent) {
      notifyListeners();
      return;
    }
    visible.add(m);
    if (visible.length > 3) visible.removeAt(0);
    if (!m.isMe && !panelOpen) unread++;
    _timers.add(Timer(Duration(seconds: m.stickerKey != null ? 4 : 5), () {
      visible.remove(m);
      notifyListeners();
    }));
    notifyListeners();
  }

  void markRead() {
    unread = 0;
    notifyListeners();
  }

  void clear() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    history.clear();
    visible.clear();
    unread = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }
}

// ---------------------------------------------------------
// 棋盤上的訊息泡泡
// ---------------------------------------------------------
class GameChatFeed extends StatelessWidget {
  final GameChatController controller;
  const GameChatFeed({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in controller.visible)
              TweenAnimationBuilder<double>(
                key: ValueKey(m.id),
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                builder: (_, v, child) => Transform.scale(scale: v, alignment: Alignment.bottomLeft, child: child),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ChatBubble(message: m, compact: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final GameChatMessage message;
  final bool compact;
  const _ChatBubble({required this.message, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final avatar = CircleAvatar(
      radius: compact ? 16 : 18,
      backgroundColor: m.color.withOpacity(0.18),
      child: m.avatarPath != null
          ? ClipOval(
        child: Image.asset(m.avatarPath!, width: 30, height: 30, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Text(m.emoji ?? '🐾')),
      )
          : Text(m.emoji ?? '🐾', style: const TextStyle(fontSize: 16)),
    );
    Widget content;
    if (m.stickerKey != null) {
      content = m.stickerAsset != null
          ? Image.asset(m.stickerAsset!, height: compact ? 72 : 88,
          errorBuilder: (_, __, ___) => Text('[${stickerLabel(m.stickerKey!)}]'))
          : Text('[${stickerLabel(m.stickerKey!)}]', style: const TextStyle(fontSize: 15));
    } else {
      content = Text(m.text ?? '', style: const TextStyle(fontSize: 14, height: 1.35));
    }
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: m.stickerKey != null
          ? const EdgeInsets.all(4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: m.stickerKey != null ? Colors.white.withOpacity(0.85) : (m.isMe ? const Color(0xFFFFF3E0) : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: m.color.withOpacity(0.45)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: content,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        avatar,
        const SizedBox(width: 6),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.isMe ? '你' : m.name,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: m.color)),
              const SizedBox(height: 2),
              bubble,
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------
// 💬 按鈕（有未讀數字）
// ---------------------------------------------------------
class GameChatButton extends StatelessWidget {
  final GameChatController controller;
  final VoidCallback onPressed;
  const GameChatButton({super.key, required this.controller, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: const SizedBox(
                width: 50,
                height: 50,
                child: Center(child: Text('💬', style: TextStyle(fontSize: 24))),
              ),
            ),
          ),
          if (controller.unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                child: Text('${controller.unread}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// 聊天面板：紀錄 + 貼圖 + 嗆聲短句 + 自由輸入
// ---------------------------------------------------------
Future<void> showGameChatPanel(
    BuildContext context, {
      required GameChatController controller,
      required String? myPetKey,
      required void Function({String? text, String? stickerKey}) onSend,
    }) async {
  controller.panelOpen = true;
  controller.markRead();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => _ChatPanel(controller: controller, myPetKey: myPetKey, onSend: onSend),
  );
  controller.panelOpen = false;
  controller.markRead();
}

class _ChatPanel extends StatefulWidget {
  final GameChatController controller;
  final String? myPetKey;
  final void Function({String? text, String? stickerKey}) onSend;
  const _ChatPanel({required this.controller, required this.myPetKey, required this.onSend});

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send({String? text, String? stickerKey}) {
    final t = text?.trim();
    if (stickerKey == null && (t == null || t.isEmpty)) return;
    widget.onSend(text: t, stickerKey: stickerKey);
    Navigator.of(context).pop(); // 關掉面板，讓使用者在棋盤上看到自己的泡泡
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final hasPetStickers = petStickerAsset(widget.myPetKey, 'happy') != null;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 10),
              const Text('聊天室', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              // 聊天紀錄
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.22,
                child: AnimatedBuilder(
                  animation: widget.controller,
                  builder: (context, _) {
                    final items = widget.controller.history.reversed.toList();
                    if (items.isEmpty) {
                      return Center(
                        child: Text('還沒有人說話，先嗆一句吧！', style: TextStyle(color: Colors.grey.shade500)),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Align(alignment: Alignment.centerLeft, child: _ChatBubble(message: items[i])),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              // 貼圖
              Text(hasPetStickers ? '我的寵物貼圖' : '貼圖（先到寵物頁選一隻上場寵物）',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SizedBox(
                height: 86,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kPetStickers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = kPetStickers[i];
                    final asset = petStickerAsset(widget.myPetKey, s.key);
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: asset == null ? null : () => _send(stickerKey: s.key),
                      child: Container(
                        width: 72,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: asset == null
                                  ? const Center(child: Text('🐾'))
                                  : Image.asset(asset, fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(child: Text('🐾'))),
                            ),
                            Text(s.label, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // 嗆聲短句
              Text('快速嗆聲', style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in kQuickPhrases)
                    ActionChip(
                      label: Text(p, style: const TextStyle(fontSize: 12.5)),
                      onPressed: () => _send(text: p),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              // 自由輸入
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      maxLength: kChatMaxLength,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) => _send(text: v),
                      decoration: InputDecoration(
                        hintText: '說點什麼…（最多 $kChatMaxLength 字）',
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _send(text: _input.text),
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
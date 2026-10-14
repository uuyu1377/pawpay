import 'package:flutter/material.dart';

import 'package:user_interface/services/game_api_service.dart';
import 'package:user_interface/services/current_pet_manager.dart';

class PetChoiceShopPage extends StatefulWidget {
  const PetChoiceShopPage({super.key});

  @override
  State<PetChoiceShopPage> createState() => _PetChoiceShopPageState();
}

class _PetChoiceShopPageState extends State<PetChoiceShopPage> {
  static const List<Map<String, String>> _pets = [
    {'key': 'dog', 'name': '狗狗', 'emoji': '🐶'},
    {'key': 'cat', 'name': '貓咪', 'emoji': '🐱'},
    {'key': 'parrot', 'name': '鸚鵡', 'emoji': '🦜'},
    {'key': 'sloth', 'name': '樹懶', 'emoji': '🦥'},
    {'key': 'fox', 'name': '狐狸', 'emoji': '🦊'},
    // ★ 修正：key 改成跟扭蛋 / 寵物頁一致，原本的 cute_dog 等舊 key 兌換後在寵物頁找不到圖
    {'key': 'shiba_dog', 'name': '柴柴', 'emoji': '🐕'},
    {'key': 'pomeranian', 'name': '博美犬', 'emoji': '🐩'},
    {'key': 'calm_dog', 'name': '諾姆犬', 'emoji': '🦮'},
    {'key': 'clingy_dog', 'name': '甩尾狗', 'emoji': '🐕'},
    {'key': 'love_cat', 'name': '愛心貓', 'emoji': '😻'},
    {'key': 'work_cat', 'name': '工作貓', 'emoji': '😼'},
    {'key': 'waiting_cat', 'name': '等待貓', 'emoji': '🐈'},
    {'key': 'rocket_cat', 'name': '火箭貓', 'emoji': '😸'},
    {'key': 'bear', 'name': '熊熊', 'emoji': '🐻'},
    {'key': 'bee', 'name': '蜜蜂', 'emoji': '🐝'},
    {'key': 'giraffe', 'name': '長頸鹿', 'emoji': '🦒'},
  ];

  // 舊資料可能存的是舊 key，讀進來時轉成新 key，才判斷得出「已擁有」
  static const Map<String, String> _legacyKeys = {
    'cute_dog': 'shiba_dog',
    'norm_dog': 'calm_dog',
    'wagging_dog': 'clingy_dog',
    'lovely_cat': 'love_cat',
    'blue_cat': 'work_cat',
    'loader_cat': 'waiting_cat',
  };
  static String _normKey(String key) => _legacyKeys[key] ?? key;

  bool _loading = true;
  bool _busy = false;
  int _tickets = 0;
  int _coins = 0;            // ★ 新增：扭蛋幣餘額
  int _ticketCoinCost = 1000; // ★ 修改：一張自選券 1000 扭蛋幣（以後端回傳的 ticket_coin_cost 為準）
  final Set<String> _ownedKeys = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final api = GameApiService.instance;
      final state = await api.fetchPetChoiceState();
      final owned = <String>{};
      final ticketPets = state['pets'];
      if (ticketPets is List) {
        for (final raw in ticketPets) {
          if (raw is! Map) continue;
          final key = raw['species_key']?.toString() ?? '';
          if (key.isNotEmpty) owned.add(_normKey(key));
        }
      }
      try {
        // ★ 修正：要帶目前登入的帳號；沒帶會讀到預設帳號（user 1）的寵物
        final existingPets = await api.fetchPets(userId: await api.resolveCurrentUserId());
        for (final pet in existingPets) {
          final key = (pet['icon_key'] ?? pet['species_name'])?.toString() ?? '';
          if (key.isNotEmpty) owned.add(_normKey(key));
        }
      } catch (_) {
        // 8000 API 未啟動時，仍可使用 5000 API 的自選券資料。
      }
      if (!mounted) return;
      setState(() {
        _tickets = _asInt(state['pet_choice_tickets']);
        _coins = _asInt(state['gacha_coins']);
        final cost = _asInt(state['ticket_coin_cost']);
        if (cost > 0) _ticketCoinCost = cost;
        _ownedKeys
          ..clear()
          ..addAll(owned);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('商店資料讀取失敗，請確認後端 5000 已啟動');
    }
  }

  // ★ 修改：寵物不課金。原本是「NT\$200 模擬付款」買自選券，改成用遊戲內扭蛋幣兌換。
  Future<void> _exchangeTicket() async {
    if (_busy) return;
    if (_coins < _ticketCoinCost) {
      _showMessage('扭蛋幣不足（需要 $_ticketCoinCost，目前 $_coins），完成記帳任務可以獲得扭蛋幣');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('兌換寵物自選券'),
        content: Text('使用 $_ticketCoinCost 扭蛋幣兌換 1 張寵物自選券？\n\n目前有 $_coins 扭蛋幣。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認兌換'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await GameApiService.instance.exchangePetChoiceTicket();
      if (!mounted) return;
      setState(() {
        _tickets = _asInt(result['pet_choice_tickets']);
        _coins = _asInt(result['gacha_coins']);
      });
      _showMessage('兌換成功，寵物自選券 +1');
    } catch (e) {
      _showMessage('兌換失敗：扭蛋幣不足，或後端 5000 未啟動');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _redeem(Map<String, String> pet) async {
    if (_busy || _tickets <= 0) return;
    final key = pet['key']!;
    if (_ownedKeys.contains(key)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('選擇${pet['name']}？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _petImage(pet, size: 120),
            const SizedBox(height: 12),
            const Text('確認後會使用 1 張寵物自選券，且無法改選其他寵物。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('確認兌換'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await GameApiService.instance.redeemPetChoiceTicket(
        speciesKey: key,
      );
      if (!mounted) return;
      setState(() {
        _tickets = _asInt(result['pet_choice_tickets']);
        _ownedKeys.add(key);
      });
      _showMessage('已解鎖${pet['name']}！');
    } catch (e) {
      _showMessage('兌換失敗：自選券不足或已擁有這隻寵物');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ★ 新增：寵物照片（跟扭蛋、寵物頁用同一批圖）
  Widget _petImage(Map<String, String> pet, {double size = 56, bool dimmed = false}) {
    final path = CurrentPetManager.petImageMap[pet['key']];
    final fallback = SizedBox(
      width: size,
      height: size,
      child: Center(child: Text(pet['emoji'] ?? '🐾', style: TextStyle(fontSize: size * 0.6))),
    );
    if (path == null) return fallback;
    final image = Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback,
    );
    return dimmed ? Opacity(opacity: 0.45, child: image) : image;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('寵物自選券')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF1DA), Color(0xFFFFD8E5)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_ticketCoinCost 扭蛋幣＝1 張寵物自選券',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text('可直接選擇一隻尚未擁有的寵物。扭蛋幣靠記帳任務取得，不需要花錢。\n目前有 $_coins 扭蛋幣'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.confirmation_number_rounded, size: 18),
                        label: Text('目前有 $_tickets 張'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _busy ? null : _exchangeTicket,
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('兌換一張'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '選擇寵物',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              _tickets > 0 ? '點選尚未擁有的寵物進行兌換' : '請先用扭蛋幣兌換一張寵物自選券',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _pets.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.35,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final pet = _pets[index];
                final owned = _ownedKeys.contains(pet['key']);
                final enabled = !owned && _tickets > 0 && !_busy;
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: enabled ? () => _redeem(pet) : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: owned ? Colors.grey.shade200 : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: enabled ? const Color(0xFFFF8A80) : Colors.grey.shade300,
                        width: enabled ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // ★ 修改：用設定好的寵物照片取代 emoji（找不到圖時才退回 emoji）
                        _petImage(pet, size: 56, dimmed: owned),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pet['name']!,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                owned ? '已擁有' : '使用 1 張券',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: owned ? Colors.grey : Colors.deepOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
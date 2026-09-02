import 'package:flutter/material.dart';

import 'package:user_interface/services/game_api_service.dart';

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
    {'key': 'cute_dog', 'name': '柴柴', 'emoji': '🐕'},
    {'key': 'pomeranian', 'name': '博美犬', 'emoji': '🐩'},
    {'key': 'norm_dog', 'name': '諾姆犬', 'emoji': '🦮'},
    {'key': 'wagging_dog', 'name': '甩尾狗', 'emoji': '🐕'},
    {'key': 'lovely_cat', 'name': '愛心貓', 'emoji': '😻'},
    {'key': 'blue_cat', 'name': '工作貓', 'emoji': '😼'},
    {'key': 'loader_cat', 'name': '等待貓', 'emoji': '🐈'},
    {'key': 'rocket_cat', 'name': '火箭貓', 'emoji': '😸'},
    {'key': 'bear', 'name': '熊熊', 'emoji': '🐻'},
    {'key': 'bee', 'name': '蜜蜂', 'emoji': '🐝'},
    {'key': 'giraffe', 'name': '長頸鹿', 'emoji': '🦒'},
  ];

  bool _loading = true;
  bool _busy = false;
  int _tickets = 0;
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
          if (key.isNotEmpty) owned.add(key);
        }
      }
      try {
        final existingPets = await api.fetchPets();
        for (final pet in existingPets) {
          final key = (pet['icon_key'] ?? pet['species_name'])?.toString() ?? '';
          if (key.isNotEmpty) owned.add(key);
        }
      } catch (_) {
        // 8000 API 未啟動時，仍可使用 5000 API 的自選券資料。
      }
      if (!mounted) return;
      setState(() {
        _tickets = _asInt(state['pet_choice_tickets']);
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

  Future<void> _purchaseTicket() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('購買寵物自選券'),
        content: const Text(
          'NT\$200 可獲得 1 張寵物自選券。\n\n'
          '專題展示版本只會模擬付款，不會產生真實扣款。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('模擬付款 NT\$200'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await GameApiService.instance.purchasePetChoiceTicket();
      if (!mounted) return;
      setState(() => _tickets = _asInt(result['pet_choice_tickets']));
      _showMessage('模擬付款完成，寵物自選券 +1');
    } catch (e) {
      _showMessage('購買失敗，請確認後端 5000 已啟動');
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
        content: const Text('確認後會使用 1 張寵物自選券，且無法改選其他寵物。'),
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('寵物自選商店')),
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
                        const Text(
                          'NT\$200＝1 張寵物自選券',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text('可直接選擇一隻尚未擁有的寵物。專題版為模擬付款，不會真的扣款。'),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Chip(
                              avatar: const Icon(Icons.confirmation_number_rounded, size: 18),
                              label: Text('目前有 $_tickets 張'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: _busy ? null : _purchaseTicket,
                              icon: const Icon(Icons.shopping_bag_rounded),
                              label: const Text('購買一張'),
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
                    _tickets > 0 ? '點選尚未擁有的寵物進行兌換' : '請先購買一張寵物自選券',
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
                              Text(pet['emoji']!, style: const TextStyle(fontSize: 34)),
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

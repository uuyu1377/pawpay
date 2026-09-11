// ★ AI 自適應(閉環修正記憶)：全新檔案，不動任何原有程式碼。
// 這頁把「AI 已經學會的分類規則」列出來（來自後端 /category-memory/list），
// 讓使用者(和教授)直接看到記憶在長大，也能刪掉不要的規則。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class CategoryMemoryPage extends StatefulWidget {
  const CategoryMemoryPage({super.key});

  @override
  State<CategoryMemoryPage> createState() => _CategoryMemoryPageState();
}

class _CategoryMemoryPageState extends State<CategoryMemoryPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _uid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'unknown_user';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = await _uid();
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/category-memory/list?user_id=$uid'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['items'] as List?) ?? [];
        _items = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {
      // 讀取失敗就顯示空狀態
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _delete(String keyword) async {
    try {
      final uid = await _uid();
      await http
          .post(
        Uri.parse('${ApiConfig.baseUrl}/category-memory/delete'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": uid, "keyword": keyword}),
      )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF5F5),
      appBar: AppBar(
        title: const Text('AI 學到的分類規則'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.brown,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Text('🧠 ', style: TextStyle(fontSize: 22)),
                  Expanded(
                    child: Text(
                      '你每次記帳/修正分類，AI 就會記住「這個店家或關鍵字要分到哪」。'
                          '被記住越多次（次數越高），下次就越會自動幫你分對。',
                      style: TextStyle(color: Colors.grey.shade700, height: 1.4, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    '還沒有學到任何規則\n多記幾筆帳、或修正 AI 的分類，這裡就會長出來',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, height: 1.5),
                  ),
                ),
              )
            else
              ..._items.map(_buildRuleTile),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleTile(Map<String, dynamic> item) {
    final keyword = (item['keyword'] ?? '').toString();
    final main = (item['main_category'] ?? '').toString();
    final sub = (item['sub_category'] ?? '').toString();
    final hit = (item['hit_count'] ?? 0);
    final int distinct = (item['distinct_count'] is int)
        ? item['distinct_count']
        : int.tryParse((item['distinct_count'] ?? 1).toString()) ?? 1;
    final int hitN = hit is int ? hit : int.tryParse(hit.toString()) ?? 0;
    final bool composite = distinct >= 2; // 複合式店家：一個關鍵字對到多種分類
    final bool strong = hitN >= 2 && !composite;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  keyword,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '→ $main${sub.isNotEmpty ? ' / $sub' : ''}',
                  style: TextStyle(color: Colors.brown.shade400, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (composite ? Colors.blueGrey : (strong ? Colors.green : Colors.orange)).withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              composite
                  ? '複合·依品項判斷'
                  : (strong ? '已自動套用 ·$hit次' : '學習中 ·$hit次'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: composite
                    ? Colors.blueGrey.shade700
                    : (strong ? Colors.green.shade700 : Colors.orange.shade800),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: Colors.grey.shade400),
            onPressed: () => _delete(keyword),
          ),
        ],
      ),
    );
  }
}
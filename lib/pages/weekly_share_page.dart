import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:user_interface/config/backend_config.dart';
import 'package:user_interface/models/transaction_model.dart';

enum ShareCardTemplate {
  cutePink,
  milkTea,
  nightBlue,
}

class WeeklyExpensePoint {
  final String label;
  final double amount;

  WeeklyExpensePoint({
    required this.label,
    required this.amount,
  });
}

class WeeklySharePage extends StatefulWidget {
  final List<Transaction> transactions;

  const WeeklySharePage({
    super.key,
    required this.transactions,
  });

  @override
  State<WeeklySharePage> createState() => _WeeklySharePageState();
}

class _WeeklySharePageState extends State<WeeklySharePage> {
  final GlobalKey _shareCardKey = GlobalKey();

  ShareCardTemplate _selectedTemplate = ShareCardTemplate.cutePink;

  bool _isAiLoading = false;
  String? _aiSummary;

  String _currentPet = 'dog';
  String _nickname = '使用者';

  @override
  void initState() {
    super.initState();
    _loadUserPetInfo();
    _loadAiSummary();
  }

  Future<void> _loadUserPetInfo() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _currentPet = prefs.getString('current_pet_key') ?? 'dog';
      _nickname = prefs.getString('user_nickname') ?? '使用者';
    });
  }

  List<WeeklyExpensePoint> _buildWeeklyExpenseData() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));

    final Map<String, double> dailyTotals = {};

    for (int i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final key = DateFormat('MM/dd').format(day);
      dailyTotals[key] = 0;
    }

    for (final tx in widget.transactions) {
      if (tx.type != TransactionType.expense) continue;

      final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (txDate.isBefore(start)) continue;

      final key = DateFormat('MM/dd').format(txDate);

      if (dailyTotals.containsKey(key)) {
        dailyTotals[key] = dailyTotals[key]! + tx.amount.abs();
      }
    }

    return dailyTotals.entries
        .map(
          (e) => WeeklyExpensePoint(
        label: e.key,
        amount: e.value,
      ),
    )
        .toList();
  }

  double _getWeeklyTotalExpense() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));

    double total = 0;

    for (final tx in widget.transactions) {
      if (tx.type != TransactionType.expense) continue;

      final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (txDate.isBefore(start)) continue;

      total += tx.amount.abs();
    }

    return total;
  }

  Map<String, double> _getCategoryTotals() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));

    final Map<String, double> categoryTotals = {};

    for (final tx in widget.transactions) {
      if (tx.type != TransactionType.expense) continue;

      final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
      if (txDate.isBefore(start)) continue;

      final category = tx.category.trim().isEmpty ? '未分類' : tx.category.trim();

      categoryTotals[category] =
          (categoryTotals[category] ?? 0) + tx.amount.abs();
    }

    return categoryTotals;
  }

  String _getTopCategory() {
    final categoryTotals = _getCategoryTotals();

    if (categoryTotals.isEmpty) return '無';

    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.key;
  }

  double _getTopCategoryAmount() {
    final categoryTotals = _getCategoryTotals();

    if (categoryTotals.isEmpty) return 0;

    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.first.value;
  }

  List<MapEntry<String, double>> _getTopThreeCategories() {
    final categoryTotals = _getCategoryTotals();

    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(3).toList();
  }

  String _categoryEmoji(String category) {
    final text = category.toLowerCase();

    if (text.contains('飲料') || text.contains('咖啡')) {
      return '🥤';
    }

    if (text.contains('飲') ||
        text.contains('食') ||
        text.contains('早餐') ||
        text.contains('午餐') ||
        text.contains('晚餐') ||
        text.contains('餐')) {
      return '🍔';
    }

    if (text.contains('交通') || text.contains('通勤')) {
      return '🚌';
    }

    if (text.contains('車')) {
      return '🚗';
    }

    if (text.contains('保險')) {
      return '🛡️';
    }

    if (text.contains('購物') || text.contains('衣')) {
      return '🛍️';
    }

    if (text.contains('娛樂') || text.contains('遊戲')) {
      return '🎮';
    }

    if (text.contains('旅遊') || text.contains('旅行')) {
      return '✈️';
    }

    if (text.contains('醫療') || text.contains('健康')) {
      return '💊';
    }

    if (text.contains('生活') || text.contains('日用')) {
      return '🧴';
    }

    if (text.contains('學') || text.contains('書')) {
      return '📚';
    }

    return '💸';
  }

  String _petEmoji() {
    switch (_currentPet) {
      case 'cat':
        return '😼';
      case 'fox':
        return '🦊';
      case 'parrot':
        return '🦜';
      case 'sloth':
        return '🦥';
      case 'dog':
      default:
        return '🐶';
    }
  }

  String _petName() {
    switch (_currentPet) {
      case 'cat':
        return '貓咪管家';
      case 'fox':
        return '狐狸顧問';
      case 'parrot':
        return '鸚鵡播報員';
      case 'sloth':
        return '樹懶小助理';
      case 'dog':
      default:
        return '狗狗記帳員';
    }
  }

  String _buildLocalCuteSummary({
    required String topCategory,
    required double totalExpense,
  }) {
    final pet = _petEmoji();
    final categoryEmoji = _categoryEmoji(topCategory);

    if (totalExpense == 0) {
      return '$pet 這週錢包超安全！$_nickname 的省錢力正在發光，繼續保持～';
    }

    if (_currentPet == 'cat') {
      return '$pet 哼，$categoryEmoji $topCategory 又成為花費王了。雖然有點會花，但至少有乖乖記帳，算你有進步。';
    }

    if (_currentPet == 'fox') {
      return '$pet 哎呀，這週 $categoryEmoji $topCategory 偷偷吃掉不少預算呢。下週可以聰明一點安排開銷。';
    }

    if (_currentPet == 'parrot') {
      return '$pet $topCategory、$topCategory！這週花費王出現啦～記帳有做到，預算也要顧到啦啦啦～';
    }

    if (_currentPet == 'sloth') {
      return '$pet 這週 $categoryEmoji $topCategory 比較明顯呢...慢慢調整就好，不用太有壓力...zzZ';
    }

    if (topCategory.contains('飲') ||
        topCategory.contains('食') ||
        topCategory.contains('餐')) {
      return '$pet 這週吃得很幸福，錢包也辛苦啦～下週一起溫柔控管飲食預算，汪！';
    }

    if (topCategory.contains('交通') || topCategory.contains('通勤')) {
      return '$pet 這週跑了不少地方，交通支出有點亮眼，辛苦移動的你了，汪！';
    }

    if (topCategory.contains('購物') || topCategory.contains('衣')) {
      return '$pet 這週購物小宇宙有啟動一下，下週可以幫錢包安排休息日，汪！';
    }

    return '$pet 這週花費王是 $categoryEmoji $topCategory，記帳雷達有抓到重點了，繼續一起守護錢包！';
  }

  Future<void> _loadAiSummary() async {
    try {
      if (!mounted) return;

      setState(() {
        _isAiLoading = true;
      });

      final prefs = await SharedPreferences.getInstance();

      final token = prefs.getString('jwt_token');
      final currentPet = prefs.getString('current_pet_key') ?? 'dog';
      final nickname = prefs.getString('user_nickname') ?? '使用者';

      final totalExpense = _getWeeklyTotalExpense();
      final topCategory = _getTopCategory();
      final topCategories = _getTopThreeCategories()
          .map((e) => '${e.key}:${e.value.toStringAsFixed(0)}')
          .join(',');

      final weeklyData = _buildWeeklyExpenseData()
          .map((e) => '${e.label}:${e.amount.toStringAsFixed(0)}')
          .join(',');

      if (token == null || token.trim().isEmpty) {
        _useLocalSummary();
        return;
      }

      final uri =
      Uri.parse('${BackendConfig.baseUrl}/api/weekly-share-summary')
          .replace(
        queryParameters: {
          'current_pet': currentPet,
          'nickname': nickname,
          'total_expense': totalExpense.toStringAsFixed(0),
          'top_category': topCategory,
          'top_categories': topCategories,
          'weekly_data': weeklyData,
        },
      );

      debugPrint('週報 AI 分析 API：$uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 20));

      debugPrint('週報 AI 分析 status：${response.statusCode}');
      debugPrint('週報 AI 分析 response：${response.body}');

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          decoded is Map<String, dynamic> &&
          (decoded['status'] == 'success' || decoded['ok'] == true)) {
        final summary = decoded['data']?['summary']?.toString().trim();

        if (summary != null && summary.isNotEmpty) {
          if (!mounted) return;

          setState(() {
            _currentPet = currentPet;
            _nickname = nickname;
            _aiSummary = summary;
            _isAiLoading = false;
          });

          return;
        }
      }

      _useLocalSummary();
    } on TimeoutException catch (e) {
      debugPrint('週報 AI 分析逾時：$e');
      _useLocalSummary();
    } catch (e) {
      debugPrint('週報 AI 分析失敗：$e');
      _useLocalSummary();
    }
  }

  void _useLocalSummary() {
    if (!mounted) return;

    final totalExpense = _getWeeklyTotalExpense();
    final topCategory = _getTopCategory();

    setState(() {
      _aiSummary = _buildLocalCuteSummary(
        topCategory: topCategory,
        totalExpense: totalExpense,
      );
      _isAiLoading = false;
    });
  }

  String _getTemplateName(ShareCardTemplate template) {
    switch (template) {
      case ShareCardTemplate.cutePink:
        return '粉色可愛';
      case ShareCardTemplate.milkTea:
        return '奶茶溫柔';
      case ShareCardTemplate.nightBlue:
        return '夜晚質感';
    }
  }

  Color _cardBackgroundColor() {
    switch (_selectedTemplate) {
      case ShareCardTemplate.cutePink:
        return const Color(0xFFFFF6FA);
      case ShareCardTemplate.milkTea:
        return const Color(0xFFFFF4E6);
      case ShareCardTemplate.nightBlue:
        return const Color(0xFF1F2433);
    }
  }

  Color _cardBorderColor() {
    switch (_selectedTemplate) {
      case ShareCardTemplate.cutePink:
        return const Color(0xFFFFC7DC);
      case ShareCardTemplate.milkTea:
        return const Color(0xFFE8CBA8);
      case ShareCardTemplate.nightBlue:
        return const Color(0xFF59607A);
    }
  }

  Color _mainTextColor() {
    switch (_selectedTemplate) {
      case ShareCardTemplate.cutePink:
        return const Color(0xFF5C2A3D);
      case ShareCardTemplate.milkTea:
        return const Color(0xFF5A3D2B);
      case ShareCardTemplate.nightBlue:
        return Colors.white;
    }
  }

  Color _subTextColor() {
    switch (_selectedTemplate) {
      case ShareCardTemplate.cutePink:
        return const Color(0xFF8A5A6A);
      case ShareCardTemplate.milkTea:
        return const Color(0xFF8A6A4D);
      case ShareCardTemplate.nightBlue:
        return const Color(0xFFD7D9E8);
    }
  }

  Color _highlightColor() {
    switch (_selectedTemplate) {
      case ShareCardTemplate.cutePink:
        return const Color(0xFFFF6FA8);
      case ShareCardTemplate.milkTea:
        return const Color(0xFFC9824A);
      case ShareCardTemplate.nightBlue:
        return const Color(0xFF9BB8FF);
    }
  }

  Future<File> _captureCardToFile() async {
    final context = _shareCardKey.currentContext;

    if (context == null) {
      throw Exception('找不到分享卡片畫面');
    }

    final boundary = context.findRenderObject() as RenderRepaintBoundary;

    final image = await boundary.toImage(pixelRatio: 3.0);

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      throw Exception('圖片轉換失敗');
    }

    final pngBytes = byteData.buffer.asUint8List();

    final dir = await getTemporaryDirectory();

    final file = File(
      '${dir.path}/weekly_expense_${DateTime.now().millisecondsSinceEpoch}.png',
    );

    await file.writeAsBytes(pngBytes);

    return file;
  }

  Future<void> _shareImage() async {
    try {
      final file = await _captureCardToFile();

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '這是我的本週可愛支出小週報！',
      );
    } catch (e) {
      debugPrint('分享圖片失敗：$e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('分享圖片失敗，請稍後再試'),
        ),
      );
    }
  }

  Future<void> _saveImageToGallery() async {
    try {
      final file = await _captureCardToFile();

      await Gal.putImage(file.path);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('圖片已儲存到相簿'),
        ),
      );
    } catch (e) {
      debugPrint('儲存圖片失敗：$e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('儲存圖片失敗，請確認相簿權限'),
        ),
      );
    }
  }

  Widget _buildTemplateSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ShareCardTemplate.values.map((template) {
        final isSelected = _selectedTemplate == template;

        return ChoiceChip(
          selected: isSelected,
          label: Text(_getTemplateName(template)),
          onSelected: (_) {
            setState(() {
              _selectedTemplate = template;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildDecorationDot({
    required double size,
    required Color color,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.25),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildShareCard() {
    final weeklyData = _buildWeeklyExpenseData();
    final totalExpense = _getWeeklyTotalExpense();
    final topCategory = _getTopCategory();
    final topCategoryAmount = _getTopCategoryAmount();
    final topThreeCategories = _getTopThreeCategories();

    final now = DateTime.now();
    final start = now.subtract(const Duration(days: 6));
    final dateRange =
        '${DateFormat('MM/dd').format(start)} - ${DateFormat('MM/dd').format(now)}';

    final maxAmount = weeklyData.isEmpty
        ? 100.0
        : weeklyData
        .map((e) => e.amount)
        .fold<double>(0, (a, b) => a > b ? a : b);

    final chartMaxY = maxAmount <= 0 ? 100.0 : maxAmount * 1.25;

    final summaryText = _aiSummary ??
        _buildLocalCuteSummary(
          topCategory: topCategory,
          totalExpense: totalExpense,
        );

    final topCategoryPercent = totalExpense <= 0
        ? 0
        : ((topCategoryAmount / totalExpense) * 100).round();

    return RepaintBoundary(
      key: _shareCardKey,
      child: Container(
        width: 370,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardBackgroundColor(),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: _cardBorderColor(),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                _selectedTemplate == ShareCardTemplate.nightBlue ? 0.22 : 0.08,
              ),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 8,
              right: 18,
              child: _buildDecorationDot(
                size: 38,
                color: _highlightColor(),
              ),
            ),
            Positioned(
              top: 72,
              right: 4,
              child: _buildDecorationDot(
                size: 18,
                color: _highlightColor(),
              ),
            ),
            Positioned(
              bottom: 140,
              left: 0,
              child: _buildDecorationDot(
                size: 24,
                color: _highlightColor(),
              ),
            ),
            DefaultTextStyle(
              style: TextStyle(
                color: _mainTextColor(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(
                            _selectedTemplate == ShareCardTemplate.nightBlue
                                ? 0.10
                                : 0.75,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          _petEmoji(),
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_nickname 的錢包週記',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: _mainTextColor(),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$dateRange ｜ ${_petName()}幫你整理好了',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _subTextColor(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: _highlightColor().withOpacity(
                        _selectedTemplate == ShareCardTemplate.nightBlue
                            ? 0.18
                            : 0.14,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本週總支出',
                          style: TextStyle(
                            fontSize: 13,
                            color: _subTextColor(),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'NT\$ ${NumberFormat('#,##0').format(totalExpense)}',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            color: _mainTextColor(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildMiniTag(
                              '${_categoryEmoji(topCategory)} 本週花費王：$topCategory',
                            ),
                            _buildMiniTag(
                              '占本週 $topCategoryPercent%',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    '一週支出心電圖',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _mainTextColor(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '哪一天錢包最有感？線條都幫你畫出來了 ✨',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _subTextColor(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: chartMaxY,
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (spots) {
                              return spots.map((spot) {
                                final index = spot.x.toInt();
                                final label = index >= 0 &&
                                    index < weeklyData.length
                                    ? weeklyData[index].label
                                    : '';
                                return LineTooltipItem(
                                  '$label\nNT\$ ${NumberFormat('#,##0').format(spot.y)}',
                                  TextStyle(
                                    color: _mainTextColor(),
                                    fontWeight: FontWeight.w800,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (value) {
                            return FlLine(
                              color: _subTextColor().withOpacity(0.16),
                              strokeWidth: 1,
                            );
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 42,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: _subTextColor(),
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();

                                if (index < 0 || index >= weeklyData.length) {
                                  return const SizedBox.shrink();
                                }

                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    weeklyData[index].label,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: _subTextColor(),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            barWidth: 4,
                            color: _highlightColor(),
                            belowBarData: BarAreaData(
                              show: true,
                              color: _highlightColor().withOpacity(0.16),
                            ),
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 4.5,
                                  color: _highlightColor(),
                                  strokeWidth: 2,
                                  strokeColor: _cardBackgroundColor(),
                                );
                              },
                            ),
                            spots: List.generate(
                              weeklyData.length,
                                  (index) {
                                return FlSpot(
                                  index.toDouble(),
                                  weeklyData[index].amount,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    '花費排行榜',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _mainTextColor(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (topThreeCategories.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(
                          _selectedTemplate == ShareCardTemplate.nightBlue
                              ? 0.08
                              : 0.7,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '這週還沒有支出資料唷',
                        style: TextStyle(
                          color: _subTextColor(),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ...topThreeCategories.asMap().entries.map((entry) {
                      final rank = entry.key + 1;
                      final item = entry.value;
                      final emoji = _categoryEmoji(item.key);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 9),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(
                            _selectedTemplate == ShareCardTemplate.nightBlue
                                ? 0.08
                                : 0.72,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _highlightColor().withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$rank',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: _highlightColor(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              emoji,
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.key,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: _mainTextColor(),
                                ),
                              ),
                            ),
                            Text(
                              'NT\$ ${NumberFormat('#,##0').format(item.value)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: _mainTextColor(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 14),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(
                        _selectedTemplate == ShareCardTemplate.nightBlue
                            ? 0.10
                            : 0.82,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _petEmoji(),
                          style: const TextStyle(fontSize: 25),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isAiLoading ? '正在幫你生成可愛小結論...' : summaryText,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: _mainTextColor(),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  Center(
                    child: Text(
                      'Share your weekly money mood ✨',
                      style: TextStyle(
                        fontSize: 11,
                        color: _subTextColor(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(
          _selectedTemplate == ShareCardTemplate.nightBlue ? 0.10 : 0.75,
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: _mainTextColor(),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saveImageToGallery,
            icon: const Icon(Icons.download_rounded),
            label: const Text('儲存圖片'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _shareImage,
            icon: const Icon(Icons.share_rounded),
            label: const Text('分享圖片'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalExpense = _getWeeklyTotalExpense();

    return Scaffold(
      appBar: AppBar(
        title: const Text('本週分享圖'),
        actions: [
          IconButton(
            onPressed: _loadAiSummary,
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: '重新產生 AI 小結論',
          ),
        ],
      ),
      body: SafeArea(
        child: totalExpense <= 0
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '這週還沒有支出紀錄，先記幾筆帳後再生成分享圖吧！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        )
            : SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '選擇分享圖模板',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              _buildTemplateSelector(),
              const SizedBox(height: 20),
              Center(
                child: _buildShareCard(),
              ),
              const SizedBox(height: 20),
              _buildActionButtons(),
              const SizedBox(height: 10),
              Text(
                '提示：AI 小結論如果還沒有接上後端，系統會自動使用本地寵物文案。',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
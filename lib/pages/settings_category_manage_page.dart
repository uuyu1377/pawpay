import 'package:flutter/material.dart';

import '../services/database_helper.dart';

class SettingsCategoryManagePage extends StatefulWidget {
  const SettingsCategoryManagePage({super.key});

  @override
  State<SettingsCategoryManagePage> createState() => _SettingsCategoryManagePageState();
}

class _SettingsCategoryManagePageState extends State<SettingsCategoryManagePage> {
  String _type = 'expense';
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    return DatabaseHelper.instance.getPickerCategories(type: _type);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _addCategoryDialog() async {
    final controller = TextEditingController();
    String type = _type;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: const Text('新增自訂分類'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'expense', label: Text('支出')),
                      ButtonSegment(value: 'income', label: Text('收入')),
                    ],
                    selected: {type},
                    onSelectionChanged: (value) => setDialogState(() => type = value.first),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '分類名稱',
                      hintText: '例如：演唱會、貓咪用品',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('新增'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;

    try {
      await DatabaseHelper.instance.addNewCategory(name, type, 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已新增分類：$name')),
      );
      setState(() => _type = type);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增失敗：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('類別與標籤管理'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '新增分類',
            icon: const Icon(Icons.add_rounded),
            onPressed: _addCategoryDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('支出分類'), icon: Icon(Icons.remove_circle_outline)),
                ButtonSegment(value: 'income', label: Text('收入分類'), icon: Icon(Icons.add_circle_outline)),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() => _type = value.first);
                _reload();
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _ErrorView(
                    message: '讀取分類失敗：${snapshot.error}',
                    onRetry: _reload,
                  );
                }

                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return _ErrorView(
                    message: '目前沒有分類資料，可點右上角新增。',
                    onRetry: _reload,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final name = (row['name'] ?? '未命名分類').toString();
                    final level = (row['level'] ?? '').toString();
                    final target = (row['target'] ?? '').toString();
                    final isVisible = row['is_visible']?.toString() == '1' || row['is_visible'] == true;
                    final isCustom = row['is_custom']?.toString() == '1' || row['is_custom'] == true;

                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _type == 'expense'
                              ? const Color(0xFFFFF4E6)
                              : const Color(0xFFEAFBF3),
                          child: Icon(
                            _type == 'expense' ? Icons.category_rounded : Icons.savings_rounded,
                            color: _type == 'expense'
                                ? const Color(0xFFFF9800)
                                : const Color(0xFF2E7D32),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text([
                          if (level.isNotEmpty) level == 'main' ? '主類' : '子類',
                          if (target.isNotEmpty) '適用：$target',
                          isCustom ? '自訂' : '內建',
                          isVisible ? '首頁可見' : '尚未解鎖',
                        ].join(' · ')),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded, size: 44, color: Colors.black45),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重新整理'),
            ),
          ],
        ),
      ),
    );
  }
}

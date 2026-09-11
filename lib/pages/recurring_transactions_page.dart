import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/transaction_model.dart';
import '../services/currency_service.dart';
import '../services/recurring_api_service.dart';
import 'type_page.dart';

class RecurringTransactionsPage extends StatefulWidget {
  const RecurringTransactionsPage({super.key});

  @override
  State<RecurringTransactionsPage> createState() => _RecurringTransactionsPageState();
}

class _RecurringTransactionsPageState extends State<RecurringTransactionsPage> {
  bool _loading = true;
  String? _error;
  List<RecurringTransactionRule> _rules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final rules = await RecurringApiService.instance.fetchRules();
      if (!mounted) return;
      setState(() => _rules = rules);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([RecurringTransactionRule? rule]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RecurringRuleEditor(initialRule: rule),
    );
    if (saved == true) await _load();
  }

  Future<void> _toggle(RecurringTransactionRule rule, bool active) async {
    try {
      await RecurringApiService.instance.saveRule(rule.copyWith(isActive: active));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新失敗：$e')));
    }
  }

  Future<void> _delete(RecurringTransactionRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除固定收支？'),
        content: const Text('已經產生的交易不會被刪除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除')),
        ],
      ),
    );
    if (confirmed != true || rule.id == null) return;
    try {
      await RecurringApiService.instance.deleteRule(rule.id!);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('刪除失敗：$e')));
    }
  }

  String _cadenceLabel(String cadence) {
    switch (cadence) {
      case 'weekly': return '每週';
      case 'yearly': return '每年';
      default: return '每月';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('固定收支')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text('固定收支服務暫時無法連線\n$_error', textAlign: TextAlign.center),
                        TextButton(onPressed: _load, child: const Text('重試')),
                      ],
                    ),
                  ),
                )
              : _rules.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '還沒有固定收支\n可新增房租、薪水、訂閱費等週期性項目',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, height: 1.6),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _rules.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final rule = _rules[index];
                          final color = rule.direction == 'income' ? Colors.green : Colors.redAccent;
                          final date = DateFormat('yyyy/MM/dd').format(rule.nextRunDate);
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _openEditor(rule),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: color.withOpacity(.12),
                                      child: Icon(
                                        rule.direction == 'income' ? Icons.south_west_rounded : Icons.north_east_rounded,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(rule.categoryName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${_cadenceLabel(rule.cadence)}・下次 $date${rule.note.isEmpty ? '' : '・${rule.note}'}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            CurrencyService.formatAmount(rule.amount, rule.currency, showCode: true),
                                            style: TextStyle(color: color, fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: rule.isActive,
                                      onChanged: (value) => _toggle(rule, value),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'edit') _openEditor(rule);
                                        if (value == 'delete') _delete(rule);
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(value: 'edit', child: Text('編輯')),
                                        PopupMenuItem(value: 'delete', child: Text('刪除')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

class _RecurringRuleEditor extends StatefulWidget {
  final RecurringTransactionRule? initialRule;
  const _RecurringRuleEditor({this.initialRule});

  @override
  State<_RecurringRuleEditor> createState() => _RecurringRuleEditorState();
}

class _RecurringRuleEditorState extends State<_RecurringRuleEditor> {
  late String _direction;
  late String _category;
  late String _currency;
  late String _cadence;
  late DateTime _startDate;
  late DateTime _nextRunDate;
  DateTime? _endDate;
  late bool _active;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    _direction = rule?.direction ?? 'expense';
    _category = rule?.categoryName ?? '飲食';
    _currency = rule?.currency ?? 'TWD';
    _cadence = rule?.cadence ?? 'monthly';
    _startDate = rule?.startDate ?? DateTime.now();
    _nextRunDate = rule?.nextRunDate ?? _startDate;
    _endDate = rule?.endDate;
    _active = rule?.isActive ?? true;
    _amountController = TextEditingController(
      text: rule == null ? '' : (rule.amount % 1 == 0 ? rule.amount.toInt().toString() : rule.amount.toString()),
    );
    _noteController = TextEditingController(text: rule?.note ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => TypePage(
          transactionType: _direction == 'income' ? TransactionType.income : TransactionType.expense,
        ),
      ),
    );
    if (result != null && mounted) setState(() => _category = result['name']?.toString() ?? _category);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (widget.initialRule == null || _nextRunDate.isBefore(picked)) _nextRunDate = picked;
      if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0 || _category.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請填寫有效金額與分類')));
      return;
    }
    setState(() => _saving = true);
    try {
      await RecurringApiService.instance.saveRule(RecurringTransactionRule(
        id: widget.initialRule?.id,
        direction: _direction,
        categoryName: _category.trim(),
        amount: amount,
        currency: _currency,
        note: _noteController.text.trim(),
        cadence: _cadence,
        startDate: _startDate,
        nextRunDate: _nextRunDate,
        endDate: _endDate,
        isActive: _active,
      ));
      await RecurringApiService.instance.processDue();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.initialRule == null ? '新增固定收支' : '編輯固定收支', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('支出'), icon: Icon(Icons.remove_rounded)),
                ButtonSegment(value: 'income', label: Text('收入'), icon: Icon(Icons.add_rounded)),
              ],
              selected: {_direction},
              onSelectionChanged: (value) => setState(() {
                _direction = value.first;
                _category = _direction == 'income' ? '薪水' : '飲食';
              }),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.category_rounded),
              title: const Text('分類'),
              subtitle: Text(_category),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickCategory,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '固定金額', prefixIcon: Icon(Icons.payments_rounded)),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _currency,
                  items: CurrencyService.supportedCodes
                      .map((code) => DropdownMenuItem(value: code, child: Text(code)))
                      .toList(),
                  onChanged: (value) => setState(() => _currency = value ?? 'TWD'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '備註（可選）', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _cadence,
              decoration: const InputDecoration(labelText: '重複週期', prefixIcon: Icon(Icons.repeat_rounded)),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('每週')),
                DropdownMenuItem(value: 'monthly', child: Text('每月')),
                DropdownMenuItem(value: 'yearly', child: Text('每年')),
              ],
              onChanged: (value) => setState(() => _cadence = value ?? 'monthly'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_rounded),
              title: const Text('開始日'),
              subtitle: Text(df.format(_startDate)),
              onTap: _pickStartDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_rounded),
              title: const Text('結束日（可不設定）'),
              subtitle: Text(_endDate == null ? '持續執行' : df.format(_endDate!)),
              trailing: _endDate == null
                  ? null
                  : IconButton(onPressed: () => setState(() => _endDate = null), icon: const Icon(Icons.clear_rounded)),
              onTap: _pickEndDate,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (value) => setState(() => _active = value),
              title: const Text('啟用這筆固定收支'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? '儲存中…' : '儲存'),
            ),
          ],
        ),
      ),
    );
  }
}

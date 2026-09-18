import 'package:flutter/material.dart';
import '../services/currency_service.dart';
import '../services/recurring_income_review_service.dart';
import '../widgets/recurring_income_review_bar.dart';
import '../widgets/income_review_problem.dart';

class RecurringIncomeHistoryPage extends StatefulWidget {
  const RecurringIncomeHistoryPage({super.key});
  @override
  State<RecurringIncomeHistoryPage> createState() => _RecurringIncomeHistoryPageState();
}

class _RecurringIncomeHistoryPageState extends State<RecurringIncomeHistoryPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<RecurringIncomeReview> _rows = [];
  final Set<String> _busy = {};
  RecurringIncomeReviewException? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final requestId = ++_requestId;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await RecurringIncomeReviewService.instance.fetchHistory(_month);
      if (!mounted || requestId != _requestId) return;
      setState(() { _rows = rows; _loading = false; });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() { _error = RecurringIncomeReviewException.from(error); _loading = false; });
    }
  }

  Future<void> _apply(RecurringIncomeReview row, String action) async {
    if (_busy.contains(row.key)) return;
    ++_requestId;
    setState(() => _busy.add(row.key));
    try {
      final updated = await RecurringIncomeReviewService.instance.apply(row, action);
      if (!mounted) return;
      ++_requestId;
      setState(() {
        _loading = false;
        _rows = _rows.map((r) => r.key == row.key ? updated : r).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'cancel' ? '已取消本次入帳，下期設定不變'
          : action == 'restore' ? '已復原本次收入' : '已確認收入'),
        action: action == 'cancel' ? SnackBarAction(label: '復原',
          onPressed: () => _apply(updated, 'restore')) : null,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      await _load();
    } finally {
      if (mounted) setState(() => _busy.remove(row.key));
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canNext = _month.isBefore(DateTime(now.year, now.month));
    return Scaffold(
      appBar: AppBar(title: const Text('固定收入入帳紀錄')),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: _busy.isEmpty ? () => _changeMonth(-1) : null,
            tooltip: '上個月', icon: const Icon(Icons.chevron_left)),
          Text('${_month.year} 年 ${_month.month} 月'),
          IconButton(onPressed: canNext && _busy.isEmpty ? () => _changeMonth(1) : null,
            tooltip: '下個月', icon: const Icon(Icons.chevron_right)),
        ]),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('到期會自動入帳；確認不會重複加錢。取消只影響這一期。',
            style: TextStyle(fontSize: 13, color: Colors.grey))),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? SingleChildScrollView(
              child: IncomeReviewProblem(problem: _error!, onRetry: _load))
          : RefreshIndicator(onRefresh: _load, child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: _rows.isEmpty ? [const Padding(padding: EdgeInsets.all(32),
                child: Center(child: Text('這個月沒有固定收入入帳紀錄')))]
                : _rows.map((row) => Card(child: Padding(
                    padding: const EdgeInsets.all(12), child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${row.categoryName}  ＋${CurrencyService.formatAmount(row.amount, row.currency)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(row.scheduledDate, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 8),
                        RecurringIncomeReviewBar(review: row, busy: _busy.contains(row.key),
                          onAction: (action) => _apply(row, action)),
                      ],
                    ),
                  ))).toList(),
            ))),
      ]),
    );
  }
}

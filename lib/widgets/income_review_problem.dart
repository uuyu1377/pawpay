import 'package:flutter/material.dart';
import '../services/recurring_income_review_service.dart';

class IncomeReviewProblem extends StatelessWidget {
  const IncomeReviewProblem({super.key, required this.problem, required this.onRetry});
  final RecurringIncomeReviewException problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
    decoration: BoxDecoration(color: const Color(0xFFFFF7EA),
      borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF947146)),
          const SizedBox(width: 8),
          Expanded(child: Text(problem.message, style: const TextStyle(fontSize: 13))),
        ]),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: onRetry, child: const Text('重試')),
          TextButton(onPressed: () => showDialog<void>(context: context,
            builder: (context) => AlertDialog(title: const Text('固定收入確認'),
              content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(problem.help), const SizedBox(height: 16),
                  SelectableText(problem.diagnostic, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
            )), child: const Text('查看原因')),
        ]),
      ]),
  );
}

import 'package:flutter/material.dart';
import '../services/recurring_income_review_service.dart';

class RecurringIncomeReviewBar extends StatelessWidget {
  const RecurringIncomeReviewBar({super.key, required this.review,
    required this.busy, required this.onAction});
  final RecurringIncomeReview review;
  final bool busy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final status = review.isCancelled ? '本次已取消・未計入收入'
      : review.isConfirmed ? '固定收入・已確認' : '已自動入帳・待確認';
    final color = review.isCancelled ? Colors.grey.shade700 : Colors.green.shade700;
    return Semantics(container: true, label: '固定收入確認', child: Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
      decoration: BoxDecoration(
        color: review.isCancelled ? Colors.grey.shade100 : const Color(0xFFF1F7EF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(spacing: 8, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(status, style: TextStyle(fontSize: 12, color: color)),
          if (busy)
            const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            if (!review.isConfirmed && !review.isCancelled)
              TextButton.icon(onPressed: () => onAction('confirm'),
                icon: const Icon(Icons.check_circle_outline, size: 20), label: const Text('確認')),
            if (!review.isCancelled)
              TextButton.icon(onPressed: () => onAction('cancel'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                icon: const Icon(Icons.cancel_outlined, size: 20), label: const Text('取消本次')),
            if (review.isCancelled)
              TextButton.icon(onPressed: () => onAction('restore'),
                icon: const Icon(Icons.undo_rounded, size: 20), label: const Text('復原本次')),
          ],
        ],
      ),
    ));
  }
}

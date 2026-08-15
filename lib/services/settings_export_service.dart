import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/transaction_model.dart';
import 'database_helper.dart';

class SettingsExportService {
  SettingsExportService._();

  static Future<File> exportTransactionsToCsv() async {
    final transactions = await DatabaseHelper.instance.getAllTransactions();
    final buffer = StringBuffer();

    buffer.writeln('id,date,type,category,note,amount,currency');
    for (final tx in transactions) {
      buffer.writeln([
        _csv(tx.id),
        _csv(DateFormat('yyyy-MM-dd HH:mm:ss').format(tx.date)),
        _csv(tx.type == TransactionType.expense ? 'expense' : 'income'),
        _csv(tx.category),
        _csv(tx.note),
        tx.amount.toStringAsFixed(0),
        _csv(tx.currency),
      ].join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'accounting_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File(p.join(dir.path, fileName));

    // 加 BOM，Excel 開啟中文比較不容易亂碼。
    await file.writeAsString('\uFEFF${buffer.toString()}', flush: true);
    return file;
  }

  static String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class ReportService {
  Future<File> exportExcel(List<Map<String, dynamic>> rows, {required String title}) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Transactions'];
    sheet.appendRow([
      TextCellValue('Date'), TextCellValue('Type'), TextCellValue('Category'),
      TextCellValue('Description'), TextCellValue('Amount (BDT)'),
    ]);
    for (final row in rows) {
      final date = row['transactionDate'];
      final dateText = date is Timestamp ? date.toDate().toIso8601String() : '';
      final amount = (row['amountMinor'] as num? ?? 0) / 100;
      sheet.appendRow([
        TextCellValue(dateText),
        TextCellValue('${row['kind'] ?? ''}'),
        TextCellValue('${row['category'] ?? ''}'),
        TextCellValue('${row['description'] ?? ''}'),
        DoubleCellValue(amount),
      ]);
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not create Excel report.');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> exportPdf(List<Map<String, dynamic>> rows, {required String title}) async {
    final document = pw.Document();
    final fontData = await rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf');
    final bengaliFont = pw.Font.ttf(fontData);
    final theme = pw.ThemeData.withFont(base: bengaliFont, bold: bengaliFont);
    var incomeMinor = 0; var expenseMinor = 0;
    for (final row in rows) { final amount = (row['amountMinor'] as num? ?? 0).toInt(); final kind = row['kind'] as String? ?? ''; if (kind == 'income' || kind == 'deposit') { incomeMinor += amount; } else if (kind == 'expense' || kind == 'messExpense' || kind == 'memberPaidExpense') { expenseMinor += amount; } }
    String kindLabel(String value) => switch (value) { 'deposit' || 'income' => 'আয় / জমা', 'expense' || 'messExpense' || 'memberPaidExpense' => 'খরচ', _ => value };
    String money(int minor) => (minor / 100).toStringAsFixed(2);
    document.addPage(pw.MultiPage(theme: theme, build: (_) => [
      pw.Header(level: 0, child: pw.Text('Finora — হিসাবের রিপোর্ট')),
      pw.Paragraph(text: 'রিপোর্ট: $title'),
      pw.Paragraph(text: 'তৈরির সময়: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}'),
      pw.SizedBox(height: 8),
      pw.Row(children: [pw.Expanded(child: pw.Text('মোট আয়: ৳${money(incomeMinor)}')), pw.Expanded(child: pw.Text('মোট খরচ: ৳${money(expenseMinor)}'))]),
      pw.SizedBox(height: 12),
      pw.TableHelper.fromTextArray(headers: ['তারিখ', 'ধরন', 'ক্যাটাগরি', 'বিবরণ', 'টাকা (৳)'], headerStyle: pw.TextStyle(font: bengaliFont, fontSize: 8), cellStyle: pw.TextStyle(font: bengaliFont, fontSize: 7), cellAlignment: pw.Alignment.centerLeft, data: rows.map((row) { final date = row['transactionDate']; final dateText = date is Timestamp ? DateFormat('dd-MM-yyyy').format(date.toDate()) : ''; final amount = money((row['amountMinor'] as num? ?? 0).toInt()); return [dateText, kindLabel('${row['kind'] ?? ''}'), '${row['category'] ?? ''}', '${row['description'] ?? ''}', amount]; }).toList()),
    ]));
    final dir = await getTemporaryDirectory(); final file = File('${dir.path}/${_safeName(title)}.pdf');
    await file.writeAsBytes(await document.save(), flush: true); return file;
  }
  Future<void> shareFile(File file) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], title: file.uri.pathSegments.last),
    );
  }

  String _safeName(String value) => value.toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

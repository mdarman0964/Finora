import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
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
    document.addPage(pw.MultiPage(build: (_) => [
      pw.Header(level: 0, child: pw.Text(title)),
      pw.Paragraph(text: 'Generated: ${DateTime.now().toIso8601String()}'),
      pw.TableHelper.fromTextArray(
        headers: ['Date', 'Type', 'Category', 'Description', 'BDT'],
        data: rows.map((row) {
          final date = row['transactionDate'];
          final dateText = date is Timestamp ? date.toDate().toIso8601String().split('T').first : '';
          final amount = ((row['amountMinor'] as num? ?? 0) / 100).toStringAsFixed(2);
          return [
            dateText,
            '${row['kind'] ?? ''}',
            '${row['category'] ?? ''}',
            '${row['description'] ?? ''}',
            amount,
          ];
        }).toList(),
      ),
    ]));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(title)}.pdf');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
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

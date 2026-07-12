import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/note.dart';

/// Exports notes to `~/Downloads` as .html or .pdf. Returns the written path.
class ExportService {
  static String get _downloads {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return p.join(home, 'Downloads');
  }

  static String _safeName(String title) =>
      title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  static Future<String> _uniquePath(String title, String ext) async {
    var path = p.join(_downloads, '${_safeName(title)}.$ext');
    var i = 1;
    while (await File(path).exists()) {
      path = p.join(_downloads, '${_safeName(title)} ($i).$ext');
      i++;
    }
    return path;
  }

  /// Markdown → standalone HTML file (wiki-links rendered as bold text).
  static Future<String> toHtml(Note note) async {
    final body = md.markdownToHtml(
      _resolveWikiLinks(note.body),
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>${note.title}</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; max-width: 760px;
         margin: 2rem auto; padding: 0 1rem; line-height: 1.6;
         color: #222; }
  h1, h2, h3 { color: #0b5560; }
  code { background: #f0f0f0; padding: 2px 4px; border-radius: 3px; }
  table { border-collapse: collapse; }
  td, th { border: 1px solid #ccc; padding: 4px 10px; }
  input[type=checkbox] { transform: scale(1.1); margin-right: 6px; }
</style>
</head>
<body>
$body
</body>
</html>
''';
    final path = await _uniquePath(note.title, 'html');
    await File(path).writeAsString(html);
    return path;
  }

  /// Markdown → plain-text PDF with embedded NotoSans (Cyrillic-safe).
  static Future<String> toPdf(Note note) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );

    final doc = pw.Document();
    final lines = _plainText(note.body).split('\n');
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (context) => [
          pw.Text(
            note.title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          for (final line in lines)
            line.trim().isEmpty
                ? pw.SizedBox(height: 8)
                : pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
        ],
      ),
    );

    final path = await _uniquePath(note.title, 'pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  static String _resolveWikiLinks(String body) => body.replaceAllMapped(
        RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
        (m) => '**${(m.group(2) ?? m.group(1))!.trim()}**',
      );

  /// Strip markdown markers for the plain-text PDF (v1.3 behaviour).
  static String _plainText(String body) => _resolveWikiLinks(body)
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // images/stickers
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAllMapped(
        RegExp(r'\*{1,2}([^*]+)\*{1,2}'),
        (m) => m.group(1)!,
      )
      .replaceAll('`', '');
}

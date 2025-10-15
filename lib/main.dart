import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:percent_indicator/percent_indicator.dart';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const AttendanceApp());

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Attendance Parser',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const AttendanceHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});
  @override
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome> {
  // ---- Business rule: minimum required % ----
  final double threshold = 80.0;

  // ---- Items to extract (token + type ↦ display label / key) ---------------
  final List<Map<String, String>> checks = const [
    // Engineering Graphics & Design
    {'key': 'EGD_PRAC', 'token': 'ENGINEERING GRAPHICS', 'type': 'PRAC', 'label': 'Engineering Graphics and Design — Practical'},
    {'key': 'EGD_THEO', 'token': 'ENGINEERING GRAPHICS', 'type': 'THEO', 'label': 'Engineering Graphics and Design — Theory'},

    // Calculus
    {'key': 'CALC_THEO', 'token': 'CALCULUS', 'type': 'THEO', 'label': 'Calculus — Theory'},
    {'key': 'CALC_TUTL', 'token': 'CALCULUS', 'type': 'TUTL', 'label': 'Calculus — Tutorial'},

    // Physics (PDF uses PRAC row for lab/tutorial)
    {'key': 'PHY_THEO', 'token': 'PHYSICS', 'type': 'THEO', 'label': 'Physics — Theory'},
    {'key': 'PHY_TUTL', 'token': 'PHYSICS', 'type': 'PRAC', 'label': 'Physics — Tutorial'},

    // Single-theory subjects
    {'key': 'ETHICS', 'token': 'ENGINEERING ETHICS', 'type': 'THEO', 'label': 'Engineering Ethics'},
    {'key': 'IKS', 'token': 'INDIAN KNOWLEDGE SYSTEM', 'type': 'THEO', 'label': 'Indian Knowledge System'},
    {'key': 'EVS', 'token': 'ENVIRONMENTAL STUDIES', 'type': 'THEO', 'label': 'Environmental Studies'},

    // Labs / Practices
    {'key': 'EEP_PRAC', 'token': 'ESSENTIAL ELECTRONICS', 'type': 'PRAC', 'label': 'Essential Electronics Practices — Practical'},

    // Computational Thinking
    {'key': 'CTPS_THEO', 'token': 'COMPUTATIONAL THINKING', 'type': 'THEO', 'label': 'Computational Thinking & Problem Solving — Theory'},
    {'key': 'CTPS_PRAC', 'token': 'COMPUTATIONAL THINKING', 'type': 'PRAC', 'label': 'Computational Thinking & Problem Solving — Practical'},

    // Biology
    {'key': 'BIO_THEO', 'token': 'ELEMENTS OF BIOLOGY', 'type': 'THEO', 'label': 'Elements of Biology — Theory'},
    {'key': 'BIO_TUTL', 'token': 'ELEMENTS OF BIOLOGY', 'type': 'TUTL', 'label': 'Elements of Biology — Tutorial'},
  ];

  // ---- Scheduled totals (semester plan you provided) ------------------------
  final Map<String, int> scheduledTotals = const {
    'EGD_PRAC': 30, 'EGD_THEO': 15,
    'CALC_THEO': 45, 'CALC_TUTL': 15,
    'PHY_THEO': 45, 'PHY_TUTL': 15,
    'ETHICS': 15, 'IKS': 15, 'EVS': 15,
    'EEP_PRAC': 30,
    'CTPS_THEO': 45, 'CTPS_PRAC': 30,
    'BIO_THEO': 30, 'BIO_TUTL': 15,
  };

  // ---- State ---------------------------------------------------------------
  bool isLoading = false;
  String? fileName;

  // Raw text + toggle
  String _rawExtractedText = '';
  bool _showRawExtracted = false;
  final TextEditingController _pasteController = TextEditingController();

  final Map<String, int> conductedSoFar = {};
  final Map<String, int> attendedSoFar = {};
  final Map<String, double> percentSoFar = {};
  final Map<String, int> remainingMissable = {};

  int totalAttendedAll = 0;
  double overallPercentSoFar = 0.0;
  int overallRemainingMissable = 0;

  // Debug counters
  int debugRowMatches = 0;
  int debugAssignedRows = 0;

  // ---- Text helpers ---------------------------------------------------------
  String _upper(String s) => s.toUpperCase();
  String _collapseWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  String _lettersOnly(String s) => s.replaceAll(RegExp(r'[^A-Z]'), '');

  // Strong prefilter to strip headers, division codes and boilerplate before parsing
  String _preFilterText(String input) {
    String t = input;

    // Normalize whitespace and uppercase for consistent matching
    t = t.replaceAll(RegExp(r'[\t\r]+'), ' ');
    t = t.replaceAll(RegExp(r'\n{2,}'), '\n');
    final upper = t.toUpperCase();

    // Keep content after first course block if present
    final idxCourse = upper.indexOf(RegExp(r'\b1\s+ENGINEERING|\bS\.NO\.'));
    String body = idxCourse >= 0 ? upper.substring(idxCourse) : upper;

    // Collapse whitespace again
    body = body.replaceAll(RegExp(r'\s+'), ' ');

    // Remove common division/batch codes and noise tokens
    final noisePatterns = <RegExp>[
      RegExp(r'\b[PTU]\d+\b'),            // T4, P4, U4
      RegExp(r'\bSEM\s*[IVX]+\b'),        // SEM I/II
      RegExp(r'\bDIV\b'),
      RegExp(r'\bCE\b'),
      RegExp(r'\bC\b'),
      RegExp(r'\bC\d+\b'),               // C1, C2
      RegExp(r'\bBATCH\s*\d+\b'),
      RegExp(r'\bLECTURE\s*TYPE\b'),
      RegExp(r'\bTOTAL\s+NO\.\s+OF\s+CLASSES\s+CONDUCTED\b'),
      RegExp(r'\bTOTAL\s+NO\.\s+OF\s+CLASSES\s+ATTENDED\b'),
      RegExp(r'\bPERCENTAGE\s*\(%\)\b'),
      RegExp(r'\bS\.NO\.?\b'),
    ];
    for (final p in noisePatterns) {
      body = body.replaceAll(p, ' ');
    }

    // Remove stray percentage values (e.g., 93.02)
    body = body.replaceAll(RegExp(r'\b\d{1,3}\.\d{1,2}\b'), ' ');

    // Tighten whitespace
    body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return body;
  }

  int _subjectScore(String ctxLettersOnly, String token) {
    final tokenLetters = _lettersOnly(_upper(token));
    return ctxLettersOnly.lastIndexOf(tokenLetters);
  }

  // ---- Parsing: robust single-pass over the whole text ----------------------
  void _parseWholeDoc(String rawExtracted) {
    // Reset
    conductedSoFar.clear();
    attendedSoFar.clear();
    percentSoFar.clear();
    remainingMissable.clear();
    totalAttendedAll = 0;
    overallRemainingMissable = 0;
    overallPercentSoFar = 0.0;
    debugRowMatches = 0;
    debugAssignedRows = 0;

    // Keep raw for toggle view
    _rawExtractedText = rawExtracted;

    // Prepare uppercase + collapsed copy for robust matching
    final textUpper = _upper(rawExtracted);
    final flat = _collapseWhitespace(textUpper);

    // (TYPE) <conducted> <attended>
    final rowRe = RegExp(r'\b(PRAC|THEO|TUTL)\s+(\d{1,3})\s+(\d{1,3})');
    final all = rowRe.allMatches(flat).toList();
    debugRowMatches = all.length;

    final assignedKeys = <String>{};

    for (final m in all) {
      final type = m.group(1)!.toUpperCase();
      final conducted = int.tryParse(m.group(2)!) ?? 0;
      final attended = int.tryParse(m.group(3)!) ?? 0;

      // Look back for the subject name
      final start = math.max(0, m.start - 180);
      final ctx = flat.substring(start, m.start);
      final ctxLetters = _lettersOnly(ctx);

      String? bestKey;
      int bestScore = -1;

      for (final cfg in checks) {
        final key = cfg['key']!;
        final token = cfg['token']!;
        final expectType = cfg['type']!.toUpperCase();

        if (expectType != type) continue;
        if (assignedKeys.contains(key)) continue;

        final score = _subjectScore(ctxLetters, token);
        if (score > bestScore) {
          bestScore = score;
          bestKey = key;
        }
      }

      if (bestKey != null && bestScore >= 0) {
        assignedKeys.add(bestKey);

        conductedSoFar[bestKey] = conducted;
        attendedSoFar[bestKey] = attended;
        debugAssignedRows++;

        final pct = conducted > 0 ? (attended / conducted) * 100.0 : 0.0;
        percentSoFar[bestKey] = pct;

        // Missable classes while staying ≥ threshold at semester end, using scheduled totals.
        // scheduledTotal = S; need attendedFinal ≥ ceil(0.8*S). Given attended so far = A, conducted so far = T.
        // Max additional misses = max(0, S - ceil(0.8*S) - (T - A)).
        final scheduled = scheduledTotals[bestKey] ?? conducted;
        final requiredAttendedFinal = (threshold / 100.0 * scheduled).ceil();
        final alreadyMissed = (conducted - attended).clamp(0, scheduled);
        final allowedTotalMiss = (scheduled - requiredAttendedFinal).clamp(0, scheduled);
        final remaining = (allowedTotalMiss - alreadyMissed).clamp(0, scheduled);
        remainingMissable[bestKey] = remaining;
      }
    }

    // Fill missing with zeros & compute missable from current counts
    for (final cfg in checks) {
      final key = cfg['key']!;
      if (!conductedSoFar.containsKey(key)) {
        conductedSoFar[key] = 0;
        attendedSoFar[key] = 0;
        percentSoFar[key] = 0.0;
        remainingMissable[key] = 0;
      }
    }

    totalAttendedAll = attendedSoFar.values.fold(0, (a, b) => a + b);
    final totalConductedSoFar = conductedSoFar.values.fold(0, (a, b) => a + b);
    overallPercentSoFar =
        totalConductedSoFar > 0 ? (totalAttendedAll / totalConductedSoFar) * 100.0 : 0.0;
    overallRemainingMissable =
        remainingMissable.values.fold(0, (a, b) => a + b);
  }

  // ---- OCR support: ensure tessdata on device -------------------------------
  Future<String> _ensureTessdata() async {
    final appSupport = await getApplicationSupportDirectory();
    final tessDir = Directory('${appSupport.path}/tessdata');

    if (!await tessDir.exists()) {
      await tessDir.create(recursive: true);
    }

    final engDst = File('${tessDir.path}/eng.traineddata');
    if (!await engDst.exists()) {
      // Try app bundle first (mobile), otherwise download from GitHub mirror
      try {
        final data = await rootBundle.load('assets/tessdata/eng.traineddata');
        await engDst.writeAsBytes(data.buffer.asUint8List(), flush: true);
      } catch (_) {
        final uri = Uri.parse('https://raw.githubusercontent.com/tesseract-ocr/tessdata_best/main/eng.traineddata');
        final resp = await http.get(uri);
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          await engDst.writeAsBytes(resp.bodyBytes, flush: true);
        } else {
          throw Exception('Failed to obtain eng.traineddata');
        }
      }
    }

    // Ensure plugin config path exists exactly as referenced by the plugin on desktop
    final cfgAssetsDir = Directory('${appSupport.path}/assets');
    if (!await cfgAssetsDir.exists()) {
      await cfgAssetsDir.create(recursive: true);
    }
    final cfgFile = File('${cfgAssetsDir.path}/tessdata_config.json');
    if (!await cfgFile.exists()) {
      const cfgJson = '{"psm":"6"}';
      await cfgFile.writeAsString(cfgJson, flush: true);
    }

    return appSupport.path; // parent of tessdata
  }

  // ---- OCR: render each PDF page -> image -> Tesseract ----------------------
  Future<String> _ocrPdfWithTesseract(Uint8List pdfBytes) async {
    final buf = StringBuffer();
    final doc = await pdfx.PdfDocument.openData(pdfBytes);
    final pages = doc.pagesCount;

    final tmpDir = await getTemporaryDirectory();
    final tessParent = await _ensureTessdata(); // ensures tessdata/eng.traineddata exists

    for (int i = 1; i <= pages; i++) {
      // Render at ~2x scale for better OCR
      final page = await doc.getPage(i);
      final imgPage = await page.render(
        width: (page.width * 3.0),
        height: (page.height * 3.0),
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      await page.close();

      if (imgPage == null) continue;

      final imgPath = '${tmpDir.path}/tess_page_$i.jpg';
      final f = File(imgPath);
      await f.writeAsBytes(imgPage.bytes, flush: true);

      // Run OCR (no initialize() call needed)
      final text = await FlutterTesseractOcr.extractText(
        imgPath,
        language: 'eng',
        args: {
          'psm': '6',
          'oem': '1',
          'tessdata': '$tessParent/tessdata',
          'preserve_interword_spaces': '1',
        },
      );

      if (text.trim().isNotEmpty) {
        buf.writeln(text);
        buf.writeln('\n'); // page separator
      }

      // Optionally delete temp images:
      // await f.delete();
    }

    await doc.close();
    return buf.toString();
  }

  // ---- Flow: pick & parse PDF ----------------------------------------------
  Future<void> processPdf() async {
    setState(() {
      isLoading = true;
      fileName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      if (result == null || result.files.single.bytes == null) {
        setState(() => isLoading = false);
        return;
      }

      fileName = result.files.single.name;
      final pdfBytes = result.files.single.bytes!;

      // 1) Try normal text extraction first (fast for digital PDFs)
      final docSf = PdfDocument(inputBytes: pdfBytes);
      String extracted = PdfTextExtractor(docSf).extractText();
      // Fallback: try page-by-page extraction (some PDFs return only per-page text)
      if (extracted.trim().isEmpty) {
        final buf = StringBuffer();
        for (int i = 0; i < docSf.pages.count; i++) {
          try {
            final pageText = PdfTextExtractor(docSf).extractText(startPageIndex: i, endPageIndex: i);
            if (pageText.trim().isNotEmpty) {
              buf.writeln(pageText);
              buf.writeln('\n');
            }
          } catch (_) {
            // ignore and continue
          }
        }
        if (buf.isNotEmpty) extracted = buf.toString();
      }
      docSf.dispose();

      // 2) If blank/near-blank, OCR via Tesseract
      if (extracted.trim().isEmpty || extracted.trim().length < 40) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No selectable text found. Running OCR...')),
          );
        }
        extracted = await _ocrPdfWithTesseract(pdfBytes);
      }

      // Pre-filter aggressively then parse
      final filtered = _preFilterText(extracted);
      _parseWholeDoc(filtered);

      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error reading PDF: $e')));
      }
    }
  }

  // ---- UI -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Parser'),
        actions: [
          IconButton(
            onPressed: processPdf,
            icon: const Icon(Icons.upload_file),
            tooltip: 'Pick Attendance PDF',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PortalAutomationScreen()),
              );
            },
            icon: const Icon(Icons.public),
            tooltip: 'Login to NMIMS portal',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: processPdf,
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Pick PDF'),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (fileName != null) ...[
          Text('File: $fileName', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Parsed rows: $debugAssignedRows / row matches found: $debugRowMatches',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 12),
        ],

        // Show raw extracted text toggle
        SwitchListTile(
          value: _showRawExtracted,
          onChanged: (v) => setState(() => _showRawExtracted = v),
          title: const Text('Show raw extracted text'),
          subtitle: const Text('Useful for debugging OCR output and line breaks'),
        ),
        if (_showRawExtracted) _rawExtractedCard(),
        const SizedBox(height: 12),

        _summaryCard(),
        const SizedBox(height: 12),
        _manualPasteCard(),
        const SizedBox(height: 12),
        ...checks.map(_subjectCard),
        const SizedBox(height: 20),
        const Text(
          'Notes:\n'
          '• Division column is ignored.\n'
          '• Percentages are computed from Attended / Conducted only.\n'
          '• “Remaining you can miss” uses your scheduled totals and an 80% threshold.\n'
          '• Physics Tutorial is taken from the PRAC row in the PDF.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  // Raw text viewer card with copy button
  Widget _rawExtractedCard() {
    final len = _rawExtractedText.length;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Raw extracted text',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                tooltip: 'Copy all',
                icon: const Icon(Icons.copy),
                onPressed: _rawExtractedText.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: _rawExtractedText));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Raw text copied to clipboard')),
                          );
                        }
                      },
              ),
            ]),
            Text('Length: $len chars',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    _rawExtractedText.isEmpty ? '— (no text extracted yet) —' : _rawExtractedText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final totalConductedSoFar = conductedSoFar.values.fold(0, (a, b) => a + b);
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overall Summary', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            LinearPercentIndicator(
              lineHeight: 10,
              percent: (overallPercentSoFar.clamp(0, 100) / 100),
              backgroundColor: Colors.grey[300],
              progressColor: overallPercentSoFar >= threshold ? Colors.green : Colors.red,
              animation: true,
            ),
            const SizedBox(height: 8),
            Text(
              'Conducted so far: $totalConductedSoFar | Attended: $totalAttendedAll | '
              '${overallPercentSoFar.toStringAsFixed(2)}%',
            ),
            const SizedBox(height: 6),
            Text(
              'You can still leave (across all subjects) and remain ≥ ${threshold.toStringAsFixed(0)}%: '
              '$overallRemainingMissable',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  // Manual paste card to parse copied text directly
  Widget _manualPasteCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Paste raw text to parse', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _pasteController,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Paste the copied PDF text here...',
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: () {
                final text = _pasteController.text;
                _rawExtractedText = text;
                final filtered = _preFilterText(text);
                setState(() {
                  _parseWholeDoc(filtered);
                  _showRawExtracted = true;
                });
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Parse pasted text'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                _pasteController.clear();
              },
              child: const Text('Clear'),
            )
          ])
        ]),
      ),
    );
  }

  Widget _subjectCard(Map<String, String> cfg) {
    final key = cfg['key']!;
    final label = cfg['label']!;

    final scheduled = scheduledTotals[key] ?? (conductedSoFar[key] ?? 0);
    final conducted = conductedSoFar[key] ?? 0;
    final attended = attendedSoFar[key] ?? 0;
    final pct = percentSoFar[key] ?? 0.0;
    final remaining = remainingMissable[key] ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearPercentIndicator(
            lineHeight: 8,
            percent: (pct.clamp(0, 100) / 100),
            backgroundColor: Colors.grey[300],
            progressColor: pct >= threshold ? Colors.green : Colors.red,
            animation: true,
          ),
          const SizedBox(height: 8),
          Text('Conducted: $conducted   |   Attended: $attended   |   ${pct.toStringAsFixed(2)}%'),
          const SizedBox(height: 6),
          Text('Scheduled total: $scheduled   |   Remaining you can miss (≥ ${threshold.toStringAsFixed(0)}%): $remaining'),
        ]),
      ),
    );
  }
}

// ---- Portal automation screen (WebView + DOM injection) ---------------------
class PortalAutomationScreen extends StatefulWidget {
  const PortalAutomationScreen({super.key});
  @override
  State<PortalAutomationScreen> createState() => _PortalAutomationScreenState();
}

class _PortalAutomationScreenState extends State<PortalAutomationScreen> {
  late final WebViewController _controller;
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _captchaCtrl = TextEditingController();
  bool _needsCaptcha = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) async {
          // Try to detect captcha element presence and prompt
          final hasCaptcha = await _controller.runJavaScriptReturningResult(
            '(function(){var c=document.querySelector("img[id*=\\"captcha\\"], img[src*=\\"captcha\\"]");return !!c;})()'
          );
          if ('$hasCaptcha' == 'true') {
            setState(() => _needsCaptcha = true);
          }
        },
      ))
      ..loadRequest(Uri.parse('https://sdc-sppap1.svkm.ac.in:50001/irj/portal'));
  }

  Future<void> _fillAndSubmit() async {
    final uid = _userCtrl.text;
    final pwd = _passCtrl.text;
    final cap = _captchaCtrl.text;

    // Best-effort field ids/names (adjust if needed on actual DOM)
    final js = """
      (function(){
        var user=document.querySelector(\"input[id*='userid'],input[name*='userid'],input[id*='User'],input[name*='User']\");
        var pass=document.querySelector(\"input[type='password']\");
        if(user){user.value='${uid.replaceAll("'", r"\'")}';}
        if(pass){pass.value='${pwd.replaceAll("'", r"\'")}';}
        var capEl=document.querySelector(\"input[id*='captcha'],input[name*='captcha']\");
        if(capEl){capEl.value='${cap.replaceAll("'", r"\'")}';}
        var btn=document.querySelector(\"input[type='submit'],button[type='submit'],button\");
        if(btn){btn.click(); return true;} else {return false;}
      })();
    """;
    await _controller.runJavaScript(js);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Portal Login')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: 'User ID'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true)),
          ]),
        ),
        if (_needsCaptcha)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(controller: _captchaCtrl, decoration: const InputDecoration(labelText: 'Captcha (type what you see in the page)')),
          ),
        Row(children: [
          const SizedBox(width: 8),
          ElevatedButton(onPressed: _fillAndSubmit, child: const Text('Fill & Submit')),
        ]),
        const Divider(height: 1),
        Expanded(child: WebViewWidget(controller: _controller)),
      ]),
    );
  }
}
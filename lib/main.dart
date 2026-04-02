import 'dart:typed_data';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance Calc',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AttendanceHome(),
    );
  }
}

class AttendanceHome extends StatefulWidget {
  const AttendanceHome({super.key});

  @override
  State<AttendanceHome> createState() => AttendanceHomeState();
}

enum LecType { theory, practical, tutorial }

/// Total semester load for each subject (used for "classes remaining" calculation)
/// Weekly load × 15 weeks per semester
final Map<String, Map<LecType, int>> weeklyLoad = {
  'LINEAR ALGEBRA AND DIFFERENTIAL EQUATIONS': {
    LecType.theory: 45, // 3 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'QUANTUM PHYSICS': {
    LecType.theory: 30, // 2 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'ELEMENTS OF BIOLOGY': {
    LecType.theory: 30, // 2 per week × 15 weeks
    LecType.practical: 15, // 1 per week × 15 weeks
  },
  'MANAGEMENT ACCOUNTING FOR ENGINEERS': {
    LecType.theory: 30, // 2 per week × 15 weeks
  },
  'OBJECT ORIENTED PROGRAMMING': {
    LecType.theory: 30, // 2 per week × 15 weeks
  },
  'OBJECT ORIENTED PROGRAMMING LAB': {
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'BASIC ELECTRICAL AND ELECTRONICS ENGINEERING': {
    LecType.theory: 30,
    LecType.practical: 30,
  },
  'WEB DEVELOPMENT': {
    LecType.practical: 30,
    LecType.tutorial: 30,
  },
  'PRODUCT REALIZATION': {
    LecType.theory: 15, // 1 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'TRANSFORMING IDEAS TO INNOVATION': {
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'CONSTITUTION OF INDIA': {
    LecType.theory: 15,
  },
  'ENGLISH COMMUNICATION': {
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'ENVIRONMENTAL SCIENCE': {
    LecType.theory: 15, // 1 per week × 15 weeks
  },
  'STATISTICAL METHODS': {
    LecType.theory: 30, // 2 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'MACHINE LEARNING': {
    LecType.theory: 15, // 1 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'INTRODUCTION TO DATA SIGNAL AND IMAGE ANALYSIS': {
    LecType.theory: 45, // 3 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'DATABASE MANAGEMENT SYSTEMS': {
    LecType.theory: 30, // 2 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'WEB PROGRAMMING': {
    LecType.theory: 30, // 2 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
  'DATA HANDLING AND VISUALIZATION': {
    LecType.theory: 15, // 1 per week × 15 weeks
    LecType.practical: 30, // 2 per week × 15 weeks
  },
};

class AttendanceHomeState extends State<AttendanceHome>
    with SingleTickerProviderStateMixin {
  String? fileName;
  String? studentName;
  static const double threshold = 80.0;
  bool isLoading = false;
  double? overallPercentage;
  int? totalClasses, attendedClasses, missable;
  Map<String, Map<String, dynamic>> subjectData = {};

  late AnimationController _controller;

  void _showGuide() {
    showDialog(
      context: context,
      builder: (context) => const GuideDialog(),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String normalizeSubject(String raw) {
    // Clean common prefixes/suffixes and codes stuck to names
    String subject = raw
        .replaceAll(
            RegExp(r'(T4|P4|U4|C1|C2|CE|Sem I|Sem II|Div C|Batch \d+|-\s*C\d?)',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\d+$'), '')
        .trim();

    final upper = subject.toUpperCase();
    if (upper.contains("LINEAR ALGEBRA") || upper.contains("DIFFER")) {
      return "LINEAR ALGEBRA AND DIFFERENTIAL EQUATIONS";
    } else if (upper.contains("QUANTUM")) {
      return "QUANTUM PHYSICS";
    } else if (upper.contains("BIOLOGY") || upper.contains("EOB")) {
      return "ELEMENTS OF BIOLOGY";
    } else if (upper.contains("MANAGEMENT") ||
        upper.contains("ACCOUNTING") ||
        upper.contains("MAE")) {
      return "MANAGEMENT ACCOUNTING FOR ENGINEERS";
    } else if (upper.contains("OBJECT ORIENTED") || upper.contains("OOP")) {
      if (upper.contains("LAB") || upper.contains("OOP-L")) {
        return "OBJECT ORIENTED PROGRAMMING LAB";
      }
      return "OBJECT ORIENTED PROGRAMMING";
    } else if (upper.contains("ELECTRICAL") ||
        upper.contains("ELECTRONICS") ||
        upper.contains("ELECTR")) {
      return "BASIC ELECTRICAL AND ELECTRONICS ENGINEERING";
    } else if (upper.contains("WEB DEVELOPMENT")) {
      return "WEB DEVELOPMENT";
    } else if (upper.contains("WEB PROGRAMMING") ||
        upper.contains("WEB PROG")) {
      return "WEB PROGRAMMING";
    } else if (upper.contains("WEB")) {
      return "WEB DEVELOPMENT";
    } else if (upper.contains("PRODUCT")) {
      return "PRODUCT REALIZATION";
    } else if (upper.contains("TRANSFORM") ||
        upper.contains("INNOVATION") ||
        upper.contains("TII")) {
      return "TRANSFORMING IDEAS TO INNOVATION";
    } else if (upper.contains("ENGLISH")) {
      return "ENGLISH COMMUNICATION";
    } else if (upper.contains("CONSTITUTION")) {
      return "CONSTITUTION OF INDIA";
    } else if (upper.contains("ENVIRONMENT") || upper.contains("ES")) {
      return "ENVIRONMENTAL SCIENCE";
    } else if (upper.contains("STATISTICAL")) {
      return "STATISTICAL METHODS";
    } else if (upper.contains("MACHINE LEARNING") || upper.contains("ML")) {
      return "MACHINE LEARNING";
    } else if ((upper.contains("DATA") && upper.contains("SIGNAL")) ||
        upper.contains("IMAGE ANALYSIS")) {
      return "INTRODUCTION TO DATA SIGNAL AND IMAGE ANALYSIS";
    } else if (upper.contains("DATABASE") || upper.contains("DBMS")) {
      return "DATABASE MANAGEMENT SYSTEMS";
    } else if ((upper.contains("DATA") && upper.contains("HANDLING")) ||
        upper.contains("VISUALIZATION")) {
      return "DATA HANDLING AND VISUALIZATION";
    }
    return subject;
  }

  Future<void> processPdf() async {
    setState(() => isLoading = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        fileName = result.files.single.name;
        await _parseAttendancePdfBytes(result.files.single.bytes!);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading PDF: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _parseAttendancePdfBytes(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      String text = PdfTextExtractor(document).extractText();
      document.dispose();

      // Remove newlines first to make parsing easier
      text = text.replaceAll('\n', ' ');

      // Extract student name from PDF header
      // Format: "SVKM'S NMIMS PRANJAL OM PRAKASH PATHAKStudent Name"
      // Get first word after NMIMS
      final nameMatch =
          RegExp(r'NMIMS\s+([A-Z]+)', caseSensitive: false).firstMatch(text);
      if (nameMatch != null) {
        studentName = nameMatch.group(1)?.trim();
        print('DEBUG: Found student name: $studentName'); // Debug
      } else {
        print('DEBUG: Student name not found in PDF'); // Debug
      }
      // Flexible regex: optional row num, subject, date, times, status (any chars)
      final rowPattern = RegExp(
        r'(?:\d+\s+)?(.+?)\s+((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4})\s+(\d{1,2}:\d{2}(?::\d{2})?\s[AP]M)\s+(\d{1,2}:\d{2}(?::\d{2})?\s[AP]M)\s+(\S+)',
        caseSensitive: false,
      );

      Map<String, Map<String, Map<String, int>>> counts = {};

      for (final match in rowPattern.allMatches(text)) {
        String rawSubject = match.group(1)!.trim();
        String status = match.group(5)!.trim().toUpperCase();

        // Skip if attendance is not updated (NU)
        if (status == 'NU' || status == 'NOT UPDATED') {
          continue;
        }

        String subject = normalizeSubject(rawSubject);

        String type;
        final upper = rawSubject.toUpperCase();
        if (upper.contains('U4')) {
          type = 'Tutorial';
        } else if (upper.contains('P4') ||
            upper.contains('BATCH') ||
            upper.contains('LAB')) {
          type = 'Practical';
        } else {
          type = 'Theory';
        }

        counts.putIfAbsent(
            subject,
            () => {
                  'Theory': {'T': 0, 'P': 0},
                  'Tutorial': {'T': 0, 'P': 0},
                  'Practical': {'T': 0, 'P': 0},
                });

        counts[subject]![type]!['T'] = (counts[subject]![type]!['T'] ?? 0) + 1;

        // Count as attended if status is 'P', 'PRESENT', etc.
        if (status == 'P' || status == 'PRESENT' || status == 'PRE') {
          counts[subject]![type]!['P'] =
              (counts[subject]![type]!['P'] ?? 0) + 1;
        }
      }

      subjectData.clear();
      int total = 0, attended = 0;
      counts.forEach((subject, data) {
        int subTotal = (data['Theory']!['T'] ?? 0) +
            (data['Tutorial']!['T'] ?? 0) +
            (data['Practical']!['T'] ?? 0);
        int subAttended = (data['Theory']!['P'] ?? 0) +
            (data['Tutorial']!['P'] ?? 0) +
            (data['Practical']!['P'] ?? 0);
        total += subTotal;
        attended += subAttended;

        int fixedTotal = subTotal;
        if (weeklyLoad.containsKey(subject)) {
          int load = 0;
          weeklyLoad[subject]!.forEach((type, val) => load += val);
          fixedTotal = load;
        }
        int allowedAbsences = (0.2 * fixedTotal).floor();
        int missed = subTotal - subAttended;
        int canMiss = (allowedAbsences - missed);
        if (canMiss < 0) canMiss = 0;

        int classesRemaining = (fixedTotal - subTotal);
        if (classesRemaining < 0) classesRemaining = 0;

        double subjectPercentage =
            subTotal == 0 ? 0.0 : (subAttended / subTotal) * 100.0;

        Map<String, dynamic> details = {
          'percentage': subjectPercentage,
          'canMiss': canMiss,
          'classesRemaining': classesRemaining,
          'types': [],
        };

        if ((data['Theory']!['T'] ?? 0) > 0) {
          details['types'].add({
            'name': 'Theory',
            'attended': data['Theory']!['P'] ?? 0,
            'total': data['Theory']!['T'] ?? 0,
          });
        }
        if ((data['Tutorial']!['T'] ?? 0) > 0) {
          details['types'].add({
            'name': 'Tutorial',
            'attended': data['Tutorial']!['P'] ?? 0,
            'total': data['Tutorial']!['T'] ?? 0,
          });
        }
        if ((data['Practical']!['T'] ?? 0) > 0) {
          details['types'].add({
            'name': 'Practical',
            'attended': data['Practical']!['P'] ?? 0,
            'total': data['Practical']!['T'] ?? 0,
          });
        }
        details['types'].add({
          'name': 'Total',
          'attended': subAttended,
          'total': subTotal,
        });

        subjectData[subject] = details;
      });

      final overall = total == 0 ? 0.0 : (attended / total) * 100.0;
      final canMissOverall = classesYouCanSkip(
          attended: attended, total: total, thresholdPct: threshold);

      setState(() {
        totalClasses = total;
        attendedClasses = attended;
        overallPercentage = overall;
        missable = canMissOverall > 0 ? canMissOverall : 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing PDF: $e')),
      );
    }
  }

  int classesYouCanSkip({
    required int attended,
    required int total,
    required double thresholdPct,
  }) {
    final p = thresholdPct / 100.0;
    if (total <= 0 || p <= 0) return 0;
    final k = (attended / p - total).floor();
    return k > 0 ? k : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: overallPercentage == null
            ? Container(
                color: Colors.red,
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      color: Colors.white,
                      child: const Text(
                        'Attendance Calc',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: isLoading ? null : processPdf,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 40, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(isLoading
                                  ? 'Processing...'
                                  : 'Select Attendance PDF'),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () async {
                                final Uri url = Uri.parse(
                                    'https://sdc-sppap1.svkm.ac.in:50001/irj/portal');
                                try {
                                  await launchUrl(url,
                                      mode: LaunchMode.externalApplication);
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Could not open the link: $e')),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 40, vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Get PDF'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Opacity(
                      opacity: 0.7,
                      child: ElevatedButton.icon(
                        onPressed: _showGuide,
                        icon: const Icon(Icons.help_outline, size: 20),
                        label: const Text('Guide'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      color: Colors.black,
                      child: Text(
                        '© ${DateTime.now().year} Pranjal Pathak',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            if (studentName != null && studentName!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Hello, ${studentName!.split(' ').first}!',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo[700],
                                  ),
                                ),
                              ),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                const Text(
                                  'Classes Attended:',
                                  style: TextStyle(fontSize: 18),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.green, width: 2),
                                  ),
                                  child: Text(
                                    '$attendedClasses',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[900],
                                    ),
                                  ),
                                ),
                                const Text(
                                  '/',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                const Text(
                                  'Classes Occurred:',
                                  style: TextStyle(fontSize: 18),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.blue, width: 2),
                                  ),
                                  child: Text(
                                    '$totalClasses',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[900],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Overall: ${overallPercentage!.toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: overallPercentage! >= threshold
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 10),
                            LinearPercentIndicator(
                              lineHeight: 10,
                              percent:
                                  (overallPercentage! / 100).clamp(0.0, 1.0),
                              backgroundColor: Colors.grey[300],
                              progressColor: overallPercentage! >= threshold
                                  ? Colors.green
                                  : Colors.red,
                              animation: true,
                            ),
                            const SizedBox(height: 12),
                            const Row(
                              children: [
                                Text('Target: 80%'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...subjectData.entries.map((entry) {
                      final details = entry.value;
                      final percentage = details['percentage'] as double;
                      final canMiss = details['canMiss'] as int;
                      final classesRemaining =
                          details['classesRemaining'] as int;
                      final types = details['types'] as List;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey[400]!, width: 2),
                        ),
                        elevation: 3,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          height: 2,
                                          width: double.infinity,
                                          color: Colors.grey[400],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    '${percentage.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: percentage >= threshold
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...types.map((type) {
                                final name = type['name'] as String;
                                final attended = type['attended'] as int;
                                final total = type['total'] as int;

                                return Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$name: Attended [ $attended ] out of [ $total ]',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                );
                              }),
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.green[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green, width: 1),
                                ),
                                child: Text(
                                  'You can miss: $canMiss classes',
                                  style: TextStyle(
                                    color: Colors.green[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.blue, width: 1),
                                ),
                                child: Text(
                                  'Classes Remaining: $classesRemaining',
                                  style: TextStyle(
                                    color: Colors.blue[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              setState(() {
                                fileName = null;
                                overallPercentage = null;
                                totalClasses = null;
                                attendedClasses = null;
                                missable = null;
                                subjectData.clear();
                              });
                              await processPdf();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                          isLoading ? 'Processing...' : 'Upload Another PDF'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Guide Dialog Widget
class GuideDialog extends StatefulWidget {
  const GuideDialog({super.key});

  @override
  State<GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<GuideDialog> {
  int currentStep = 0;
  final List<String> guideImages = [
    'assets/guide/step1.png',
    'assets/guide/step2.png',
    'assets/guide/step3.png',
  ];

  void _nextStep() {
    if (currentStep < guideImages.length - 1) {
      setState(() {
        currentStep++;
      });
    }
  }

  void _previousStep() {
    if (currentStep > 0) {
      setState(() {
        currentStep--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Step ${currentStep + 1} of ${guideImages.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Image
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: InteractiveViewer(
                  child: Image.asset(
                    guideImages[currentStep],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image_not_supported,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Image not found.\nPlease add guide images to assets/guide/\n(step1.png, step2.png, step3.png)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: currentStep > 0 ? _previousStep : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        currentStep < guideImages.length - 1 ? _nextStep : null,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter for diagonal animated lines
class DiagonalLinesPainter extends CustomPainter {
  final double progress;
  DiagonalLinesPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.3)
      ..strokeWidth = 2;

    const double spacing = 40;
    final double offset = progress * spacing * 2;

    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i + offset, 0),
        Offset(i - size.height + offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DiagonalLinesPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:percent_indicator/percent_indicator.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance Tracker',
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
  State<AttendanceHome> createState() => _AttendanceHomeState();
}

class _AttendanceHomeState extends State<AttendanceHome>
    with SingleTickerProviderStateMixin {
  String? fileName;
  double threshold = 80.0;
  bool isLoading = false;
  double? overallPercentage;
  int? totalClasses, attendedClasses, missable;
  Map<String, List<String>> subjectData = {};

  late AnimationController _controller;

  /// Fixed totals for missable calculation
  final Map<String, int> fixedTotals = {
    "Calculus": 60,
    "Physics": 75,
    "Computational Thinking for Problem Solving": 75,
    "Elements of Biology": 45,
    "Engineering Graphics and Design": 45,
    "Engineering Ethics": 15,
    "Indian Knowledge System": 15,
    "Environmental Studies": 15,
    "Essential Electronic Practices": 30,
  };

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
    String subject = raw.replaceAll(RegExp(r'(T4|P4|U4|C1|CE|Sem I|Div C|Batch \\d+)', caseSensitive: false), '').trim();

    if (subject.toUpperCase().contains("COMPUTATIONAL THINKING")) {
      return "Computational Thinking for Problem Solving";
    } else if (subject.toUpperCase().contains("BIOLOGY")) {
      return "Elements of Biology";
    } else if (subject.toUpperCase().contains("GRAPHICS")) {
      return "Engineering Graphics and Design";
    } else if (subject.toUpperCase().contains("ELECTRONIC")) {
      return "Essential Electronic Practices";
    } else if (subject.toUpperCase().contains("ENGINEERING ETHICS")) {
      return "Engineering Ethics";
    } else if (subject.toUpperCase().contains("INDIAN KNOWLEDGE")) {
      return "Indian Knowledge System";
    } else if (subject.toUpperCase().contains("ENVIRONMENTAL")) {
      return "Environmental Studies";
    } else if (subject.toUpperCase().contains("PHYSICS")) {
      return "Physics";
    } else if (subject.toUpperCase().contains("CALCULUS")) {
      return "Calculus";
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

        final PdfDocument document =
            PdfDocument(inputBytes: result.files.single.bytes!);
        String text = PdfTextExtractor(document).extractText();
        document.dispose();

        text = text.replaceAll('\n', ' ');
        final rowPattern = RegExp(
          r'([A-Z ]+.*?)\s+(Jul|Aug|Sep|Oct)\s+\d{1,2},\s+2025\s+\d{1,2}:\d{2}:\d{2}\s[AP]M\s+\d{1,2}:\d{2}:\d{2}\s[AP]M\s+(P|A)',
          caseSensitive: false,
        );

        Map<String, Map<String, Map<String, int>>> counts = {};

        for (final match in rowPattern.allMatches(text)) {
          String rawSubject = match.group(1)!.trim();
          String status = match.group(3)!;

          String subject = normalizeSubject(rawSubject);

          String type;
          if (rawSubject.contains('U4')) {
            type = 'Tutorial';
          } else if (rawSubject.contains('P4') || rawSubject.contains('Batch')) {
            type = 'Practical';
          } else {
            type = 'Theory';
          }

          counts.putIfAbsent(subject, () => {
                'Theory': {'T': 0, 'P': 0},
                'Tutorial': {'T': 0, 'P': 0},
                'Practical': {'T': 0, 'P': 0},
              });

          counts[subject]![type]!['T'] = counts[subject]![type]!['T']! + 1;
          if (status == 'P') {
            counts[subject]![type]!['P'] = counts[subject]![type]!['P']! + 1;
          }
        }

        subjectData.clear();
        int total = 0, attended = 0;
        counts.forEach((subject, data) {
          int subTotal = data.values.map((e) => e['T']!).reduce((a, b) => a + b);
          int subAttended = data.values.map((e) => e['P']!).reduce((a, b) => a + b);
          total += subTotal;
          attended += subAttended;

          int fixedTotal = fixedTotals[subject] ?? subTotal;
          int allowedAbsences = (0.2 * fixedTotal).floor();
          int missed = subTotal - subAttended;
          int canMiss = allowedAbsences - missed;
          if (canMiss < 0) canMiss = 0;

          int classesRemaining = fixedTotal - subTotal;
          if (classesRemaining < 0) classesRemaining = 0;

          List<String> details = [];

          if (!(data['Theory']!['T'] == 0 && data['Theory']!['P'] == 0)) {
            details.add('Theory: ${data['Theory']!['P']}/${data['Theory']!['T']}');
          }
          if (!(data['Tutorial']!['T'] == 0 && data['Tutorial']!['P'] == 0)) {
            details.add('Tutorial: ${data['Tutorial']!['P']}/${data['Tutorial']!['T']}');
          }
          if (!(data['Practical']!['T'] == 0 && data['Practical']!['P'] == 0)) {
            details.add('Practical: ${data['Practical']!['P']}/${data['Practical']!['T']}');
          }

          details.add('Total: $subAttended/$subTotal');
          details.add('You can miss: $canMiss classes');
          details.add('Classes Remaining: $classesRemaining');

          subjectData[subject] = details;
        });

        double overall = (attended / total) * 100;
        int canMissOverall = ((attended / (threshold / 100)) - total).floor();

        setState(() {
          totalClasses = total;
          attendedClasses = attended;
          overallPercentage = overall;
          missable = canMissOverall > 0 ? canMissOverall : 0;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading PDF: $e')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: overallPercentage == null
            ? Stack(
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: DiagonalLinesPainter(_controller.value),
                        child: Container(color: Colors.blue[700]),
                      );
                    },
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Attendance Tracker',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: isLoading ? null : processPdf,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.blue[700],
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(isLoading ? 'Processing...' : 'Select Attendance PDF'),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Text(
                              'Overall Attendance: ${overallPercentage!.toStringAsFixed(2)}%',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            LinearPercentIndicator(
                              lineHeight: 10,
                              percent: overallPercentage!.clamp(0, 100) / 100,
                              backgroundColor: Colors.grey[300],
                              progressColor: overallPercentage! >= threshold ? Colors.green : Colors.red,
                              animation: true,
                            ),
                            const SizedBox(height: 12),
                            Text('Total Classes: $totalClasses'),
                            Text('Attended: $attendedClasses'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: subjectData.entries.map((entry) {
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 3,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  ...entry.value.map((line) {
                                    if (line.startsWith('You can miss')) {
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green, width: 1),
                                        ),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            color: Colors.green[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    } else if (line.startsWith('Classes Remaining')) {
                                      return Container(
                                        margin: const EdgeInsets.only(top: 8),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue[50],
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.blue, width: 1),
                                        ),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            color: Colors.blue[800],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    } else {
                                      return Text(line);
                                    }
                                  }),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: isLoading ? null : processPdf,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(isLoading ? 'Processing...' : 'Upload Another PDF'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class DiagonalLinesPainter extends CustomPainter {
  final double progress;
  DiagonalLinesPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.lightBlueAccent.withOpacity(0.3)
      ..strokeWidth = 2;

    double spacing = 40;
    double offset = progress * spacing * 2;

    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(
        Offset(i + offset, 0),
        Offset(i - size.height + offset, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
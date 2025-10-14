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

class _AttendanceHomeState extends State<AttendanceHome> {
  String? fileName;
  double threshold = 80.0;
  bool isLoading = false;
  double? overallPercentage;
  int? totalClasses, attendedClasses, missable;
  Map<String, List<String>> subjectData = {};

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
        final pdfBytes = result.files.single.bytes!;

        // ✅ Load and extract text using Syncfusion
        final document = PdfDocument(inputBytes: pdfBytes);
        final extractedText = PdfTextExtractor(document).extractText();
        document.dispose();

        // ✅ Parse attendance data
        final RegExp entryPattern = RegExp(r'([A-Z ]{4,})[A-Z0-9 ]*?(P|A)\b');
        subjectData.clear();

        for (final match in entryPattern.allMatches(extractedText)) {
          final subject = match.group(1)!.trim();
          final status = match.group(2)!;
          subjectData.putIfAbsent(subject, () => []);
          subjectData[subject]!.add(status);
        }

        int total = 0, attended = 0;
        subjectData.forEach((subject, records) {
          int pres = records.where((s) => s == 'P').length;
          total += records.length;
          attended += pres;
        });

        double overall = (attended / total) * 100;
        int canMiss = ((attended / (threshold / 100)) - total).floor();

        setState(() {
          totalClasses = total;
          attendedClasses = attended;
          overallPercentage = overall;
          missable = canMiss > 0 ? canMiss : 0;
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
      appBar: AppBar(title: const Text('Attendance Tracker')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: isLoading ? null : processPdf,
              icon: const Icon(Icons.upload_file),
              label: Text(isLoading ? 'Processing...' : 'Upload Attendance PDF'),
            ),
            const SizedBox(height: 16),
            if (fileName != null) Text('Selected File: $fileName'),
            const SizedBox(height: 24),
            if (overallPercentage != null) ...[
              Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Text(
                        'Overall Attendance: ${overallPercentage!.toStringAsFixed(2)}%',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      LinearPercentIndicator(
                        lineHeight: 10,
                        percent: overallPercentage!.clamp(0, 100) / 100,
                        backgroundColor: Colors.grey[300],
                        progressColor: overallPercentage! >= threshold
                            ? Colors.green
                            : Colors.red,
                        animation: true,
                      ),
                      const SizedBox(height: 12),
                      Text('Total Classes: $totalClasses'),
                      Text('Attended: $attendedClasses'),
                      Text('Threshold: ${threshold.toStringAsFixed(0)}%'),
                      const Divider(height: 20, thickness: 1),
                      Text(
                        'You can miss $missable more classes while staying above $threshold%.',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (subjectData.isNotEmpty)
              Expanded(
                child: ListView(
                  children: subjectData.entries.map((entry) {
                    int p = entry.value.where((e) => e == 'P').length;
                    int total = entry.value.length;
                    double percent = (p / total) * 100;
                    return Card(
                      child: ListTile(
                        title: Text(entry.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LinearPercentIndicator(
                              lineHeight: 8,
                              percent: percent.clamp(0, 100) / 100,
                              progressColor: percent >= threshold
                                  ? Colors.green
                                  : Colors.red,
                              backgroundColor: Colors.grey[300],
                              animation: true,
                            ),
                            const SizedBox(height: 6),
                            Text('${p}/$total  |  ${percent.toStringAsFixed(1)}%'),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

# Attendance Calc

**Attendance Calc** is a Flutter application designed for SVKM NMIMS students to parse, calculate, and analyze class attendance directly from portal PDF reports.

---

## 🌟 Features

- 📄 **PDF Report Parser**: Parses attendance reports downloaded from the SVKM NMIMS SAP student portal.
- 👤 **Student Recognition**: Automatically extracts and displays the student's name from the PDF header.
- 📊 **Overall & Subject-wise Dashboard**:
  - Displays total classes attended vs. total classes occurred.
  - Calculates overall attendance percentage with visual progress indicator against an **80% target threshold**.
  - Detailed breakdown for each subject, categorized by **Theory**, **Practical**, and **Tutorial** components.
- 🎯 **Smart Bunking & Remaining Classes Calculator**:
  - **Classes You Can Miss**: Calculates the number of upcoming classes you can miss for each subject (and overall) while staying above the mandatory 80% threshold.
  - **Classes Remaining**: Estimates remaining semester classes based on curriculum loads.
- 🔄 **Subject Name Normalization**: Cleans portal labels, batch tags, and normalizes course names (e.g., DSA, DSA Lab, Discrete Mathematics, Probability & Statistics, Signals & Systems, COA, PEM, Python, Technical Communication).
- 🧭 **In-App Step-by-Step Guide**: Includes a visual modal guide demonstrating how to download the required PDF from the portal.
- 🔗 **Direct Portal Access**: Features a **"Get PDF"** button that opens the SVKM NMIMS SAP portal in an external browser.

---

## 🚀 How to Use

1. **Download your Attendance PDF**:
   - Open the app and tap **"Get PDF"** (or open `https://sdc-sppap1.svkm.ac.in:50001/irj/portal` in your browser).
   - Log in to the SVKM NMIMS SAP portal.
   - Navigate to **Attendance Display for Students**, set the end date to today's date, submit, and download the report as a PDF.
   - *(Tip: Tap **"Guide"** on the home screen to view visual step-by-step instructions).*

2. **Upload & Calculate**:
   - Tap **"Select Attendance PDF"** on the landing screen.
   - Select the downloaded attendance PDF using the file picker.
   - The app instantly processes the PDF and displays your complete attendance stats!

3. **Re-upload**:
   - Tap **"Upload Another PDF"** to load a newly downloaded attendance report anytime.

---

## ⚙️ How It Works (Technical Overview)

- **In-Memory PDF Extraction**: Uses `syncfusion_flutter_pdf` to extract raw text content from the selected PDF in memory without storing files on disk.
- **Regex Parsing**: Searches for class attendance rows matching course names, dates (`MMM dd, yyyy`), class timings, and status tags (`P`, `PRESENT`, `PRE` vs `A`, `ABSENT`, skipping `NU` / `NOT UPDATED`).
- **Lecture Type Classification**: Identifies lecture types (`Theory`, `Practical`, `Tutorial`) based on tags (`P4`, `U4`, `LAB`, `BATCH`).
- **Subject Normalization**: Strips batch/semester/division clutter (`Sem I`, `Div C`, `T4`, `C1`, etc.) and maps variations to standard course titles.
- **Calculations**:
  - **Overall Percentage**: \(\frac{\text{Total Attended}}{\text{Total Occurred}} \times 100\)
  - **Missable Classes Formula**: \(\max\left(0, \lfloor \frac{\text{Attended}}{0.80} - \text{Total} \rfloor\right)\) or subject-level allowed absences calculated against total semester load.

---

## 🛠️ Project Structure & Tech Stack

- **Framework**: [Flutter](https://flutter.dev/) (Material 3)
- **Language**: Dart
- **Key Packages**:
  - `file_picker`: Custom file picker for PDF selection.
  - `syncfusion_flutter_pdf`: PDF text extraction.
  - `percent_indicator`: Linear progress indicators for target visualization.
  - `url_launcher`: Launching SVKM NMIMS SAP Portal in browser.

```
Attendance_Calc_App-3.0/
├── assets/
│   ├── app_icon.png
│   └── guide/                # Step-by-step visual guide images
│       ├── step1.png
│       ├── step2.png
│       └── step3.png
├── lib/
│   └── main.dart             # Core application logic, parser, and UI
├── pubspec.yaml              # Dependencies and asset declarations
└── test/
    └── widget_test.dart      # Flutter widget smoke tests
```

---

## 💻 Setup & Development

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.0.0)

### Running Locally
```bash
# Clone the repository
git clone https://github.com/Pranjal551/Attendance_Calc_App.git

# Navigate to the project directory
cd Attendance_Calc_App-3.0

# Install dependencies
flutter pub get

# Launch the app
flutter run
```

---

## 🧪 Testing

Run widget tests to verify app startup and UI rendering:
```bash
flutter test
```

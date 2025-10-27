import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/schedule.dart';
import '../../models/free_day.dart';
import '../utils/firebase_manager.dart';

/// Service for generating and sharing PDF documents for schedules
class PdfService {
  // Cached font and logo data
  Uint8List? _oswaldRegularData;
  Uint8List? _oswaldBoldData;
  Uint8List? _logoData;

  // Modern, professional color palette
  static final PdfColor primaryColor = PdfColor.fromHex('#3366C2');
  static final PdfColor accentColor =
      PdfColor.fromHex('#D81B60'); // Bright blue
  static final PdfColor successColor = PdfColor.fromHex('#059669'); // Green
  static final PdfColor warningColor = PdfColor.fromHex('#d97706'); // Amber
  static final PdfColor errorColor = PdfColor.fromHex('#dc2626'); // Red
  static final PdfColor neutralDark =
      PdfColor.fromHex('#0f172a'); // Almost black
  static final PdfColor neutralMedium = PdfColor.fromHex('#64748b'); // Slate
  static final PdfColor neutralLight =
      PdfColor.fromHex('#cbd5e1'); // Light slate
  static final PdfColor backgroundPrimary =
      PdfColor.fromHex('#ffffff'); // White
  static final PdfColor backgroundSecondary =
      PdfColor.fromHex('#f8fafc'); // Off-white
  static final PdfColor borderColor =
      PdfColor.fromHex('#e2e8f0'); // Subtle border

  static const int _calendarCellHeight = 75;
  static const int _maxAssignmentsPerCell = 3;
  static const int _pdfCleanupDelaySeconds = 5;

  /// Generates a PDF for the schedule and shares it
  Future<void> generateAndShareSchedulePdf(Schedule schedule) async {
    _validateSchedule(schedule);

    await _loadFonts();
    final logoImage = await _getAppLogo();
    final participants = await _fetchParticipantsWithDetails(schedule.id);

    final pdf = _createPdfDocument();
    final file = await _generatePdfFile(schedule, participants, logoImage, pdf);

    await _sharePdfFile(file, schedule);
    _scheduleFileCleanup(file);
  }

  // ============================================================================
  // Asset Loading
  // ============================================================================

  Future<void> _loadFonts() async {
    if (_oswaldRegularData != null && _oswaldBoldData != null) return;

    _oswaldRegularData = await rootBundle
        .load('assets/fonts/Oswald-Regular.ttf')
        .then((data) => data.buffer.asUint8List());

    _oswaldBoldData = await rootBundle
        .load('assets/fonts/Oswald-Bold.ttf')
        .then((data) => data.buffer.asUint8List());
  }

  Future<Uint8List> _getAppLogo() async {
    _logoData ??= await rootBundle
        .load('assets/schedulo.png')
        .then((data) => data.buffer.asUint8List());
    return _logoData!;
  }

  // ============================================================================
  // PDF Generation
  // ============================================================================

  void _validateSchedule(Schedule schedule) {
    if (!schedule.isFullySet) {
      throw Exception('Schedule must be fully set to export as PDF');
    }
  }

  pw.Document _createPdfDocument() {
    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(ByteData.sublistView(_oswaldRegularData!)),
        bold: pw.Font.ttf(ByteData.sublistView(_oswaldBoldData!)),
      ),
    );
  }

  Future<File> _generatePdfFile(
    Schedule schedule,
    List<Map<String, dynamic>> participants,
    Uint8List logoImage,
    pw.Document pdf,
  ) async {
    final startDate = schedule.startDate;
    final endDate = _getScheduleEndDate(schedule);
    final monthGroups = _groupDatesByMonth(startDate, endDate);
    final dayAssignments = _buildDayAssignmentsMap(participants);

    // Add cover page
    pdf.addPage(_buildCoverPage(logoImage, schedule, participants));

    // Add calendar pages
    _addCalendarPages(pdf, logoImage, schedule, monthGroups, dayAssignments);

    // Add team assignments page
    pdf.addPage(_buildTeamAssignmentsPage(logoImage, schedule, participants));

    // Save to file
    return await _savePdfToFile(pdf, schedule);
  }

  Future<File> _savePdfToFile(pw.Document pdf, Schedule schedule) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = _generateFileName(schedule);
    final filePath = '${tempDir.path}/$fileName';

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  String _generateFileName(Schedule schedule) {
    final sanitizedName = schedule.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .toLowerCase();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${sanitizedName}_$timestamp.pdf';
  }

  Future<void> _sharePdfFile(File file, Schedule schedule) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Schedule: ${schedule.name}',
        text: 'Here is the schedule PDF for ${schedule.name}',
      ),
    );
  }

  void _scheduleFileCleanup(File file) {
    Future.delayed(const Duration(seconds: _pdfCleanupDelaySeconds), () {
      try {
        if (file.existsSync()) {
          file.delete();
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    });
  }

  // ============================================================================
  // Page Builders
  // ============================================================================

  pw.Page _buildCoverPage(
    Uint8List logoImage,
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Stack(
        children: [
          // Background gradient effect
          pw.Positioned.fill(
            child: pw.Container(
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  begin: pw.Alignment.topLeft,
                  end: pw.Alignment.bottomRight,
                  colors: [
                    backgroundPrimary,
                    backgroundSecondary,
                  ],
                ),
              ),
            ),
          ),
          // Content
          pw.Padding(
            padding: const pw.EdgeInsets.all(48),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildModernHeader(logoImage),
                pw.SizedBox(height: 60),
                _buildHeroTitle(schedule),
                pw.SizedBox(height: 40),
                _buildInfoCards(schedule, participants),
                pw.Spacer(),
                _buildModernFooter(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addCalendarPages(
    pw.Document pdf,
    Uint8List logoImage,
    Schedule schedule,
    Map<DateTime, List<DateTime>> monthGroups,
    Map<String, List<Map<String, dynamic>>> dayAssignments,
  ) {
    final monthEntries = monthGroups.entries.toList();

    for (int i = 0; i < monthEntries.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildSimplePageHeader(logoImage, schedule.name),
              pw.SizedBox(height: 32),
              _buildMonthCalendar(
                monthEntries[i].key,
                monthEntries[i].value,
                dayAssignments,
              ),
              pw.Spacer(),
              _buildPageNumber(i + 2, monthEntries.length + 2),
            ],
          ),
        ),
      );
    }
  }

  pw.Page _buildTeamAssignmentsPage(
    Uint8List logoImage,
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildSimplePageHeader(logoImage, schedule.name),
          pw.SizedBox(height: 32),
          _buildSectionHeader('Team Schedule'),
          pw.SizedBox(height: 24),
          ...participants.map((p) => _buildParticipantCard(p)),
          pw.Spacer(),
          _buildPageNumber(
            participants.length + 2,
            participants.length + 2,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Widget Builders - Modern Header & Footer
  // ============================================================================

  pw.Widget _buildModernHeader(Uint8List logoImage) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Row(
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: primaryColor,
                borderRadius: pw.BorderRadius.circular(12),
                boxShadow: [
                  pw.BoxShadow(
                    color: primaryColor.shade(0.3),
                    blurRadius: 8,
                    offset: const PdfPoint(0, 4),
                  ),
                ],
              ),
              child: pw.Image(
                pw.MemoryImage(logoImage),
                height: 32,
                width: 32,
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Schedulo',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: neutralDark,
                    letterSpacing: -0.5,
                  ),
                ),
                pw.Text(
                  'Schedule Report',
                  style: pw.TextStyle(
                    fontSize: 11,
                    color: neutralMedium,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildSimplePageHeader(Uint8List logoImage, String scheduleName) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: borderColor, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Image(
                  pw.MemoryImage(logoImage),
                  height: 20,
                  width: 20,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                'Schedulo',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: neutralDark,
                ),
              ),
            ],
          ),
          pw.Text(
            scheduleName,
            style: pw.TextStyle(
              fontSize: 12,
              color: neutralMedium,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildModernFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 20),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated on ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}',
            style: pw.TextStyle(
              fontSize: 9,
              color: neutralMedium,
            ),
          ),
          pw.Text(
            'Confidential',
            style: pw.TextStyle(
              fontSize: 9,
              color: neutralMedium,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPageNumber(int current, int total) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 16),
      child: pw.Center(
        child: pw.Text(
          'Page $current of $total',
          style: pw.TextStyle(
            fontSize: 9,
            color: neutralMedium,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(left: 4, bottom: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: primaryColor, width: 4),
        ),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12),
        child: pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: neutralDark,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Widget Builders - Hero Section
  // ============================================================================

  pw.Widget _buildHeroTitle(Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(32),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [primaryColor, accentColor],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(16),
        boxShadow: [
          pw.BoxShadow(
            color: primaryColor.shade(0.3),
            blurRadius: 20,
            offset: const PdfPoint(0, 8),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            schedule.name.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 32,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              letterSpacing: 1,
            ),
          ),
          if (schedule.description != null &&
              schedule.description!.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.only(left: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(
                      color: PdfColors.white.shade(0.5), width: 3),
                ),
              ),
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12),
                child: pw.Text(
                  schedule.description!,
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.white.shade(0.2),
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildInfoCards(
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: _buildInfoCard(
                'Duration',
                schedule.duration,
                warningColor,
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: _buildInfoCard(
                'Start Date',
                DateFormat('MMM dd, yyyy').format(schedule.startDate),
                accentColor,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            pw.Expanded(
              child: _buildInfoCard(
                'Team Members',
                '${participants.length} people',
                successColor,
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: _buildInfoCard(
                'Status',
                'Active',
                successColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildInfoCard(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: backgroundPrimary,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey.shade(0.1),
            blurRadius: 8,
            offset: const PdfPoint(0, 2),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              color: neutralMedium,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 24,
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Text(
                  value,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: neutralDark,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Widget Builders - Calendar
  // ============================================================================

  pw.Widget _buildMonthCalendar(
    DateTime month,
    List<DateTime> datesInMonth,
    Map<String, List<Map<String, dynamic>>> dayAssignments,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: backgroundPrimary,
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey.shade(0.1),
            blurRadius: 12,
            offset: const PdfPoint(0, 4),
          ),
        ],
      ),
      child: pw.Column(
        children: [
          _buildMonthHeader(month),
          _buildWeekdayHeader(),
          _buildMonthGrid(month, datesInMonth, dayAssignments),
        ],
      ),
    );
  }

  pw.Widget _buildMonthHeader(DateTime month) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 16),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [primaryColor, accentColor],
        ),
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(16),
          topRight: pw.Radius.circular(16),
        ),
      ),
      child: pw.Center(
        child: pw.Text(
          DateFormat('MMMM yyyy').format(month).toUpperCase(),
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  pw.Widget _buildWeekdayHeader() {
    const weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return pw.Container(
      color: backgroundSecondary,
      padding: const pw.EdgeInsets.symmetric(vertical: 12),
      child: pw.Row(
        children: weekdays
            .map((day) => pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      day,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: neutralMedium,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  pw.Widget _buildMonthGrid(
    DateTime month,
    List<DateTime> datesInMonth,
    Map<String, List<Map<String, dynamic>>> dayAssignments,
  ) {
    final rows = <pw.Widget>[];
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final lastDayOfMonth = DateTime(month.year, month.month + 1, 0);
    final startingWeekday = firstDayOfMonth.weekday;

    DateTime weekStart = firstDayOfMonth.subtract(
      Duration(days: startingWeekday - 1),
    );

    while (
        weekStart.isBefore(lastDayOfMonth) || weekStart.month == month.month) {
      rows.add(_buildWeekRow(weekStart, month, datesInMonth, dayAssignments));
      weekStart = weekStart.add(const Duration(days: 7));
    }

    return pw.Column(children: rows);
  }

  pw.Widget _buildWeekRow(
    DateTime weekStart,
    DateTime month,
    List<DateTime> datesInMonth,
    Map<String, List<Map<String, dynamic>>> dayAssignments,
  ) {
    final weekCells = <pw.Widget>[];

    for (int i = 0; i < 7; i++) {
      final currentDate = weekStart.add(Duration(days: i));
      final isCurrentMonth = currentDate.month == month.month;
      final isInSchedule = datesInMonth.any(
        (d) =>
            d.year == currentDate.year &&
            d.month == currentDate.month &&
            d.day == currentDate.day,
      );

      if (isCurrentMonth && isInSchedule) {
        final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);
        final assignments = dayAssignments[dateKey] ?? [];
        weekCells.add(_buildCalendarCell(currentDate, assignments));
      } else {
        weekCells.add(_buildEmptyCell(currentDate, isCurrentMonth));
      }
    }

    return pw.Row(
      children: weekCells.map((cell) => pw.Expanded(child: cell)).toList(),
    );
  }

  pw.Widget _buildCalendarCell(
    DateTime date,
    List<Map<String, dynamic>> assignments,
  ) {
    final isToday = date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year;

    return pw.Container(
      height: _calendarCellHeight.toDouble(),
      decoration: pw.BoxDecoration(
        color: assignments.isNotEmpty ? backgroundSecondary : backgroundPrimary,
        border: pw.Border.all(color: borderColor, width: 0.5),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: pw.BoxDecoration(
                color: isToday
                    ? errorColor
                    : (assignments.isNotEmpty ? primaryColor : neutralLight),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                '${date.day}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: isToday || assignments.isNotEmpty
                      ? PdfColors.white
                      : neutralMedium,
                ),
              ),
            ),
            if (assignments.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              ...assignments.take(_maxAssignmentsPerCell).map(
                    (assignment) => _buildAssignmentChip(assignment),
                  ),
              if (assignments.length > _maxAssignmentsPerCell)
                _buildMoreAssignmentsBadge(
                  assignments.length - _maxAssignmentsPerCell,
                ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _buildAssignmentChip(Map<String, dynamic> assignment) {
    final freeDay = assignment['freeDay'] as FreeDay;
    final username = assignment['username'].toString();
    final firstName = username.split(' ')[0];
    final color = assignment['color'] as PdfColor;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              firstName.length > 6
                  ? '${firstName.substring(0, 6)}..'
                  : firstName,
              style: pw.TextStyle(
                fontSize: 7,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
          ),
          pw.Text(
            '${freeDay.startTime.substring(0, 5)}-${freeDay.endTime.substring(0, 5)}',
            style: pw.TextStyle(
              fontSize: 6,
              color: PdfColors.white.shade(0.2),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildMoreAssignmentsBadge(int count) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: pw.BoxDecoration(
        color: neutralMedium,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        '+$count more',
        style: pw.TextStyle(
          fontSize: 6,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildEmptyCell(DateTime date, bool isCurrentMonth) {
    return pw.Container(
      height: _calendarCellHeight.toDouble(),
      decoration: pw.BoxDecoration(
        color: isCurrentMonth ? backgroundPrimary : backgroundSecondary,
        border: pw.Border.all(color: borderColor, width: 0.5),
      ),
      child: pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          isCurrentMonth ? '${date.day}' : '',
          style: pw.TextStyle(
            fontSize: 9,
            color: neutralLight,
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // Widget Builders - Team Assignments
  // ============================================================================

  pw.Widget _buildParticipantCard(Map<String, dynamic> participant) {
    final username = participant['username'] as String;
    final freeDays = participant['free_days'] as List<FreeDay>;
    final participantColor = _getParticipantColor(username);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        color: backgroundPrimary,
        border: pw.Border.all(color: borderColor, width: 1.5),
        borderRadius: pw.BorderRadius.circular(12),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey.shade(0.08),
            blurRadius: 8,
            offset: const PdfPoint(0, 2),
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildParticipantHeader(username, participantColor, freeDays.length),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            child: _buildParticipantFreeDays(freeDays, participantColor),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildParticipantHeader(
    String username,
    PdfColor color,
    int freeDaysCount,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: backgroundSecondary,
        borderRadius: const pw.BorderRadius.only(
          topLeft: pw.Radius.circular(12),
          topRight: pw.Radius.circular(12),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 12,
                height: 12,
                decoration: pw.BoxDecoration(
                  color: color,
                  shape: pw.BoxShape.circle,
                  boxShadow: [
                    pw.BoxShadow(
                      color: color.shade(0.4),
                      blurRadius: 4,
                      offset: const PdfPoint(0, 2),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                username,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: neutralDark,
                ),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 4,
            ),
            decoration: pw.BoxDecoration(
              color: color.shade(0.85),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              '$freeDaysCount ${freeDaysCount == 1 ? 'slot' : 'slots'}',
              style: pw.TextStyle(
                fontSize: 9,
                color: color,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildParticipantFreeDays(List<FreeDay> freeDays, PdfColor color) {
    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: freeDays.map((freeDay) {
        return pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(
            color: backgroundPrimary,
            border: pw.Border.all(color: color, width: 1.5),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: pw.BoxDecoration(
                  color: color,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  freeDay.day.substring(0, 3).toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                DateFormat('MMM dd').format(freeDay.date),
                style: pw.TextStyle(
                  fontSize: 9,
                  color: neutralDark,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '${freeDay.startTime.substring(0, 5)} - ${freeDay.endTime.substring(0, 5)}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: neutralMedium,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ============================================================================
  // Data Processing
  // ============================================================================

  Map<DateTime, List<DateTime>> _groupDatesByMonth(
    DateTime startDate,
    DateTime endDate,
  ) {
    final monthGroups = <DateTime, List<DateTime>>{};
    DateTime currentDate = startDate;

    while (currentDate.isBefore(endDate) ||
        currentDate.isAtSameMomentAs(endDate)) {
      final monthKey = DateTime(currentDate.year, currentDate.month, 1);
      monthGroups.putIfAbsent(monthKey, () => []);
      monthGroups[monthKey]!.add(currentDate);
      currentDate = currentDate.add(const Duration(days: 1));
    }

    return monthGroups;
  }

  Map<String, List<Map<String, dynamic>>> _buildDayAssignmentsMap(
    List<Map<String, dynamic>> participants,
  ) {
    final Map<String, List<Map<String, dynamic>>> dayAssignments = {};

    for (var participant in participants) {
      final freeDays = participant['free_days'] as List<FreeDay>;
      for (var freeDay in freeDays) {
        final dateKey = DateFormat('yyyy-MM-dd').format(freeDay.date);
        dayAssignments.putIfAbsent(dateKey, () => []);
        dayAssignments[dateKey]!.add({
          'username': participant['username'],
          'freeDay': freeDay,
          'color': _getParticipantColor(participant['username']),
        });
      }
    }

    return dayAssignments;
  }

  DateTime _getScheduleEndDate(Schedule schedule) {
    final weeks = _parseDurationToWeeks(schedule.duration);
    return schedule.startDate.add(Duration(days: weeks * 7));
  }

  int _parseDurationToWeeks(String duration) {
    switch (duration) {
      case '1 week':
        return 1;
      case '2 weeks':
        return 2;
      case '3 weeks':
        return 3;
      case '1 month':
        return 4;
      case '2 months':
        return 8;
      case '3 months':
        return 12;
      case '6 months':
        return 26;
      default:
        return int.tryParse(duration.split(' ')[0]) ?? 1;
    }
  }

  // ============================================================================
  // Utilities
  // ============================================================================

  PdfColor _getParticipantColor(String username) {
    const colors = [
      '#3b82f6', // Blue
      '#8b5cf6', // Purple
      '#ec4899', // Pink
      '#f59e0b', // Amber
      '#10b981', // Emerald
      '#06b6d4', // Cyan
      '#f97316', // Orange
      '#6366f1', // Indigo
    ];

    final index = username.hashCode.abs() % colors.length;
    return PdfColor.fromHex(colors[index]);
  }

  Future<List<Map<String, dynamic>>> _fetchParticipantsWithDetails(
    String scheduleId,
  ) async {
    try {
      final participantDocs = await FirebaseManager.firestore
          .collection('participants')
          .where('schedule_id', isEqualTo: scheduleId)
          .get();

      final List<Map<String, dynamic>> participantsWithDetails = [];

      for (var doc in participantDocs.docs) {
        final data = doc.data();
        final userId = data['user_id'] as String;
        final freeDaysData = data['free_days'] as List?;

        if (freeDaysData == null || freeDaysData.isEmpty) continue;

        final userDoc = await FirebaseManager.firestore
            .collection('users')
            .doc(userId)
            .get();

        final username = userDoc.data()?['username'] ?? 'Unknown User';
        final freeDays = freeDaysData
            .map((d) => FreeDay.fromJson(d as Map<String, dynamic>))
            .toList();

        participantsWithDetails.add({
          'username': username,
          'free_days': freeDays,
        });
      }

      return participantsWithDetails;
    } catch (e) {
      return [];
    }
  }
}

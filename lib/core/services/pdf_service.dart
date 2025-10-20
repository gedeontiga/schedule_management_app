import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/schedule.dart';
import '../../models/free_day.dart';
import '../utils/firebase_manager.dart';

class PdfService {
  Uint8List? _oswaldRegularData;
  Uint8List? _oswaldBoldData;
  Uint8List? _logoData;

  /// Color palette inspired by the calendar images
  static final PdfColor primaryBlue = PdfColor.fromHex('#4A90E2');
  static final PdfColor accentOrange = PdfColor.fromHex('#FF9500');
  static final PdfColor accentRed = PdfColor.fromHex('#FF3B30');
  static final PdfColor accentPurple = PdfColor.fromHex('#9B59B6');
  static final PdfColor lightBackground = PdfColor.fromHex('#F8F9FA');
  static final PdfColor darkGray = PdfColor.fromHex('#2C3E50');
  static final PdfColor mediumGray = PdfColor.fromHex('#7F8C8D');
  static final PdfColor headerGray = PdfColor.fromHex('#495057');
  static final PdfColor calendarBorder = PdfColor.fromHex('#DEE2E6');

  /// Load custom fonts
  Future<void> _loadFonts() async {
    if (_oswaldRegularData == null || _oswaldBoldData == null) {
      _oswaldRegularData = await rootBundle
          .load('assets/fonts/Oswald-Regular.ttf')
          .then((data) => data.buffer.asUint8List());

      _oswaldBoldData = await rootBundle
          .load('assets/fonts/Oswald-Bold.ttf')
          .then((data) => data.buffer.asUint8List());
    }
  }

  /// Load app logo
  Future<Uint8List> _getAppLogo() async {
    _logoData ??= await rootBundle
        .load('assets/schedulo.png')
        .then((data) => data.buffer.asUint8List());
    return _logoData!;
  }

  /// Get download directory
  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission required');
      }
      final dir = await getExternalStorageDirectory();
      final appDir = Directory('${dir!.path}/SchedulerPDFs');
      if (!await appDir.exists()) await appDir.create(recursive: true);
      return appDir;
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/SchedulerPDFs');
      if (!await appDir.exists()) await appDir.create(recursive: true);
      return appDir;
    }
    return await getTemporaryDirectory();
  }

  /// Generate enhanced PDF schedule
  Future<File> generateSchedulePdf(Schedule schedule) async {
    if (!schedule.isFullySet) {
      throw Exception('Schedule must be fully set to export as PDF');
    }

    await _loadFonts();
    final logoImage = await _getAppLogo();
    final downloadDir = await _getDownloadDirectory();

    final sanitizedName = schedule.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .toLowerCase();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${downloadDir.path}/${sanitizedName}_$timestamp.pdf';

    // Fetch participants with user details
    final participants = await _fetchParticipantsWithDetails(schedule.id);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(ByteData.sublistView(_oswaldRegularData!)),
        bold: pw.Font.ttf(ByteData.sublistView(_oswaldBoldData!)),
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => _buildHeader(logoImage, schedule),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildTitleSection(schedule),
          pw.SizedBox(height: 20),
          _buildScheduleDetails(schedule),
          pw.SizedBox(height: 30),
          _buildCalendarView(schedule, participants),
          pw.SizedBox(height: 30),
          _buildParticipantDetails(participants),
        ],
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// Build PDF header
  pw.Widget _buildHeader(Uint8List logoImage, Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: primaryBlue, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Image(pw.MemoryImage(logoImage), height: 40),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'SCHEDULER',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: primaryBlue,
                ),
              ),
              pw.Text(
                'Interpretation Planning',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: mediumGray,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build PDF footer
  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: calendarBorder),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 8, color: mediumGray),
          ),
          pw.Text(
            'Page ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: mediumGray),
          ),
        ],
      ),
    );
  }

  /// Build title section
  pw.Widget _buildTitleSection(Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [primaryBlue, PdfColor.fromHex('#357ABD')],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            schedule.name,
            style: pw.TextStyle(
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          if (schedule.description != null && schedule.description!.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                schedule.description!,
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build schedule details section
  pw.Widget _buildScheduleDetails(Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: lightBackground,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: calendarBorder),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _buildDetailItem(
            'Duration',
            schedule.duration,
            accentOrange,
          ),
          _buildDetailItem(
            'Start Date',
            DateFormat('MMM dd, yyyy').format(schedule.startDate),
            accentPurple,
          ),
          _buildDetailItem(
            'Created',
            DateFormat('MMM dd, yyyy').format(schedule.createdAt),
            accentRed,
          ),
          _buildDetailItem(
            'Status',
            schedule.isFullySet ? 'Fully Set' : 'In Progress',
            schedule.isFullySet ? PdfColors.green : accentOrange,
          ),
        ],
      ),
    );
  }

  /// Build detail item
  pw.Widget _buildDetailItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            color: mediumGray,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// Build calendar view
  pw.Widget _buildCalendarView(
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Text(
            'Schedule Calendar',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: darkGray,
            ),
          ),
        ),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: calendarBorder, width: 1.5),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: _buildCalendarGrid(schedule, participants),
        ),
      ],
    );
  }

  /// Build calendar grid
  pw.Widget _buildCalendarGrid(
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    // Group free days by date
    final Map<String, List<Map<String, dynamic>>> dayAssignments = {};

    for (var participant in participants) {
      final freeDays = participant['free_days'] as List<FreeDay>;
      for (var freeDay in freeDays) {
        final dateKey = DateFormat('yyyy-MM-dd').format(freeDay.date);
        dayAssignments.putIfAbsent(dateKey, () => []);
        dayAssignments[dateKey]!.add({
          'username': participant['username'],
          'freeDay': freeDay,
        });
      }
    }

    // Build calendar rows
    final rows = <pw.TableRow>[];

    // Header row
    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: headerGray),
        children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .map((day) => pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    day,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ))
            .toList(),
      ),
    );

    // Calculate calendar dates
    final startDate = schedule.startDate;
    final firstDay = startDate.subtract(Duration(days: startDate.weekday - 1));

    DateTime currentDate = firstDay;
    while (currentDate.isBefore(startDate.add(const Duration(days: 35)))) {
      final weekCells = <pw.Widget>[];

      for (int i = 0; i < 7; i++) {
        final dateKey = DateFormat('yyyy-MM-dd').format(currentDate);
        final assignments = dayAssignments[dateKey] ?? [];

        weekCells.add(_buildCalendarCell(currentDate, assignments, schedule));
        currentDate = currentDate.add(const Duration(days: 1));
      }

      rows.add(pw.TableRow(children: weekCells));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: calendarBorder, width: 0.5),
      children: rows,
    );
  }

  /// Build calendar cell
  pw.Widget _buildCalendarCell(
    DateTime date,
    List<Map<String, dynamic>> assignments,
    Schedule schedule,
  ) {
    final isToday = date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year;

    final isBeforeStart = date.isBefore(schedule.startDate);

    return pw.Container(
      height: 60,
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        color: isToday
            ? PdfColor.fromHex('#E3F2FD')
            : isBeforeStart
                ? PdfColor.fromHex('#F5F5F5')
                : PdfColors.white,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${date.day}',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: isToday ? pw.FontWeight.bold : null,
              color: isBeforeStart ? mediumGray : darkGray,
            ),
          ),
          if (assignments.isNotEmpty)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: assignments.take(2).map((assignment) {
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(top: 2),
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 3, vertical: 1),
                    decoration: pw.BoxDecoration(
                      color: _getParticipantColor(assignment['username']),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      assignment['username'].toString().split(' ')[0],
                      style: pw.TextStyle(
                        fontSize: 6,
                        color: PdfColors.white,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  );
                }).toList(),
              ),
            ),
          if (assignments.length > 2)
            pw.Text(
              '+${assignments.length - 2}',
              style: pw.TextStyle(fontSize: 6, color: mediumGray),
            ),
        ],
      ),
    );
  }

  /// Build participant details section
  pw.Widget _buildParticipantDetails(List<Map<String, dynamic>> participants) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Text(
            'Participant Assignments',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: darkGray,
            ),
          ),
        ),
        ...participants
            .map((participant) => _buildParticipantCard(participant)),
      ],
    );
  }

  /// Build participant card
  pw.Widget _buildParticipantCard(Map<String, dynamic> participant) {
    final username = participant['username'] as String;
    final roles = participant['roles'] as String;
    final freeDays = participant['free_days'] as List<FreeDay>;

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: calendarBorder, width: 1.5),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          // Header
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _getParticipantColor(username),
              borderRadius: const pw.BorderRadius.only(
                topLeft: pw.Radius.circular(8),
                topRight: pw.Radius.circular(8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  username,
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                if (roles.isNotEmpty)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFFFFF).shade(0.3),
                      borderRadius: pw.BorderRadius.circular(12),
                    ),
                    child: pw.Text(
                      roles,
                      style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Assignments
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            child: pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: freeDays.map((freeDay) {
                return _buildAssignmentChip(freeDay);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Build assignment chip
  pw.Widget _buildAssignmentChip(FreeDay freeDay) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: lightBackground,
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: primaryBlue, width: 1),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 6,
            height: 6,
            decoration: pw.BoxDecoration(
              color: accentOrange,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${freeDay.day}, ${DateFormat('MMM dd').format(freeDay.date)}',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: darkGray,
                ),
              ),
              pw.Text(
                '${freeDay.startTime} - ${freeDay.endTime}',
                style: pw.TextStyle(
                  fontSize: 8,
                  color: mediumGray,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Get color for participant based on name
  PdfColor _getParticipantColor(String username) {
    final colors = [
      primaryBlue,
      accentOrange,
      accentRed,
      accentPurple,
      PdfColor.fromHex('#27AE60'),
      PdfColor.fromHex('#E74C3C'),
      PdfColor.fromHex('#3498DB'),
      PdfColor.fromHex('#F39C12'),
    ];

    final index = username.hashCode.abs() % colors.length;
    return colors[index];
  }

  /// Fetch participants with user details from Firestore
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
        final rolesData = data['roles'] as List?;

        if (freeDaysData == null || freeDaysData.isEmpty) continue;

        // Fetch user details
        final userDoc = await FirebaseManager.firestore
            .collection('users')
            .doc(userId)
            .get();

        final username = userDoc.data()?['username'] ?? 'Unknown User';
        final roles =
            rolesData?.map((r) => r['name'] as String).join(', ') ?? '';

        final freeDays = freeDaysData
            .map((d) => FreeDay.fromJson(d as Map<String, dynamic>))
            .toList();

        participantsWithDetails.add({
          'username': username,
          'roles': roles,
          'free_days': freeDays,
        });
      }

      return participantsWithDetails;
    } catch (e) {
      return [];
    }
  }
}

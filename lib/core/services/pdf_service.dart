import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../../models/schedule.dart';
import '../../models/free_day.dart';
import '../utils/firebase_manager.dart';

class PdfService {
  Uint8List? _oswaldRegularData;
  Uint8List? _oswaldBoldData;
  Uint8List? _logoData;

  // Enhanced color palette with softer, more friendly colors
  static final PdfColor primaryBlue = PdfColor.fromHex('#5B9BD5');
  static final PdfColor accentOrange = PdfColor.fromHex('#FFA940');
  static final PdfColor accentRed = PdfColor.fromHex('#FF6B6B');
  static final PdfColor accentPurple = PdfColor.fromHex('#A78BFA');
  static final PdfColor accentGreen = PdfColor.fromHex('#4ECDC4');
  static final PdfColor lightBackground = PdfColor.fromHex('#FAFBFC');
  static final PdfColor darkGray = PdfColor.fromHex('#2D3748');
  static final PdfColor mediumGray = PdfColor.fromHex('#718096');
  static final PdfColor headerGray = PdfColor.fromHex('#4A5568');
  static final PdfColor calendarBorder = PdfColor.fromHex('#E2E8F0');
  static final PdfColor cardBackground = PdfColor.fromHex('#FFFFFF');

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

  Future<Uint8List> _getAppLogo() async {
    _logoData ??= await rootBundle
        .load('assets/schedulo.png')
        .then((data) => data.buffer.asUint8List());
    return _logoData!;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final Directory? directory = await getExternalStorageDirectory();

      if (directory == null) {
        throw Exception('Unable to access external storage');
      }

      directory.path.replaceAll(
          '/Android/data/${directory.path.split('/')[4]}/files', '/Download');

      final appDir = Directory('${directory.path}/SchedulerPDFs');

      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }

      return appDir;
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${dir.path}/SchedulerPDFs');
      if (!await appDir.exists()) await appDir.create(recursive: true);
      return appDir;
    }

    return await getTemporaryDirectory();
  }

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
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildHeader(logoImage, schedule),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          _buildTitleSection(schedule),
          pw.SizedBox(height: 24),
          _buildScheduleDetails(schedule),
          pw.SizedBox(height: 32),
          _buildCalendarView(schedule, participants),
          pw.SizedBox(height: 32),
          _buildParticipantDetails(participants),
        ],
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  pw.Widget _buildHeader(Uint8List logoImage, Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: calendarBorder, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: lightBackground,
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: calendarBorder, width: 1),
                ),
                child:
                    pw.Image(pw.MemoryImage(logoImage), height: 32, width: 32),
              ),
              pw.SizedBox(width: 16),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Scheduler',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: darkGray,
                      letterSpacing: -0.5,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Interpretation Planning System',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: mediumGray,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [primaryBlue, PdfColor.fromHex('#4A7BA7')],
              ),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              schedule.name,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: calendarBorder, width: 1),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated on ${DateFormat('MMMM dd, yyyy at HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(fontSize: 8, color: mediumGray),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: mediumGray),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTitleSection(Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(24),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [primaryBlue, PdfColor.fromHex('#4A7BA7')],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(16),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey300,
            offset: const PdfPoint(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 32,
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Text(
                  schedule.name,
                  style: pw.TextStyle(
                    fontSize: 26,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (schedule.description != null && schedule.description!.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12, left: 16),
              child: pw.Text(
                schedule.description!,
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey100,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildScheduleDetails(Schedule schedule) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: cardBackground,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: calendarBorder, width: 1.5),
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
            schedule.isFullySet ? accentGreen : accentOrange,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDetailItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 9,
            color: mediumGray,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(20),
            boxShadow: [
              pw.BoxShadow(
                color: PdfColors.grey300,
                offset: const PdfPoint(0, 2),
                blurRadius: 4,
              ),
            ],
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

  pw.Widget _buildCalendarView(
    Schedule schedule,
    List<Map<String, dynamic>> participants,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            pw.Container(
              width: 4,
              height: 24,
              decoration: pw.BoxDecoration(
                color: primaryBlue,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Text(
              'Schedule Calendar',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: darkGray,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: cardBackground,
            border: pw.Border.all(color: calendarBorder, width: 1.5),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 12,
            verticalRadius: 12,
            child: _buildCalendarGrid(schedule, participants),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildCalendarGrid(
    Schedule schedule,
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

    final rows = <pw.TableRow>[];

    rows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(
            colors: [headerGray, PdfColor.fromHex('#5A6C7D')],
          ),
        ),
        children: [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday'
        ]
            .map((day) => pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 12),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    day,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ))
            .toList(),
      ),
    );

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
      columnWidths: {
        0: const pw.FlexColumnWidth(1),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(1),
        6: const pw.FlexColumnWidth(1),
      },
      children: rows,
    );
  }

  pw.Widget _buildCalendarCell(
    DateTime date,
    List<Map<String, dynamic>> assignments,
    Schedule schedule,
  ) {
    final isToday = date.day == DateTime.now().day &&
        date.month == DateTime.now().month &&
        date.year == DateTime.now().year;

    final isBeforeStart = date.isBefore(schedule.startDate);
    final isWeekend = date.weekday == 6 || date.weekday == 7;

    return pw.Container(
      height: 70,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        color: isToday
            ? PdfColor.fromHex('#E3F2FD')
            : isBeforeStart
                ? PdfColor.fromHex('#F7FAFC')
                : isWeekend
                    ? PdfColor.fromHex('#FAFAFA')
                    : cardBackground,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: pw.BoxDecoration(
              color: isToday ? primaryBlue : null,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              '${date.day}',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: isToday ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isToday
                    ? PdfColors.white
                    : isBeforeStart
                        ? mediumGray
                        : darkGray,
              ),
            ),
          ),
          if (assignments.isNotEmpty)
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.SizedBox(height: 4),
                  ...assignments.take(2).map((assignment) {
                    final freeDay = assignment['freeDay'] as FreeDay;
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 3),
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        color: assignment['color'],
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            assignment['username'].toString().split(' ')[0],
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                          ),
                          pw.Text(
                            '${freeDay.startTime}-${freeDay.endTime}',
                            style: pw.TextStyle(
                              fontSize: 6,
                              color: PdfColors.grey100,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    );
                  }),
                  if (assignments.length > 2)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: pw.BoxDecoration(
                        color: lightBackground,
                        borderRadius: pw.BorderRadius.circular(3),
                        border: pw.Border.all(color: calendarBorder),
                      ),
                      child: pw.Text(
                        '+${assignments.length - 2} more',
                        style: pw.TextStyle(
                          fontSize: 6,
                          color: mediumGray,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _buildParticipantDetails(List<Map<String, dynamic>> participants) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: pw.Row(
            children: [
              pw.Container(
                width: 4,
                height: 24,
                decoration: pw.BoxDecoration(
                  color: primaryBlue,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Text(
                'Team Assignments',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: darkGray,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        ...participants
            .map((participant) => _buildParticipantCard(participant)),
      ],
    );
  }

  pw.Widget _buildParticipantCard(Map<String, dynamic> participant) {
    final username = participant['username'] as String;
    final roles = participant['roles'] as String;
    final freeDays = participant['free_days'] as List<FreeDay>;
    final participantColor = _getParticipantColor(username);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: pw.BoxDecoration(
        color: cardBackground,
        border: pw.Border.all(color: calendarBorder, width: 1.5),
        borderRadius: pw.BorderRadius.circular(12),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColors.grey300,
            offset: const PdfPoint(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: pw.Column(
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: participantColor,
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
                      width: 32,
                      height: 32,
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey300,
                        shape: pw.BoxShape.circle,
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        username[0].toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 10),
                    pw.Text(
                      username,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
                if (roles.isNotEmpty)
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white.shade(0.75),
                      borderRadius: pw.BorderRadius.circular(16),
                    ),
                    child: pw.Text(
                      roles,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            child: pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: freeDays.map((freeDay) {
                return _buildAssignmentChip(freeDay, participantColor);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAssignmentChip(FreeDay freeDay, PdfColor participantColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: lightBackground,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: participantColor, width: 1.5),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(
              color: participantColor,
              shape: pw.BoxShape.circle,
            ),
          ),
          pw.SizedBox(width: 8),
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
              pw.SizedBox(height: 2),
              pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: participantColor.shade(0.2),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '${freeDay.startTime} - ${freeDay.endTime}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: participantColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  PdfColor _getParticipantColor(String username) {
    final colors = [
      PdfColor.fromHex('#5B9BD5'), // Blue
      PdfColor.fromHex('#FFA940'), // Orange
      PdfColor.fromHex('#FF6B6B'), // Red
      PdfColor.fromHex('#A78BFA'), // Purple
      PdfColor.fromHex('#4ECDC4'), // Teal
      PdfColor.fromHex('#F59E0B'), // Amber
      PdfColor.fromHex('#10B981'), // Green
      PdfColor.fromHex('#EC4899'), // Pink
    ];

    final index = username.hashCode.abs() % colors.length;
    return colors[index];
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
        final rolesData = data['roles'] as List?;

        if (freeDaysData == null || freeDaysData.isEmpty) continue;

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

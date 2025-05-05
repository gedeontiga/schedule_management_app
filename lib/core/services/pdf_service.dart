import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/schedule.dart';
import '../utils/supabase_manager.dart';
import 'permission_service.dart';

class PdfService {
  final PermissionService _permissionService = PermissionService();
  final supabase = SupabaseManager.client;

  Uint8List? _oswaldRegularData;
  Uint8List? _oswaldBoldData;

  Future<Directory> getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final status = await _permissionService.requestStoragePermission();
      if (status != PermissionStatus.granted) {
        throw Exception('Storage permission is required to save PDF files');
      }

      final downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access downloads directory');
      }

      final appDownloadsDir = Directory('${downloadsDir.path}/SchedulerPDFs');
      if (!await appDownloadsDir.exists()) {
        await appDownloadsDir.create(recursive: true);
      }
      return appDownloadsDir;
    } else if (Platform.isIOS) {
      final documentsDir = await getApplicationDocumentsDirectory();
      final appDownloadsDir = Directory('${documentsDir.path}/SchedulerPDFs');
      if (!await appDownloadsDir.exists()) {
        await appDownloadsDir.create(recursive: true);
      }
      return appDownloadsDir;
    } else {
      final tempDir = await getTemporaryDirectory();
      return tempDir;
    }
  }

  Future<void> _loadFonts() async {
    if (_oswaldRegularData == null || _oswaldBoldData == null) {
      // Load Oswald fonts directly
      _oswaldRegularData = await rootBundle
          .load('assets/fonts/Oswald-Regular.ttf')
          .then((data) => data.buffer.asUint8List());

      _oswaldBoldData = await rootBundle
          .load('assets/fonts/Oswald-Bold.ttf')
          .then((data) => data.buffer.asUint8List());
    }
  }

  Future<Uint8List> _getAppLogo() async {
    return await rootBundle
        .load('assets/schedule_app_logo.png')
        .then((data) => data.buffer.asUint8List());
  }

  Future<File> generateSchedulePdf(Schedule schedule) async {
    if (!schedule.isFullySet) {
      throw Exception('Schedule must be fully set to export as PDF');
    }

    await _loadFonts();
    final logoImage = await _getAppLogo();

    final downloadDir = await getDownloadDirectory();
    final sanitizedName = schedule.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .toLowerCase();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${downloadDir.path}/${sanitizedName}_$timestamp.pdf';

    final pdf = pw.Document(
      theme: (_oswaldRegularData != null &&
              _oswaldRegularData!.isNotEmpty &&
              _oswaldBoldData != null &&
              _oswaldBoldData!.isNotEmpty)
          ? pw.ThemeData.withFont(
              base: pw.Font.ttf(ByteData.sublistView(_oswaldRegularData!)),
              bold: pw.Font.ttf(ByteData.sublistView(_oswaldBoldData!)),
            )
          : null,
    );

    final participants = await supabase
        .from('participants')
        .select('*')
        .eq('schedule_id', schedule.id)
        .then((p) => p
            .where((participant) => participant['free_days'].isNotEmpty)
            .toList());

    final participantIds =
        participants.map((p) => p['user_id'] as String).toList();

    final userData = await supabase
        .from('user_details')
        .select('id, username')
        .inFilter('id', participantIds);

    final usernameMap = {
      for (var user in userData)
        user['id'] as String: user['username'] as String
    };

    // Define colors
    final PdfColor primaryColor = PdfColor.fromInt(0xFF2196F3);
    final PdfColor accentColor = PdfColor.fromInt(0xFFD81B60);
    final PdfColor lightGrey = PdfColor.fromHex('#F5F5F5');
    final PdfColor participantHeaderColor = PdfColor.fromHex('#D6E4FF');
    final PdfColor alternateRowColor = PdfColor.fromHex('#F9F9F9');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Image(
                    pw.MemoryImage(logoImage),
                    height: 60,
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'SCHEDULER',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryColor,
                        ),
                      ),
                      pw.Text(
                        'Your schedule management solution',
                        style: pw.TextStyle(
                          fontSize: 12,
                          color: PdfColors.grey700,
                          fontStyle: pw.FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 2, color: primaryColor),
              pw.SizedBox(height: 10),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) {
          return [
            // Schedule Title
            pw.Header(
              level: 0,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text(
                  schedule.name,
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 10),

            // Schedule Description (if available)
            if (schedule.description != null &&
                schedule.description!.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: lightGrey,
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Text(
                  schedule.description!,
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey800),
                ),
              ),
            pw.SizedBox(height: 20),

            // Schedule Details Section
            pw.Header(
              level: 1,
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 5,
                    height: 20,
                    color: accentColor,
                    margin: const pw.EdgeInsets.only(right: 10),
                  ),
                  pw.Text(
                    'Schedule Details',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),

            // Schedule Details Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              columnWidths: {
                0: const pw.FixedColumnWidth(150),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                _buildTableRow(
                  'Duration',
                  schedule.duration,
                  isHeader: true,
                  backgroundColor: lightGrey,
                ),
                _buildTableRow(
                  'Available Days',
                  schedule.availableDays.map((d) => d.day).join(', '),
                ),
                _buildTableRow(
                  'Created On',
                  DateFormat('yyyy-MM-dd').format(schedule.createdAt),
                ),
              ],
            ),
            pw.SizedBox(height: 30),

            // Participant Assignments Section
            pw.Header(
              level: 1,
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 5,
                    height: 20,
                    color: accentColor,
                    margin: const pw.EdgeInsets.only(right: 10),
                  ),
                  pw.Text(
                    'Participant Assignments',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),

            // Participants Section - Improved layout
            ...participants.map((participant) {
              final userName = usernameMap[participant['user_id']];
              final roles =
                  participant['roles'].map((role) => role['name']).join(', ');

              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Participant Header
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: participantHeaderColor,
                        borderRadius: const pw.BorderRadius.only(
                          topLeft: pw.Radius.circular(5),
                          topRight: pw.Radius.circular(5),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Participant: $userName',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 16,
                              color: PdfColors.blue900,
                            ),
                          ),
                          pw.Text(
                            'Roles: $roles',
                            style: pw.TextStyle(
                              fontSize: 12,
                              color: PdfColors.blue800,
                              fontStyle: pw.FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scheduled Days Table
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(120),
                          1: const pw.FixedColumnWidth(120),
                          2: const pw.FlexColumnWidth(),
                        },
                        children: [
                          // Table Header
                          pw.TableRow(
                            decoration: pw.BoxDecoration(color: lightGrey),
                            children: [
                              _buildTableCell('Day', isHeader: true),
                              _buildTableCell('Date', isHeader: true),
                              _buildTableCell('Time Slot', isHeader: true),
                            ],
                          ),

                          // Days rows with alternating colors
                          ...participant['free_days']
                              .asMap()
                              .entries
                              .map((entry) {
                            final index = entry.key;
                            final day = entry.value;
                            final date = DateTime.tryParse(day['date'])!;

                            return pw.TableRow(
                              decoration: index % 2 == 1
                                  ? pw.BoxDecoration(color: alternateRowColor)
                                  : null,
                              children: [
                                _buildTableCell(
                                  day['day'].toString(),
                                  textStyle: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                _buildTableCell(
                                  DateFormat('yyyy-MM-dd').format(date),
                                ),
                                _buildTimeSlotCell(
                                  day['start_time'],
                                  day['end_time'],
                                  primaryColor,
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ];
        },
      ),
    );

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    if (Platform.isAndroid) {
      await _scanMediaFile(filePath);
    }

    return file;
  }

  pw.TableRow _buildTableRow(
    String label,
    String value, {
    bool isHeader = false,
    PdfColor? backgroundColor,
  }) {
    return pw.TableRow(
      decoration: backgroundColor != null
          ? pw.BoxDecoration(color: backgroundColor)
          : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isHeader ? pw.FontWeight.bold : null,
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(10),
          child: pw.Text(value),
        ),
      ],
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    pw.TextStyle? textStyle,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: textStyle ??
            pw.TextStyle(
              fontWeight: isHeader ? pw.FontWeight.bold : null,
            ),
      ),
    );
  }

  pw.Widget _buildTimeSlotCell(
      String startTime, String endTime, PdfColor accentColor) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.start,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 3,
            ),
            decoration: pw.BoxDecoration(
                color: PdfColors.orange200,
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(
                  color: PdfColors.blue900,
                  width: 0.5,
                )),
            child: pw.Text(
              '$startTime - $endTime',
              style: pw.TextStyle(
                color: PdfColors.blue900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanMediaFile(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final channel = MethodChannel('com.scheduler.app/media_scanner');
        await channel.invokeMethod('scanFile', {'filePath': filePath});
      }
    } catch (e) {
      debugPrint('Error scanning media file: $e');
    }
  }
}

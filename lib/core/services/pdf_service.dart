import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

  // Cache for the Montserrat font data
  Uint8List? _montserratRegularData;
  Uint8List? _montserratBoldData;

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

  // Load Montserrat font data
  Future<void> _loadFonts() async {
    if (_montserratRegularData == null || _montserratBoldData == null) {
      // Load Montserrat Regular and Bold from GoogleFonts
      final regularFont = GoogleFonts.montserrat();
      final boldFont = GoogleFonts.montserrat(fontWeight: FontWeight.bold);

      // Extract font data as Uint8List
      _montserratRegularData = await _getFontData(regularFont);
      _montserratBoldData = await _getFontData(boldFont);
    }
  }

  Future<Uint8List> _getFontData(TextStyle style) async {
    final fontFamily = style.fontFamily ?? 'Montserrat';
    final fontWeight = style.fontWeight ?? FontWeight.normal;
    // Map FontWeight to Google Fonts asset naming convention
    final weightName = _fontWeightToName(fontWeight);
    // GoogleFonts stores fonts in packages, so we need to load from the correct asset path
    final fontAssetPath =
        'packages/google_fonts/fonts/$fontFamily-$weightName.ttf';
    try {
      final fontData = await rootBundle.load(fontAssetPath);
      return fontData.buffer.asUint8List();
    } catch (e) {
      throw Exception('Failed to load font $fontFamily-$weightName: $e');
    }
  }

  // Helper method to map FontWeight to Google Fonts asset naming
  String _fontWeightToName(FontWeight weight) {
    switch (weight) {
      case FontWeight.w100:
        return 'Thin';
      case FontWeight.w200:
        return 'ExtraLight';
      case FontWeight.w300:
        return 'Light';
      case FontWeight.w400:
        return 'Regular';
      case FontWeight.w500:
        return 'Medium';
      case FontWeight.w600:
        return 'SemiBold';
      case FontWeight.w700:
        return 'Bold';
      case FontWeight.w800:
        return 'ExtraBold';
      case FontWeight.w900:
        return 'Black';
      default:
        return 'Regular';
    }
  }

  // Method to load app logo from assets
  Future<Uint8List> _getAppLogo() async {
    return await rootBundle
        .load('assets/schedule_app_logo.png')
        .then((data) => data.buffer.asUint8List());
  }

  Future<File> generateSchedulePdf(Schedule schedule) async {
    if (!schedule.isFullySet) {
      throw Exception('Schedule must be fully set to export as PDF');
    }

    // Load fonts and logo
    await _loadFonts();
    final logoImage = await _getAppLogo();

    final downloadDir = await getDownloadDirectory();
    final sanitizedName = schedule.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .toLowerCase();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${downloadDir.path}/${sanitizedName}_$timestamp.pdf';

    // Create PDF document with custom theme using Google Fonts
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(ByteData.sublistView(_montserratRegularData!)),
        bold: pw.Font.ttf(ByteData.sublistView(_montserratBoldData!)),
      ),
    );

    final participantIds = schedule.participants
        .where((p) => p.freeDays.isNotEmpty)
        .map((p) => p.userId)
        .toList();

    final userData = await supabase
        .from('users')
        .select('id, username')
        .inFilter('id', participantIds);

    final usernameMap = {
      for (var user in userData)
        user['id'] as String: user['username'] as String
    };

    final participants =
        schedule.participants.where((p) => p.freeDays.isNotEmpty).toList();

    final PdfColor primaryColor = PdfColor.fromHex('#4285F4');
    final PdfColor accentColor = PdfColor.fromHex('#34A853');
    final PdfColor lightGrey = PdfColor.fromHex('#F5F5F5');

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
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) {
          return [
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
                  style: const pw.TextStyle(
                      fontSize: 14, color: PdfColors.grey800),
                ),
              ),
            pw.SizedBox(height: 20),
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
                  schedule.availableDays.join(', '),
                ),
                _buildTableRow(
                  'Created On',
                  DateFormat('yyyy-MM-dd').format(schedule.createdAt),
                ),
              ],
            ),
            pw.SizedBox(height: 30),
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
            ...participants.map((participant) {
              final userName =
                  usernameMap[participant.userId] ?? participant.userId;
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#D6E4FF'),
                        borderRadius: const pw.BorderRadius.only(
                          topLeft: pw.Radius.circular(5),
                          topRight: pw.Radius.circular(5),
                        ),
                      ),
                      child: pw.Text(
                        'Participant: $userName',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 16,
                          color: PdfColors.blue900,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(100),
                          1: const pw.FixedColumnWidth(100),
                          2: const pw.FixedColumnWidth(100),
                          3: const pw.FlexColumnWidth(),
                        },
                        children: [
                          pw.TableRow(
                            decoration: pw.BoxDecoration(color: lightGrey),
                            children: [
                              _buildTableCell('Day', isHeader: true),
                              _buildTableCell('Date', isHeader: true),
                              _buildTableCell('Time', isHeader: true),
                              _buildTableCell('Roles', isHeader: true),
                            ],
                          ),
                          ...participant.freeDays.map((day) {
                            final roles = participant.roles
                                .map((role) => role.name)
                                .join(', ');
                            return pw.TableRow(
                              children: [
                                _buildTableCell(day.day),
                                _buildTableCell(
                                    DateFormat('yyyy-MM-dd').format(day.date)),
                                _buildTableCell(
                                    '${day.startTime} - ${day.endTime}'),
                                _buildTableCell(roles),
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

  pw.TableRow _buildTableRow(String label, String value,
      {bool isHeader = false, PdfColor? backgroundColor}) {
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

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isHeader ? pw.FontWeight.bold : null,
        ),
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
      // Handle the exception or log it
    }
  }
}

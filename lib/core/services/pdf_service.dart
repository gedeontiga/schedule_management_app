import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/schedule.dart';
import 'permission_service.dart';

class PdfService {
  final PermissionService _permissionService = PermissionService();

  Future<Directory> getDownloadDirectory() async {
    // First, check if we can access the download directory
    if (Platform.isAndroid) {
      // For Android, we need to use the downloads directory
      final status = await _permissionService.requestStoragePermission();
      if (status != PermissionStatus.granted) {
        throw Exception('Storage permission is required to save PDF files');
      }

      // Get the downloads directory path
      final downloadsDir = await getExternalStorageDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access downloads directory');
      }

      // Create a subfolder for our app's PDFs
      final appDownloadsDir = Directory('${downloadsDir.path}/SchedulerPDFs');

      // Create the directory if it doesn't exist
      if (!await appDownloadsDir.exists()) {
        await appDownloadsDir.create(recursive: true);
      }

      return appDownloadsDir;
    } else if (Platform.isIOS) {
      // For iOS, we use the documents directory
      final documentsDir = await getApplicationDocumentsDirectory();
      final appDownloadsDir = Directory('${documentsDir.path}/SchedulerPDFs');

      // Create the directory if it doesn't exist
      if (!await appDownloadsDir.exists()) {
        await appDownloadsDir.create(recursive: true);
      }

      return appDownloadsDir;
    } else {
      // For other platforms, just use temp directory
      final tempDir = await getTemporaryDirectory();
      return tempDir;
    }
  }

  Future<File> generateSchedulePdf(Schedule schedule) async {
    if (!schedule.isFullySet) {
      throw Exception('Schedule must be fully set to export as PDF');
    }

    // Get the download directory
    final downloadDir = await getDownloadDirectory();

    // Create a sanitized filename from the schedule name
    final sanitizedName = schedule.name
        .replaceAll(' ', '_')
        .replaceAll(RegExp(r'[^\w\s]+'), '')
        .toLowerCase();

    // Create a filename with timestamp
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${downloadDir.path}/${sanitizedName}_$timestamp.pdf';

    // Initialize PDF document
    final pdf = pw.Document();

    // Get all participants with their assigned days
    final participants =
        schedule.participants.where((p) => p.freeDays.isNotEmpty).toList();

    // Add content to PDF
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('Schedule: ${schedule.name}',
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Paragraph(
              text: schedule.description ?? 'No description',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 20),

            // Schedule details
            pw.Header(level: 1, text: 'Schedule Details'),
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FixedColumnWidth(150),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Duration',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(schedule.duration),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Available Days',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(schedule.availableDays.join(', ')),
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('Created On',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(
                          DateFormat('yyyy-MM-dd').format(schedule.createdAt)),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Participant assignments
            pw.Header(level: 1, text: 'Participant Assignments'),
            ...participants.map((participant) {
              final userName =
                  participant.userId; // In a real app, fetch actual user name
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
                    child: pw.Text(
                      'Participant: $userName',
                      style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  pw.Table(
                    border: pw.TableBorder.all(),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(100),
                      1: const pw.FixedColumnWidth(100),
                      2: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey300),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('Day',
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('Date',
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text('Roles',
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      ...participant.freeDays.map((day) {
                        final roles = participant.roles
                            .map((role) => role.name)
                            .join(', ');
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(day.day),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(
                                  DateFormat('yyyy-MM-dd').format(day.date)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(5),
                              child: pw.Text(roles),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }),

            pw.SizedBox(height: 20),
            pw.Footer(
              leading: pw.Text(
                  'Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
            ),
          ];
        },
      ),
    );

    // Save the PDF to file
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    // If on Android, make the file visible in the media store
    if (Platform.isAndroid) {
      await _scanMediaFile(filePath);
    }

    return file;
  }

  // Scan media file so it appears in gallery/file manager
  Future<void> _scanMediaFile(String filePath) async {
    try {
      if (Platform.isAndroid) {
        final channel = MethodChannel('com.scheduler.app/media_scanner');
        await channel.invokeMethod('scanFile', {'filePath': filePath});
      }
    } catch (e) {
      // Fail silently, this is just a convenience feature
    }
  }
}

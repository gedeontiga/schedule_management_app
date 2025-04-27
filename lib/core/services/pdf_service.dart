import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../../models/schedule.dart';

class PdfService {
  Future<File> generateSchedulePdf(Schedule schedule) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(schedule.name,
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Text('Description: ${schedule.description ?? "None"}'),
              pw.Text('Available Days: ${schedule.availableDays.join(", ")}'),
              pw.Text('Duration: ${schedule.duration}'),
              pw.SizedBox(height: 16),
              pw.Text('Participants:',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ...schedule.participants.map(
                (p) => pw.Text(
                    '- User: ${p.userId}, Roles: ${p.roles.map((r) => r.name).join(", ")}, Free Days: ${p.freeDays.join(", ")}'),
              ),
            ],
          );
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/schedule_${schedule.id}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}

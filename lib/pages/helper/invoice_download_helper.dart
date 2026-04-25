import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';

Future<String?> generateUploadAndSaveInvoicePDF({
  required BuildContext context,
  required int orderId,
  required String orderNo,
  required String companyName,
  required double totalAmount,
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> priceComponents,
}) async {
  try {
    final repaintKey = GlobalKey();
    // 🧮 Compute total from priceComponents
    final computedTotal = priceComponents.fold<double>(
      0,
      (sum, p) => sum + ((p['actual_price'] ?? 0) as num).toDouble(),
    );

    // 🧩 Invoice UI (Flutter widget with proper font)
    final invoice = RepaintBoundary(
      key: repaintKey,
      child: Material(
        color: Colors.white,
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: 'NotoSansKannada', // use Kannada-safe font
            fontSize: 13,
            color: Colors.black,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(
                  child: Text(
                    'Invoice',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                Text('ಆರ್ಡರ್ ಸಂಖ್ಯೆ: $orderNo'),
                Text('ಕಂಪನಿ: $companyName'),
                Text('Order ID: $orderId'),
                const SizedBox(height: 10),

                // Product Table
                Table(
                  border: TableBorder.all(),
                  columnWidths: const {
                    0: FixedColumnWidth(40),
                    1: FlexColumnWidth(),
                    2: FixedColumnWidth(40),
                    3: FixedColumnWidth(70),
                    4: FixedColumnWidth(60),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(color: Color(0xFFEFEFEF)),
                      children: [
                        Padding(padding: EdgeInsets.all(4), child: Text('Sl')),
                        Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('ಉತ್ಪನ್ನ'),
                        ),
                        Padding(padding: EdgeInsets.all(4), child: Text('Qty')),
                        Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('ಬೆಲೆ ₹'),
                        ),
                        Padding(
                          padding: EdgeInsets.all(4),
                          child: Text('ಸ್ಟಾಕ್'),
                        ),
                      ],
                    ),
                    for (int i = 0; i < products.length; i++)
                      TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${i + 1}'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(products[i]['product_name'] ?? '-'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text('${products[i]['quantity'] ?? 0}'),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              '₹${(products[i]['unit_price'] ?? 0).toStringAsFixed(2)}',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              (products[i]['stock'] == true) ? 'ಹೌದು' : 'ಇಲ್ಲ',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                if (priceComponents.isNotEmpty)
                  Table(
                    border: TableBorder.all(),
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: Color(0xFFEFEFEF)),
                        children: [
                          Padding(
                            padding: EdgeInsets.all(4),
                            child: Text('ಘಟಕ'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(4),
                            child: Text('ಮೊತ್ತ ₹'),
                          ),
                        ],
                      ),
                      for (final p in priceComponents)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(p['price_component'] ?? '-'),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: Text(
                                (p['actual_price'] ?? 0).toStringAsFixed(2),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                const SizedBox(height: 10),

                // 🧮 Compute total from priceComponents
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'ಒಟ್ಟು ಮೊತ್ತ: ₹${computedTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const Center(
                  child: Text(
                    'ಧನ್ಯವಾದಗಳು!',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // 🧩 Capture Widget as Image
    final overlay = OverlayEntry(
      builder: (_) => Center(child: SizedBox(width: 794, child: invoice)),
    );
    Overlay.of(context).insert(overlay);
    await Future.delayed(const Duration(milliseconds: 400));

    final renderObject = repaintKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('Render boundary not found');
    }
    final boundary = renderObject;
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();
    overlay.remove();

    // 🧩 Generate PDF from Image
    final pdf = pw.Document();
    final pdfImage = pw.MemoryImage(pngBytes);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Image(pdfImage)),
      ),
    );
    final pdfBytes = await pdf.save();

    // 🧩 Upload to Supabase
    final supabase = Supabase.instance.client;
    const bucketName = 'invoice_files';
    final fileName = 'invoice_$orderNo.pdf';
    final filePath = 'invoices/$fileName';

    await supabase.storage
        .from(bucketName)
        .uploadBinary(
          filePath,
          pdfBytes,
          fileOptions: const FileOptions(upsert: true),
        );

    final publicUrl = supabase.storage.from(bucketName).getPublicUrl(filePath);
    await supabase
        .from('order')
        .update({'invoice_url': publicUrl})
        .eq('id', orderId);

    debugPrint('✅ Kannada-perfect invoice uploaded: $publicUrl');
    return publicUrl;
  } catch (e, st) {
    debugPrint('❌ Error generating Kannada PDF: $e');
    debugPrint('$st');
    return null;
  }
}

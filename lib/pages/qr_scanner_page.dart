import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class QRScannerPage extends StatefulWidget {
  final String scheduleId;
  final Map<String, dynamic> scheduleData;

  const QRScannerPage({
    super.key,
    required this.scheduleId,
    required this.scheduleData,
  });

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  MobileScannerController? controller;
  bool isProcessing = false;
  List<String> checkedInBookings = [];
  bool isTorchOn = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      formats: [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Scan QR Code',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Torch toggle
          IconButton(
            icon: Icon(
              isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: isTorchOn ? Colors.yellow : Colors.white,
            ),
            onPressed: () async {
              try {
                await controller?.toggleTorch();
                setState(() {
                  isTorchOn = !isTorchOn;
                });
              } catch (e) {
                print('Error toggling torch: $e');
              }
            },
          ),
          // Camera switch
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: () async {
              try {
                await controller?.switchCamera();
              } catch (e) {
                print('Error switching camera: $e');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview area
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                // Camera view
                MobileScanner(
                  controller: controller,
                  onDetect: (BarcodeCapture capture) {
                    if (isProcessing) return;

                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final String? code = barcode.rawValue;
                      if (code != null && code.isNotEmpty) {
                        print('QR Code detected: $code');
                        _processQRCode(code);
                        break;
                      }
                    }
                  },
                ),

                // Scanning overlay
                Container(
                  decoration: ShapeDecoration(
                    shape: QRScannerOverlayShape(
                      borderColor: Colors.blue,
                      borderRadius: 16,
                      borderLength: 40,
                      borderWidth: 4,
                      cutOutSize: MediaQuery.of(context).size.width * 0.7,
                    ),
                  ),
                ),

                // Processing overlay
                if (isProcessing)
                  Container(
                    color: Colors.black.withOpacity(0.7),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Processing QR Code...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Instructions overlay
                Positioned(
                  top: 50,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Point camera at QR code',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (checkedInBookings.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${checkedInBookings.length} checked in',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom control panel
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Test button
                TextButton(
                  onPressed: () {
                    String testQrData = '''
                    {
                      "bookingId": "test123",
                      "scheduleId": "${widget.scheduleId}",
                      "passengerName": "Test User"
                    }
                    ''';
                    _processQRCode(testQrData);
                  },
                  child: const Text(
                    'Test QR Processing',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),

                const SizedBox(height: 16),

                // Done button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context, checkedInBookings),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.check),
                    label: Text(
                      'Done (${checkedInBookings.length} checked in)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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

  Future<void> _processQRCode(String qrData) async {
    if (isProcessing) return;

    setState(() {
      isProcessing = true;
    });

    try {
      print('Processing QR: $qrData');

      Map<String, dynamic> qrInfo;
      try {
        qrInfo = json.decode(qrData);
      } catch (e) {
        _showMessage('Invalid QR code format', Colors.red);
        return;
      }

      final bookingId = qrInfo['bookingId'];
      final scheduleId = qrInfo['scheduleId'];
      final passengerName = qrInfo['passengerName'] ?? 'Passenger';

      if (bookingId == null || scheduleId == null) {
        _showMessage('Invalid QR code data', Colors.red);
        return;
      }

      // For test booking
      if (bookingId == 'test123') {
        if (!checkedInBookings.contains(bookingId)) {
          setState(() {
            checkedInBookings.add(bookingId);
          });
          _showMessage('$passengerName checked in! (TEST)', Colors.green);
        } else {
          _showMessage('$passengerName already checked in', Colors.orange);
        }
        return;
      }

      if (scheduleId != widget.scheduleId) {
        _showMessage('Wrong trip', Colors.red);
        return;
      }

      if (checkedInBookings.contains(bookingId)) {
        _showMessage('$passengerName already checked in', Colors.orange);
        return;
      }

      final bookingDoc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .get();

      if (!bookingDoc.exists) {
        _showMessage('Booking not found', Colors.red);
        return;
      }

      final bookingData = bookingDoc.data() as Map<String, dynamic>;

      if (bookingData['scheduleId'] != widget.scheduleId) {
        _showMessage('Schedule mismatch', Colors.red);
        return;
      }

      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(bookingId)
          .update({
            'status': 'checked_in',
            'checkedInAt': FieldValue.serverTimestamp(),
          });

      setState(() {
        checkedInBookings.add(bookingId);
      });

      _showMessage('$passengerName checked in!', Colors.green);
    } catch (e) {
      print('Error processing QR: $e');
      _showMessage('Error: ${e.toString()}', Colors.red);
    } finally {
      // Delay before allowing next scan
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  void _showMessage(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

// Custom overlay shape for the QR scanner
class QRScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QRScannerOverlayShape({
    this.borderColor = Colors.red,
    this.borderWidth = 3.0,
    this.overlayColor = const Color.fromRGBO(0, 0, 0, 80),
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => const EdgeInsets.all(10);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    Path path = Path();
    Size size = rect.size;
    final center = Offset(size.width / 2, size.height / 2);
    final cutOutRect = Rect.fromCenter(
      center: center,
      width: cutOutSize,
      height: cutOutSize,
    );

    path.addRect(rect);
    path.addRRect(
      RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
    );
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final size = rect.size;
    final center = Offset(size.width / 2, size.height / 2);
    final cutOutRect = Rect.fromCenter(
      center: center,
      width: cutOutSize,
      height: cutOutSize,
    );

    final paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    canvas.drawRect(rect, Paint()..color = overlayColor);
    canvas.drawRRect(
      RRect.fromRectAndRadius(cutOutRect, Radius.circular(borderRadius)),
      paint,
    );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final path = Path();

    // Draw corner brackets
    path.moveTo(cutOutRect.left, cutOutRect.top + borderLength);
    path.lineTo(cutOutRect.left, cutOutRect.top + borderRadius);
    path.quadraticBezierTo(
      cutOutRect.left,
      cutOutRect.top,
      cutOutRect.left + borderRadius,
      cutOutRect.top,
    );
    path.lineTo(cutOutRect.left + borderLength, cutOutRect.top);

    path.moveTo(cutOutRect.right - borderLength, cutOutRect.top);
    path.lineTo(cutOutRect.right - borderRadius, cutOutRect.top);
    path.quadraticBezierTo(
      cutOutRect.right,
      cutOutRect.top,
      cutOutRect.right,
      cutOutRect.top + borderRadius,
    );
    path.lineTo(cutOutRect.right, cutOutRect.top + borderLength);

    path.moveTo(cutOutRect.right, cutOutRect.bottom - borderLength);
    path.lineTo(cutOutRect.right, cutOutRect.bottom - borderRadius);
    path.quadraticBezierTo(
      cutOutRect.right,
      cutOutRect.bottom,
      cutOutRect.right - borderRadius,
      cutOutRect.bottom,
    );
    path.lineTo(cutOutRect.right - borderLength, cutOutRect.bottom);

    path.moveTo(cutOutRect.left + borderLength, cutOutRect.bottom);
    path.lineTo(cutOutRect.left + borderRadius, cutOutRect.bottom);
    path.quadraticBezierTo(
      cutOutRect.left,
      cutOutRect.bottom,
      cutOutRect.left,
      cutOutRect.bottom - borderRadius,
    );
    path.lineTo(cutOutRect.left, cutOutRect.bottom - borderLength);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QRScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      overlayColor: overlayColor,
    );
  }
}
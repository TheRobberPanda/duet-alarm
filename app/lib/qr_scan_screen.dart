import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

/// Full-screen camera for reading the partner's invite QR. Returns the code
/// string via Navigator.pop; the pair screen owns validation and redemption.
/// Kept as its own route rather than an inline sheet so the camera gets the
/// whole screen and the gesture arenas never overlap.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();

  // onDetect fires for every frame the barcode is visible -- one pop, ever.
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      // Anything shorter is noise; the redeem path reports real problems
      // ("expired", "that is your own code") in plain language.
      if (code != null && code.length >= 4) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: DuetColors.text),
          title: const Text('Scan their code',
              style: TextStyle(fontSize: 16, color: DuetColors.text)),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: DuetColors.text.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: Text(
                  'Line up the QR on their screen',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: DuetColors.text.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

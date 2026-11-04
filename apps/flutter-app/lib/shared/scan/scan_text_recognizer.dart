import 'scan_text_recognizer_contract.dart';
import 'scan_text_recognizer_unsupported.dart'
    if (dart.library.io) 'scan_text_recognizer_native.dart'
    as implementation;

export 'scan_text_recognizer_contract.dart';

ScanTextRecognizer createScanTextRecognizer() =>
    implementation.createScanTextRecognizer();

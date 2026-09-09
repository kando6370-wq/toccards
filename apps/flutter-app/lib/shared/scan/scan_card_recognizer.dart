import 'scan_card_recognizer_contract.dart';
import 'scan_card_recognizer_unsupported.dart'
    if (dart.library.io) 'scan_card_recognizer_native.dart'
    as implementation;

export 'scan_card_recognizer_contract.dart';

ScanCardRecognizer createScanCardRecognizer() =>
    implementation.createScanCardRecognizer();

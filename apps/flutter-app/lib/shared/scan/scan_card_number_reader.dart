import 'scan_card_number_reader_contract.dart';
import 'scan_card_number_reader_unsupported.dart'
    if (dart.library.io) 'scan_card_number_reader_native.dart'
    as implementation;

export 'scan_card_number_reader_contract.dart';

ScanCardNumberReader createScanCardNumberReader() =>
    implementation.createScanCardNumberReader();

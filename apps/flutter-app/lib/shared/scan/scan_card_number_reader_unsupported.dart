import 'scan_card_number_reader_contract.dart';

ScanCardNumberReader createScanCardNumberReader() =>
    const _UnsupportedScanCardNumberReader();

class _UnsupportedScanCardNumberReader implements ScanCardNumberReader {
  const _UnsupportedScanCardNumberReader();

  @override
  Future<String?> read(_) async => null;
}

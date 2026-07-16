import 'scan_image_hasher_contract.dart';
import 'scan_image_hasher_unsupported.dart'
    if (dart.library.ffi) 'scan_image_hasher_native.dart'
    as implementation;

export 'scan_image_hasher_contract.dart';

ScanImageHasher createScanImageHasher() =>
    implementation.createScanImageHasher();

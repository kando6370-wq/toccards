import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/scan/scan_stability.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';

void main() {
  test(
    'eight stable detections trigger once because one recognition request, not camera frames, defines an auditable scan',
    () {
      final gate = ScanStabilityGate();

      for (var index = 0; index < 7; index += 1) {
        expect(gate.add(_detection(offset: index * 0.5)), isFalse);
      }
      expect(gate.add(_detection(offset: 3.5)), isTrue);
    },
  );

  test(
    'movement or area jumps restart stability because a different card pose must not reuse prior frame confidence',
    () {
      final gate = ScanStabilityGate();
      for (var index = 0; index < 5; index += 1) {
        gate.add(_detection(offset: index * 0.5));
      }

      expect(gate.add(_detection(offset: 80)), isFalse);
      expect(gate.stableCount, 1);
      expect(gate.add(null), isFalse);
      expect(gate.stableCount, 0);
    },
  );
}

ScanFrameDetection _detection({required double offset}) {
  return ScanFrameDetection(
    width: 1280,
    height: 720,
    corners: [
      ScanImagePoint(400 + offset, 100 + offset),
      ScanImagePoint(700 + offset, 100 + offset),
      ScanImagePoint(700 + offset, 520 + offset),
      ScanImagePoint(400 + offset, 520 + offset),
    ],
  );
}

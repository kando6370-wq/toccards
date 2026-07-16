import 'dart:math' as math;

import '../../shared/scan/scan_image_hasher.dart';

class ScanStabilityGate {
  ScanStabilityGate({
    this.requiredFrames = 8,
    this.movementThreshold = 0.012,
    this.areaChangeThreshold = 0.10,
  });

  final int requiredFrames;
  final double movementThreshold;
  final double areaChangeThreshold;

  List<ScanImagePoint>? _previousCorners;
  var _stableCount = 0;

  int get stableCount => _stableCount;

  bool add(ScanFrameDetection? detection) {
    if (detection == null || detection.corners.length != 4) {
      reset();
      return false;
    }
    final previous = _previousCorners;
    if (previous == null) {
      _stableCount = 1;
    } else {
      final diagonal = math.sqrt(
        detection.width * detection.width + detection.height * detection.height,
      );
      var movement = 0.0;
      for (var index = 0; index < 4; index += 1) {
        final dx = detection.corners[index].x - previous[index].x;
        final dy = detection.corners[index].y - previous[index].y;
        movement += math.sqrt(dx * dx + dy * dy);
      }
      movement = movement / 4 / diagonal;
      final previousArea = _polygonArea(previous);
      final currentArea = _polygonArea(detection.corners);
      final areaChange =
          (currentArea - previousArea).abs() / math.max(previousArea, 1.0);
      _stableCount =
          movement <= movementThreshold && areaChange <= areaChangeThreshold
          ? _stableCount + 1
          : 1;
    }
    _previousCorners = List.of(detection.corners);
    return _stableCount >= requiredFrames;
  }

  void reset() {
    _previousCorners = null;
    _stableCount = 0;
  }

  double _polygonArea(List<ScanImagePoint> points) {
    var twiceArea = 0.0;
    for (var index = 0; index < points.length; index += 1) {
      final next = points[(index + 1) % points.length];
      twiceArea += points[index].x * next.y - next.x * points[index].y;
    }
    return twiceArea.abs() / 2;
  }
}

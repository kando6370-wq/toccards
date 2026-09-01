import 'dart:math' as math;
import 'dart:typed_data';

class ScanImagePoint {
  const ScanImagePoint(this.x, this.y);

  final double x;
  final double y;
}

class ScanMaskQuad {
  const ScanMaskQuad({
    required this.points,
    required this.areaRatio,
    required this.usedMinimumAreaRectangle,
  });

  final List<ScanImagePoint> points;
  final double areaRatio;
  final bool usedMinimumAreaRectangle;
}

ScanMaskQuad? fitScanMaskQuad(
  Float32List masks, {
  required int maskOffset,
  required int maskRows,
  required int maskCols,
  required int resizedWidth,
  required int resizedHeight,
  required int sourceWidth,
  required int sourceHeight,
  double threshold = 0.5,
}) {
  if (resizedWidth <= 0 ||
      resizedHeight <= 0 ||
      resizedWidth > maskCols ||
      resizedHeight > maskRows) {
    return null;
  }

  final pixelCount = resizedWidth * resizedHeight;
  final binary = Uint8List(pixelCount);
  for (var y = 0; y < resizedHeight; y += 1) {
    final sourceRow = maskOffset + y * maskCols;
    final targetRow = y * resizedWidth;
    for (var x = 0; x < resizedWidth; x += 1) {
      if (masks[sourceRow + x] >= threshold) {
        binary[targetRow + x] = 1;
      }
    }
  }

  final boundary = _largestComponentBoundary(
    binary,
    resizedWidth,
    resizedHeight,
  );
  if (boundary == null || boundary.area < 16 || boundary.points.length < 3) {
    return null;
  }

  final hull = _convexHull(boundary.points);
  if (hull.length < 3) return null;
  final contourArea = _polygonArea(hull);
  if (contourArea < 16) return null;

  List<ScanImagePoint>? quad;
  var usedMinimumAreaRectangle = false;
  final perimeter = _closedPerimeter(hull);
  for (var index = 0; index < 24; index += 1) {
    final epsilonRatio = 0.005 + index * (0.115 / 23);
    final polygon = _approximateClosedPolygon(hull, epsilonRatio * perimeter);
    if (polygon.length == 4) {
      quad = polygon;
      break;
    }
  }

  if (quad == null) {
    final rectangle = _minimumAreaRectangle(hull);
    if (rectangle == null || rectangle.width < 4 || rectangle.height < 4) {
      return null;
    }
    quad = rectangle.points;
    usedMinimumAreaRectangle = true;
  }

  final scaleX = sourceWidth / resizedWidth;
  final scaleY = sourceHeight / resizedHeight;
  return ScanMaskQuad(
    points: orderScanCorners([
      for (final point in quad)
        ScanImagePoint(point.x * scaleX, point.y * scaleY),
    ]),
    areaRatio: contourArea / pixelCount,
    usedMinimumAreaRectangle: usedMinimumAreaRectangle,
  );
}

List<ScanImagePoint> orderScanCorners(List<ScanImagePoint> points) {
  if (points.length != 4) {
    throw ArgumentError.value(points.length, 'points', 'Four points required');
  }
  final centerX = points.map((point) => point.x).reduce((a, b) => a + b) / 4;
  final centerY = points.map((point) => point.y).reduce((a, b) => a + b) / 4;
  final ordered = List<ScanImagePoint>.from(points)
    ..sort((left, right) {
      final leftAngle = math.atan2(left.y - centerY, left.x - centerX);
      final rightAngle = math.atan2(right.y - centerY, right.x - centerX);
      return leftAngle.compareTo(rightAngle);
    });
  var start = 0;
  for (var index = 1; index < ordered.length; index += 1) {
    if (ordered[index].x + ordered[index].y <
        ordered[start].x + ordered[start].y) {
      start = index;
    }
  }
  final rotated = [
    for (var index = 0; index < 4; index += 1)
      ordered[(start + index) % 4],
  ];
  final firstX = rotated[1].x - rotated[0].x;
  final firstY = rotated[1].y - rotated[0].y;
  final secondX = rotated[2].x - rotated[1].x;
  final secondY = rotated[2].y - rotated[1].y;
  if (firstX * secondY - firstY * secondX < 0) {
    return [rotated[0], rotated[3], rotated[2], rotated[1]];
  }
  return rotated;
}

class _ComponentBoundary {
  const _ComponentBoundary(this.area, this.points);

  final int area;
  final List<ScanImagePoint> points;
}

_ComponentBoundary? _largestComponentBoundary(
  Uint8List binary,
  int width,
  int height,
) {
  final visited = Uint8List(binary.length);
  final queue = Int32List(binary.length);
  _ComponentBoundary? largest;

  for (var start = 0; start < binary.length; start += 1) {
    if (binary[start] == 0 || visited[start] != 0) continue;
    var head = 0;
    var tail = 1;
    var area = 0;
    final boundary = <ScanImagePoint>[];
    queue[0] = start;
    visited[start] = 1;

    while (head < tail) {
      final pixel = queue[head++];
      area += 1;
      final x = pixel % width;
      final y = pixel ~/ width;
      var isBoundary = x == 0 || y == 0 || x == width - 1 || y == height - 1;

      void visit(int neighbor) {
        if (binary[neighbor] == 0) {
          isBoundary = true;
        } else if (visited[neighbor] == 0) {
          visited[neighbor] = 1;
          queue[tail++] = neighbor;
        }
      }

      if (x > 0) visit(pixel - 1);
      if (x + 1 < width) visit(pixel + 1);
      if (y > 0) visit(pixel - width);
      if (y + 1 < height) visit(pixel + width);
      if (isBoundary) boundary.add(ScanImagePoint(x.toDouble(), y.toDouble()));
    }

    if (largest == null || area > largest.area) {
      largest = _ComponentBoundary(area, boundary);
    }
  }
  return largest;
}

List<ScanImagePoint> _convexHull(List<ScanImagePoint> points) {
  final sorted = List<ScanImagePoint>.from(points)
    ..sort((left, right) {
      final xOrder = left.x.compareTo(right.x);
      return xOrder != 0 ? xOrder : left.y.compareTo(right.y);
    });
  if (sorted.length <= 1) return sorted;

  final unique = <ScanImagePoint>[];
  for (final point in sorted) {
    if (unique.isEmpty ||
        point.x != unique.last.x ||
        point.y != unique.last.y) {
      unique.add(point);
    }
  }
  if (unique.length <= 2) return unique;

  final lower = <ScanImagePoint>[];
  for (final point in unique) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  final upper = <ScanImagePoint>[];
  for (final point in unique.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  return [...lower.take(lower.length - 1), ...upper.take(upper.length - 1)];
}

double _cross(ScanImagePoint a, ScanImagePoint b, ScanImagePoint c) =>
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);

double _closedPerimeter(List<ScanImagePoint> points) {
  var total = 0.0;
  for (var index = 0; index < points.length; index += 1) {
    total += _distance(points[index], points[(index + 1) % points.length]);
  }
  return total;
}

double _polygonArea(List<ScanImagePoint> points) {
  var doubledArea = 0.0;
  for (var index = 0; index < points.length; index += 1) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    doubledArea += current.x * next.y - current.y * next.x;
  }
  return doubledArea.abs() / 2;
}

List<ScanImagePoint> _approximateClosedPolygon(
  List<ScanImagePoint> points,
  double epsilon,
) {
  if (points.length <= 4) return List<ScanImagePoint>.from(points);
  var split = 1;
  var farthestSquared = 0.0;
  for (var index = 1; index < points.length; index += 1) {
    final dx = points[index].x - points.first.x;
    final dy = points[index].y - points.first.y;
    final squared = dx * dx + dy * dy;
    if (squared > farthestSquared) {
      farthestSquared = squared;
      split = index;
    }
  }
  final firstArc = points.sublist(0, split + 1);
  final secondArc = [...points.sublist(split), points.first];
  final first = _approximatePolyline(firstArc, epsilon);
  final second = _approximatePolyline(secondArc, epsilon);
  return [
    ...first.take(first.length - 1),
    ...second.take(second.length - 1),
  ];
}

List<ScanImagePoint> _approximatePolyline(
  List<ScanImagePoint> points,
  double epsilon,
) {
  if (points.length <= 2) return List<ScanImagePoint>.from(points);
  final keep = Uint8List(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;
  final ranges = <(int, int)>[(0, points.length - 1)];
  while (ranges.isNotEmpty) {
    final (start, end) = ranges.removeLast();
    var farthest = -1;
    var maximumDistance = epsilon;
    for (var index = start + 1; index < end; index += 1) {
      final distance = _pointLineDistance(points[index], points[start], points[end]);
      if (distance > maximumDistance) {
        maximumDistance = distance;
        farthest = index;
      }
    }
    if (farthest >= 0) {
      keep[farthest] = 1;
      ranges.add((start, farthest));
      ranges.add((farthest, end));
    }
  }
  return [
    for (var index = 0; index < points.length; index += 1)
      if (keep[index] != 0) points[index],
  ];
}

double _pointLineDistance(
  ScanImagePoint point,
  ScanImagePoint start,
  ScanImagePoint end,
) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return _distance(point, start);
  return ((dy * point.x - dx * point.y + end.x * start.y - end.y * start.x)
              .abs()) /
      length;
}

class _Rectangle {
  const _Rectangle(this.points, this.width, this.height);

  final List<ScanImagePoint> points;
  final double width;
  final double height;
}

_Rectangle? _minimumAreaRectangle(List<ScanImagePoint> hull) {
  _Rectangle? best;
  var bestArea = double.infinity;
  for (var index = 0; index < hull.length; index += 1) {
    final start = hull[index];
    final end = hull[(index + 1) % hull.length];
    final angle = math.atan2(end.y - start.y, end.x - start.x);
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    var minimumX = double.infinity;
    var maximumX = double.negativeInfinity;
    var minimumY = double.infinity;
    var maximumY = double.negativeInfinity;
    for (final point in hull) {
      final rotatedX = point.x * cosine + point.y * sine;
      final rotatedY = -point.x * sine + point.y * cosine;
      minimumX = math.min(minimumX, rotatedX);
      maximumX = math.max(maximumX, rotatedX);
      minimumY = math.min(minimumY, rotatedY);
      maximumY = math.max(maximumY, rotatedY);
    }
    final width = maximumX - minimumX;
    final height = maximumY - minimumY;
    final area = width * height;
    if (area >= bestArea) continue;
    bestArea = area;
    ScanImagePoint restore(double x, double y) => ScanImagePoint(
      x * cosine - y * sine,
      x * sine + y * cosine,
    );
    best = _Rectangle(
      [
        restore(minimumX, minimumY),
        restore(maximumX, minimumY),
        restore(maximumX, maximumY),
        restore(minimumX, maximumY),
      ],
      width,
      height,
    );
  }
  return best;
}

double _distance(ScanImagePoint left, ScanImagePoint right) => math.sqrt(
  math.pow(left.x - right.x, 2) + math.pow(left.y - right.y, 2),
);

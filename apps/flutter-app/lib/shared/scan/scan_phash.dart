import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const _sourceSize = 1024;
const _dctSize = 64;
const _hashSize = 16;
const _precisionBits = 22;

final _cosines = List.generate(
  _hashSize,
  (frequency) => List.generate(
    _dctSize,
    (index) => math.cos(math.pi * frequency * (2 * index + 1) / (2 * _dctSize)),
    growable: false,
  ),
  growable: false,
);

String encodeScanPhash(Uint8List channel) {
  if (channel.length != _sourceSize * _sourceSize) {
    throw ArgumentError.value(
      channel.length,
      'channel.length',
      'Expected a 1024 x 1024 channel.',
    );
  }

  final resized = resizeScanChannelPillowLanczos(
    channel,
    inputWidth: _sourceSize,
    inputHeight: _sourceSize,
    outputWidth: _dctSize,
    outputHeight: _dctSize,
  );
  final coefficients = _lowFrequencyDct(resized);
  final sorted = [...coefficients]..sort();
  final median = (sorted[127] + sorted[128]) / 2;
  final bytes = Uint8List(32);
  for (var index = 0; index < coefficients.length; index += 1) {
    if (coefficients[index] > median) {
      bytes[index >> 3] |= 1 << (7 - (index & 7));
    }
  }
  return base64UrlEncode(bytes).replaceAll('=', '');
}

Uint8List resizeScanChannelPillowLanczos(
  Uint8List source, {
  required int inputWidth,
  required int inputHeight,
  required int outputWidth,
  required int outputHeight,
}) {
  final horizontalFilter = _LanczosCoefficients.create(
    inputSize: inputWidth,
    outputSize: outputWidth,
  );
  final verticalFilter =
      inputHeight == inputWidth && outputHeight == outputWidth
      ? horizontalFilter
      : _LanczosCoefficients.create(
          inputSize: inputHeight,
          outputSize: outputHeight,
        );
  final horizontal = Uint8List(outputWidth * inputHeight);
  for (var row = 0; row < inputHeight; row += 1) {
    final sourceRow = row * inputWidth;
    final targetRow = row * outputWidth;
    for (var column = 0; column < outputWidth; column += 1) {
      var sum = 1 << (_precisionBits - 1);
      final start = horizontalFilter.starts[column];
      final weights = horizontalFilter.weights[column];
      for (var offset = 0; offset < weights.length; offset += 1) {
        sum += source[sourceRow + start + offset] * weights[offset];
      }
      horizontal[targetRow + column] = _clip8(sum >> _precisionBits);
    }
  }

  final output = Uint8List(outputWidth * outputHeight);
  for (var row = 0; row < outputHeight; row += 1) {
    final rowStart = verticalFilter.starts[row];
    final weights = verticalFilter.weights[row];
    for (var column = 0; column < outputWidth; column += 1) {
      var sum = 1 << (_precisionBits - 1);
      for (var offset = 0; offset < weights.length; offset += 1) {
        sum +=
            horizontal[(rowStart + offset) * outputWidth + column] *
            weights[offset];
      }
      output[row * outputWidth + column] = _clip8(sum >> _precisionBits);
    }
  }
  return output;
}

Uint8List letterboxScanChannelPillowLanczos(
  Uint8List source, {
  required int width,
  required int height,
}) {
  final scale = math.min(_sourceSize / width, _sourceSize / height);
  final resizedWidth = (width * scale).round();
  final resizedHeight = (height * scale).round();
  final resized = resizeScanChannelPillowLanczos(
    source,
    inputWidth: width,
    inputHeight: height,
    outputWidth: resizedWidth,
    outputHeight: resizedHeight,
  );
  final canvas = Uint8List(_sourceSize * _sourceSize)
    ..fillRange(0, _sourceSize * _sourceSize, 255);
  final left = (_sourceSize - resizedWidth) ~/ 2;
  final top = (_sourceSize - resizedHeight) ~/ 2;
  for (var row = 0; row < resizedHeight; row += 1) {
    canvas.setRange(
      (top + row) * _sourceSize + left,
      (top + row) * _sourceSize + left + resizedWidth,
      resized,
      row * resizedWidth,
    );
  }
  return canvas;
}

List<double> _lowFrequencyDct(Uint8List pixels) {
  final vertical = List<double>.filled(_hashSize * _dctSize, 0);
  for (var rowFrequency = 0; rowFrequency < _hashSize; rowFrequency += 1) {
    final rowCosines = _cosines[rowFrequency];
    for (var column = 0; column < _dctSize; column += 1) {
      var sum = 0.0;
      for (var row = 0; row < _dctSize; row += 1) {
        sum += pixels[row * _dctSize + column] * rowCosines[row];
      }
      vertical[rowFrequency * _dctSize + column] = sum;
    }
  }

  final output = List<double>.filled(_hashSize * _hashSize, 0);
  for (var rowFrequency = 0; rowFrequency < _hashSize; rowFrequency += 1) {
    for (
      var columnFrequency = 0;
      columnFrequency < _hashSize;
      columnFrequency += 1
    ) {
      final columnCosines = _cosines[columnFrequency];
      var sum = 0.0;
      for (var column = 0; column < _dctSize; column += 1) {
        sum +=
            vertical[rowFrequency * _dctSize + column] * columnCosines[column];
      }
      output[rowFrequency * _hashSize + columnFrequency] = sum;
    }
  }
  return output;
}

int _clip8(int value) => value.clamp(0, 255);

class _LanczosCoefficients {
  const _LanczosCoefficients({required this.starts, required this.weights});

  final List<int> starts;
  final List<List<int>> weights;

  factory _LanczosCoefficients.create({
    required int inputSize,
    required int outputSize,
  }) {
    final scale = inputSize / outputSize;
    final filterScale = math.max(scale, 1.0);
    final support = 3 * filterScale;
    final starts = <int>[];
    final weights = <List<int>>[];

    for (var output = 0; output < outputSize; output += 1) {
      final center = (output + 0.5) * scale;
      final start = math.max((center - support + 0.5).toInt(), 0);
      final end = math.min((center + support + 0.5).toInt(), inputSize);
      final doubles = <double>[];
      var total = 0.0;
      for (var input = start; input < end; input += 1) {
        final value = _lanczos((input - center + 0.5) / filterScale);
        doubles.add(value);
        total += value;
      }
      starts.add(start);
      weights.add([
        for (final value in doubles)
          _roundAwayFromZero(value / total * (1 << _precisionBits)),
      ]);
    }
    return _LanczosCoefficients(starts: starts, weights: weights);
  }
}

double _lanczos(double value) {
  if (value < -3 || value >= 3) return 0;
  return _sinc(value) * _sinc(value / 3);
}

double _sinc(double value) {
  if (value == 0) return 1;
  final radians = value * math.pi;
  return math.sin(radians) / radians;
}

int _roundAwayFromZero(double value) {
  return value < 0 ? (value - 0.5).toInt() : (value + 0.5).toInt();
}

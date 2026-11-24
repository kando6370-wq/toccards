import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../shared/ui/kando_style.dart';

const cardSharePosterWidth = 1080;
const cardSharePosterHeight = 1980;

const _logicalWidth = 360.0;
const _logicalHeight = 660.0;
const _pixelRatio = 3.0;

Future<Uint8List> renderCardSharePoster({
  required Uint8List imageBytes,
  required String name,
  required String setName,
  required String marketPrice,
  required Uri cardUrl,
}) async {
  if (imageBytes.isEmpty) {
    throw const FormatException('The card image is empty.');
  }
  if (name.trim().isEmpty || setName.trim().isEmpty) {
    throw const FormatException('Card name and set name are required.');
  }
  if ((cardUrl.scheme != 'https' && cardUrl.scheme != 'http') ||
      cardUrl.host.isEmpty) {
    throw const FormatException('The card share URL is invalid.');
  }

  final codec = await ui.instantiateImageCodec(imageBytes);
  ui.Image? cardImage;
  ui.PictureRecorder? recorder;
  ui.Picture? picture;
  ui.Image? posterImage;
  try {
    cardImage = (await codec.getNextFrame()).image;
    recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    _paintPoster(
      canvas,
      cardImage: cardImage,
      name: name.trim(),
      setName: setName.trim(),
      marketPrice: marketPrice.trim(),
      cardUrl: cardUrl,
    );
    picture = recorder.endRecording();
    recorder = null;
    posterImage = await picture.toImage(
      cardSharePosterWidth,
      cardSharePosterHeight,
    );
    final data = await posterImage.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('The card share poster could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    recorder?.endRecording().dispose();
    posterImage?.dispose();
    picture?.dispose();
    cardImage?.dispose();
    codec.dispose();
  }
}

void _paintPoster(
  Canvas canvas, {
  required ui.Image cardImage,
  required String name,
  required String setName,
  required String marketPrice,
  required Uri cardUrl,
}) {
  const bounds = Rect.fromLTWH(0, 0, _logicalWidth, _logicalHeight);
  canvas.drawRect(bounds, Paint()..color = KandoColors.ink);
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(0, -0.55),
        radius: 0.95,
        colors: [Color(0x33464835), Color(0x0010100B)],
      ).createShader(bounds),
  );

  _paintText(
    canvas,
    text: 'CardScanFox',
    offset: const Offset(24, 23),
    width: 312,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w700,
      color: KandoColors.accent,
      letterSpacing: 0,
    ),
  );

  const cardFrame = Rect.fromLTWH(72, 52, 216, 302);
  canvas.drawRRect(
    RRect.fromRectAndRadius(cardFrame, const Radius.circular(12)),
    Paint()..color = KandoColors.surface,
  );
  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(cardFrame, const Radius.circular(10)),
  );
  _paintContainedImage(canvas, cardImage, cardFrame.deflate(8));
  canvas.restore();
  canvas.drawRRect(
    RRect.fromRectAndRadius(cardFrame, const Radius.circular(12)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = KandoColors.border,
  );

  _paintText(
    canvas,
    text: name,
    offset: const Offset(24, 376),
    width: 312,
    maxLines: 2,
    style: const TextStyle(
      fontFamily: 'Fraunces',
      fontSize: 25,
      height: 31 / 25,
      fontWeight: FontWeight.w600,
      color: KandoColors.text,
      letterSpacing: 0,
    ),
  );
  _paintText(
    canvas,
    text: setName,
    offset: const Offset(24, 442),
    width: 312,
    maxLines: 1,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 13,
      height: 18 / 13,
      color: KandoColors.mutedText,
      letterSpacing: 0,
    ),
  );
  _paintText(
    canvas,
    text: marketPrice.isEmpty ? '--' : marketPrice,
    offset: const Offset(24, 458),
    width: 312,
    maxLines: 1,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 19,
      height: 26 / 19,
      fontWeight: FontWeight.w600,
      color: KandoColors.money,
      letterSpacing: 0,
    ),
  );

  const qrPanel = Rect.fromLTWH(24, 486, 312, 150);
  canvas.drawRRect(
    RRect.fromRectAndRadius(qrPanel, const Radius.circular(12)),
    Paint()..color = KandoColors.surface,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(qrPanel, const Radius.circular(12)),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = KandoColors.borderSubtle,
  );

  const qrBackground = Rect.fromLTWH(32, 494, 134, 134);
  canvas.drawRRect(
    RRect.fromRectAndRadius(qrBackground, const Radius.circular(8)),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final qrPainter = QrPainter(
    data: cardUrl.toString(),
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Color(0xFF000000),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Color(0xFF000000),
    ),
  );
  canvas.save();
  canvas.translate(48, 510);
  qrPainter.paint(canvas, const Size.square(102));
  canvas.restore();

  _paintText(
    canvas,
    text: 'SCAN TO VIEW CARD',
    offset: const Offset(180, 516),
    width: 132,
    maxLines: 2,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w700,
      color: KandoColors.text,
      letterSpacing: 0,
    ),
  );
  _paintText(
    canvas,
    text: 'Open card details and current market information.',
    offset: const Offset(180, 562),
    width: 132,
    maxLines: 3,
    style: const TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 16 / 11,
      color: KandoColors.mutedText,
      letterSpacing: 0,
    ),
  );
}

void _paintContainedImage(Canvas canvas, ui.Image image, Rect destination) {
  final source = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final fitted = applyBoxFit(BoxFit.contain, source.size, destination.size);
  final sourceRect = Alignment.center.inscribe(fitted.source, source);
  final destinationRect = Alignment.center.inscribe(
    fitted.destination,
    destination,
  );
  canvas.drawImageRect(
    image,
    sourceRect,
    destinationRect,
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.high,
  );
}

void _paintText(
  Canvas canvas, {
  required String text,
  required Offset offset,
  required double width,
  required TextStyle style,
  int? maxLines,
  TextAlign textAlign = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: textAlign,
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '...',
  )..layout(maxWidth: width);
  try {
    painter.paint(canvas, offset);
  } finally {
    painter.dispose();
  }
}

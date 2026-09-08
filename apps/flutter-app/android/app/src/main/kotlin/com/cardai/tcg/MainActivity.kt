package com.cardai.tcg

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    private val imageExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var scanModelRuntime: ScanModelRuntime? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        scanModelRuntime = ScanModelRuntime(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.cardai.tcg/scan-image-processor",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareDetection", "rectifyCard" -> imageExecutor.execute {
                    try {
                        val value = when (call.method) {
                            "prepareDetection" -> prepareDetection(call)
                            else -> rectifyCard(call)
                        }
                        mainHandler.post { result.success(value) }
                    } catch (error: Throwable) {
                        mainHandler.post {
                            result.error(
                                "scan_image_processing_failed",
                                error.message ?: "The image could not be processed.",
                                null,
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        scanModelRuntime?.close()
        scanModelRuntime = null
        imageExecutor.shutdown()
        super.onDestroy()
    }

    private fun prepareDetection(call: MethodCall): Map<String, Any> {
        val bytes = call.argument<ByteArray>("image")
            ?: throw IllegalArgumentException("Image bytes are required.")
        val maximumSize = call.argument<Int>("maximum_size")
            ?: throw IllegalArgumentException("Maximum size is required.")
        require(maximumSize > 0) { "Maximum size must be positive." }

        val source = decodeNormalized(bytes)
        try {
            val scale = min(maximumSize.toDouble() / source.width, maximumSize.toDouble() / source.height)
            val resizedWidth = max(1, min(maximumSize, Math.rint(source.width * scale).toInt()))
            val resizedHeight = max(1, min(maximumSize, Math.rint(source.height * scale).toInt()))
            val resized = if (source.width == resizedWidth && source.height == resizedHeight) {
                source
            } else {
                Bitmap.createScaledBitmap(source, resizedWidth, resizedHeight, true)
            }
            try {
                return mapOf(
                    "source_width" to source.width,
                    "source_height" to source.height,
                    "resized_width" to resizedWidth,
                    "resized_height" to resizedHeight,
                    "rgb_bytes" to rgbBytes(resized),
                )
            } finally {
                if (resized !== source) resized.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    private fun rectifyCard(call: MethodCall): Map<String, Any> {
        val bytes = call.argument<ByteArray>("image")
            ?: throw IllegalArgumentException("Image bytes are required.")
        val cornerValues = call.argument<List<Number>>("corners")
            ?: throw IllegalArgumentException("Card corners are required.")
        val cardWidth = call.argument<Int>("card_width")
            ?: throw IllegalArgumentException("Card width is required.")
        val cardHeight = call.argument<Int>("card_height")
            ?: throw IllegalArgumentException("Card height is required.")
        val embeddingSize = call.argument<Int>("embedding_size")
            ?: throw IllegalArgumentException("Embedding size is required.")
        val jpegQuality = call.argument<Int>("jpeg_quality") ?: 85
        require(cornerValues.size == 8) { "Exactly four card corners are required." }
        require(cornerValues.all { it.toDouble().isFinite() }) {
            "Card corners must be finite."
        }
        require(cardWidth > 0 && cardHeight > 0 && embeddingSize > 0) {
            "Image dimensions must be positive."
        }

        val source = decodeNormalized(bytes)
        try {
            val card = Bitmap.createBitmap(cardWidth, cardHeight, Bitmap.Config.ARGB_8888)
            try {
                val sourcePoints = FloatArray(8) { cornerValues[it].toFloat() }
                val destinationPoints = floatArrayOf(
                    0f,
                    0f,
                    (cardWidth - 1).toFloat(),
                    0f,
                    (cardWidth - 1).toFloat(),
                    (cardHeight - 1).toFloat(),
                    0f,
                    (cardHeight - 1).toFloat(),
                )
                val transform = Matrix()
                check(transform.setPolyToPoly(sourcePoints, 0, destinationPoints, 0, 4)) {
                    "The detected card corners cannot be transformed."
                }
                val paint = Paint(
                    Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG,
                )
                Canvas(card).drawBitmap(source, transform, paint)

                val encoded = ByteArrayOutputStream()
                check(card.compress(Bitmap.CompressFormat.JPEG, jpegQuality, encoded)) {
                    "The corrected card image could not be encoded."
                }
                val embedding = Bitmap.createScaledBitmap(card, embeddingSize, embeddingSize, true)
                try {
                    return mapOf(
                        "card_image_bytes" to encoded.toByteArray(),
                        "embedding_rgb_bytes" to rgbBytes(embedding),
                    )
                } finally {
                    if (embedding !== card) embedding.recycle()
                }
            } finally {
                card.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    private fun decodeNormalized(bytes: ByteArray): Bitmap {
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("The selected image is invalid.")
        val orientation = try {
            ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Throwable) {
            ExifInterface.ORIENTATION_NORMAL
        }
        val transform = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> transform.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                transform.setRotate(180f)
                transform.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                transform.setRotate(90f)
                transform.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> transform.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                transform.setRotate(-90f)
                transform.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> transform.setRotate(-90f)
        }
        if (transform.isIdentity) return decoded
        return try {
            Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
        } finally {
            decoded.recycle()
        }
    }

    private fun rgbBytes(bitmap: Bitmap): ByteArray {
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        val result = ByteArray(pixels.size * 3)
        for (index in pixels.indices) {
            val color = pixels[index]
            val offset = index * 3
            result[offset] = ((color ushr 16) and 0xff).toByte()
            result[offset + 1] = ((color ushr 8) and 0xff).toByte()
            result[offset + 2] = (color and 0xff).toByte()
        }
        return result
    }
}

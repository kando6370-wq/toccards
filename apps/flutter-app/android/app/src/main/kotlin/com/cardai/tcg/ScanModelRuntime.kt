package com.cardai.tcg

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OnnxValue
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.concurrent.Executors

class ScanModelRuntime(
    private val context: Context,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val environment = OrtEnvironment.getEnvironment()
    private var detectionSession: OrtSession? = null
    private var embeddingSession: OrtSession? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "runDetection" && call.method != "runEmbedding") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val tensor = call.argument<FloatArray>("tensor")
            if (tensor == null) {
                result.error("invalid_model_input", "A float tensor is required.", null)
                return@setMethodCallHandler
            }
            executor.execute {
                try {
                    val output = when (call.method) {
                        "runDetection" -> runDetection(tensor)
                        else -> runEmbedding(tensor)
                    }
                    mainHandler.post { result.success(output) }
                } catch (error: Throwable) {
                    mainHandler.post {
                        result.error(
                            "scan_model_runtime_failed",
                            error.message ?: "The on-device model could not run.",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun runDetection(tensor: FloatArray): Map<String, Any> {
        require(tensor.size == DETECTION_ELEMENTS) { "Invalid detection tensor size." }
        val session = detectionSession ?: createSession(DETECTION_MODEL).also {
            detectionSession = it
        }
        OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(tensor),
            longArrayOf(1, 3, 640, 640),
        ).use { input ->
            session.run(mapOf("input" to input)).use { outputs ->
                val detections = outputs.get("dets").orElseThrow()
                val masks = outputs.get("masks").orElseThrow()
                return mapOf(
                    "dets" to floatValues(detections),
                    "dets_shape" to shape(detections),
                    "masks" to floatValues(masks),
                    "masks_shape" to shape(masks),
                )
            }
        }
    }

    private fun runEmbedding(tensor: FloatArray): FloatArray {
        require(tensor.size == EMBEDDING_ELEMENTS) { "Invalid embedding tensor size." }
        val session = embeddingSession ?: createSession(EMBEDDING_MODEL).also {
            embeddingSession = it
        }
        OnnxTensor.createTensor(
            environment,
            FloatBuffer.wrap(tensor),
            longArrayOf(1, 3, 384, 384),
        ).use { input ->
            session.run(mapOf("image" to input)).use { outputs ->
                return floatValues(outputs.get("embedding").orElseThrow())
            }
        }
    }

    private fun createSession(assetPath: String): OrtSession {
        val model = context.assets.open(assetPath).use { it.readBytes() }
        return OrtSession.SessionOptions().use { options ->
            options.addCPU(true)
            environment.createSession(model, options)
        }
    }

    private fun floatValues(value: OnnxValue): FloatArray {
        require(value is OnnxTensor) { "Expected a tensor output." }
        val buffer = value.floatBuffer.orElseThrow().duplicate()
        val result = FloatArray(buffer.remaining())
        buffer.get(result)
        return result
    }

    private fun shape(value: OnnxValue): List<Int> {
        require(value is OnnxTensor) { "Expected a tensor output." }
        return value.info.shape.map { dimension -> Math.toIntExact(dimension) }
    }

    override fun close() {
        executor.shutdown()
        detectionSession?.close()
        embeddingSession?.close()
    }

    private companion object {
        const val CHANNEL = "com.cardai.tcg/scan-model-runtime"
        const val DETECTION_MODEL = "models/rtmdet_ins_tiny_card_640_fp16.ort"
        const val EMBEDDING_MODEL = "models/pe_core_t16_image_fp16.ort"
        const val DETECTION_ELEMENTS = 3 * 640 * 640
        const val EMBEDDING_ELEMENTS = 3 * 384 * 384
    }
}

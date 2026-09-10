package com.cardai.tcg

import kotlin.math.floor

internal object OpenCvLinearRgbScaler {
    fun resizeArgb(
        source: IntArray,
        sourceWidth: Int,
        sourceHeight: Int,
        width: Int,
        height: Int,
    ): ByteArray {
        require(sourceWidth > 0 && sourceHeight > 0 && width > 0 && height > 0) {
            "Image dimensions must be positive."
        }
        require(source.size == sourceWidth * sourceHeight) {
            "Source pixels do not match the image dimensions."
        }

        val xScale = sourceWidth.toDouble() / width
        val yScale = sourceHeight.toDouble() / height
        val leftIndexes = IntArray(width)
        val rightIndexes = IntArray(width)
        val xWeights = DoubleArray(width)
        for (x in 0 until width) {
            val coordinate = (x + 0.5) * xScale - 0.5
            val lower = floor(coordinate).toInt()
            leftIndexes[x] = lower.coerceIn(0, sourceWidth - 1)
            rightIndexes[x] = (lower + 1).coerceIn(0, sourceWidth - 1)
            xWeights[x] = coordinate - lower
        }

        val output = ByteArray(width * height * 3)
        for (y in 0 until height) {
            val coordinate = (y + 0.5) * yScale - 0.5
            val lower = floor(coordinate).toInt()
            val top = lower.coerceIn(0, sourceHeight - 1)
            val bottom = (lower + 1).coerceIn(0, sourceHeight - 1)
            val yWeight = coordinate - lower
            for (x in 0 until width) {
                val left = leftIndexes[x]
                val right = rightIndexes[x]
                val topLeft = source[top * sourceWidth + left]
                val topRight = source[top * sourceWidth + right]
                val bottomLeft = source[bottom * sourceWidth + left]
                val bottomRight = source[bottom * sourceWidth + right]
                val target = (y * width + x) * 3
                for (channelIndex in channelShifts.indices) {
                    val shift = channelShifts[channelIndex]
                    val topLeftChannel = channel(topLeft, shift)
                    val topRightChannel = channel(topRight, shift)
                    val bottomLeftChannel = channel(bottomLeft, shift)
                    val bottomRightChannel = channel(bottomRight, shift)
                    val topValue = topLeftChannel +
                        (topRightChannel - topLeftChannel) * xWeights[x]
                    val bottomValue = bottomLeftChannel +
                        (bottomRightChannel - bottomLeftChannel) * xWeights[x]
                    val value = topValue + (bottomValue - topValue) * yWeight
                    output[target + channelIndex] = Math.rint(value).toInt().coerceIn(0, 255).toByte()
                }
            }
        }
        return output
    }

    private fun channel(color: Int, shift: Int): Int = (color ushr shift) and 0xff

    private val channelShifts = intArrayOf(16, 8, 0)
}

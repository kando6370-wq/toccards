package com.cardai.tcg

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class OpenCvLinearRgbScalerTest {
    @Test
    fun matchesOpenCvLinearReferencePixels() {
        val source = intArrayOf(
            rgb(0, 0, 0),
            rgb(100, 10, 20),
            rgb(200, 20, 40),
            rgb(20, 100, 200),
            rgb(120, 110, 220),
            rgb(220, 120, 240),
        )

        val resized = OpenCvLinearRgbScaler.resizeArgb(
            source,
            sourceWidth = 3,
            sourceHeight = 2,
            width = 2,
            height = 3,
        )

        val expected = bytes(
            25, 2, 5,
            175, 17, 35,
            35, 53, 105,
            185, 68, 135,
            45, 102, 205,
            195, 117, 235,
        )
        expected.indices.forEach { index ->
            val difference = abs(
                (expected[index].toInt() and 0xff) - (resized[index].toInt() and 0xff),
            )
            assertTrue("Channel $index differs from OpenCV by $difference", difference <= 1)
        }
    }

    @Test
    fun preservesPixelsAtTheOriginalSize() {
        val source = intArrayOf(rgb(1, 2, 3), rgb(254, 253, 252))

        assertArrayEquals(
            bytes(1, 2, 3, 254, 253, 252),
            OpenCvLinearRgbScaler.resizeArgb(
                source,
                sourceWidth = 2,
                sourceHeight = 1,
                width = 2,
                height = 1,
            ),
        )
    }

    private fun rgb(red: Int, green: Int, blue: Int): Int =
        (0xff shl 24) or (red shl 16) or (green shl 8) or blue

    private fun bytes(vararg values: Int): ByteArray =
        ByteArray(values.size) { values[it].toByte() }
}

package com.termisol.vr

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Renders a terminal cell grid into an Android [Bitmap] using the standard
 * [Canvas] API.
 *
 * The binary [cells] array is expected to be in the format produced by
 * [VrFrameEncoder] on the Dart side: 13 bytes per cell
 * (codepoint + foreground + background + flags).
 */
class TerminalBitmapRenderer(
    private val cols: Int,
    private val rows: Int,
    private val cellWidth: Float = 16f,
    private val cellHeight: Float = 32f,
) {
    private val bitmapWidth = (cols * cellWidth).toInt()
    private val bitmapHeight = (rows * cellHeight).toInt()
    private val bitmap: Bitmap = Bitmap.createBitmap(bitmapWidth, bitmapHeight, Bitmap.Config.ARGB_8888)
    private val canvas = Canvas(bitmap)
    private val textPaint = Paint().apply {
        typeface = Typeface.MONOSPACE
        textSize = cellHeight * 0.75f
        isAntiAlias = true
    }
    private val bgPaint = Paint()

    /** Render [cells] into a Bitmap and return it. */
    fun render(cells: ByteArray, rows: Int, cols: Int): Bitmap {
        canvas.drawColor(Color.BLACK)

        val buffer = ByteBuffer.wrap(cells).order(ByteOrder.LITTLE_ENDIAN)

        for (r in 0 until rows) {
            for (c in 0 until cols) {
                if (buffer.remaining() < 13) break

                val codepoint = buffer.int
                val fg = buffer.int
                val bg = buffer.int
                val flags = buffer.get().toInt()

                val x = c * cellWidth
                val y = r * cellHeight

                // Draw background if non-default.
                if (bg != 0) {
                    bgPaint.color = bg or 0xFF000000.toInt()
                    canvas.drawRect(x, y, x + cellWidth, y + cellHeight, bgPaint)
                }

                // Draw character.
                if (codepoint != 0) {
                    textPaint.color = fg or 0xFF000000.toInt()
                    // Simple faint support.
                    if (flags and 0x02 != 0) {
                        textPaint.alpha = 128
                    } else {
                        textPaint.alpha = 255
                    }
                    val char = codepoint.toChar().toString()
                    canvas.drawText(char, x, y + cellHeight * 0.8f, textPaint)
                }
            }
        }

        return bitmap
    }
}

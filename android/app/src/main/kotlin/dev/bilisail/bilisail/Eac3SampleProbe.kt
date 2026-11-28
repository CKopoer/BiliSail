package dev.bilisail.bilisail

import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableBitArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.Ac3Util

/** Inspects an access unit when the container only signals ordinary E-AC-3. */
@UnstableApi
internal class Eac3SampleProbe {
    // One independent syncframe and up to eight dependent syncframes, at most 4096 bytes each.
    private val prefix = ByteArray(9 * 4096)
    private var bytesReceived = 0L

    fun reset() {
        bytesReceived = 0
    }

    fun append(data: ByteArray, offset: Int, length: Int) {
        if (bytesReceived < prefix.size) {
            val destination = bytesReceived.toInt()
            val count = minOf(length, prefix.size - destination)
            data.copyInto(prefix, destination, offset, offset + count)
        }
        bytesReceived += length
    }

    fun containsJoc(size: Int, offset: Int): Boolean {
        // TrackOutput may already have received part of the next sample.
        val end = bytesReceived - offset
        val start = end - size
        if (start < 0 || start >= prefix.size || size <= 0) return false
        val limit = minOf(end, prefix.size.toLong()).toInt()
        val bits = ParsableBitArray(prefix, limit)
        var pos = start.toInt()
        try {
            while (limit - pos >= 7) {
                if (prefix[pos] != 0x0b.toByte() || prefix[pos + 1] != 0x77.toByte()) return false
                val bitstreamId = (prefix[pos + 5].toInt() and 0xff) ushr 3
                if (bitstreamId > 16) return false
                bits.setPosition(pos * 8)
                val frame = Ac3Util.parseAc3SyncframeInfo(bits)
                if (frame.mimeType == null || frame.frameSize !in 7..(limit - pos)) return false
                if (bitstreamId > 10 && frame.streamType == Ac3Util.SyncFrameInfo.STREAM_TYPE_UNDEFINED) return false
                pos += frame.frameSize
                if (bits.position > pos * 8) return false
                if (frame.mimeType == MimeTypes.AUDIO_E_AC3_JOC) return true
            }
        } catch (_: IndexOutOfBoundsException) {
            return false
        } catch (_: IllegalStateException) {
            return false
        }
        return false
    }
}

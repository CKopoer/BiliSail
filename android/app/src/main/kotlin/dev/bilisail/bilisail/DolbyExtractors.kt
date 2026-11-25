package dev.bilisail.bilisail

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableBitArray
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.*

/** Matroska A_EAC3 and older MP4 init segments may omit the JOC indication. */
@UnstableApi
internal fun dolbyExtractors() = ExtractorsFactory {
    DefaultExtractorsFactory().createExtractors().map { extractor ->
        object : ForwardingExtractor(extractor) {
            override fun init(output: ExtractorOutput) {
                super.init(object : ForwardingExtractorOutput(output) {
                    override fun track(id: Int, type: Int): TrackOutput {
                        val track = super.track(id, type)
                        return if (type == C.TRACK_TYPE_AUDIO) DolbyTrackOutput(track) else track
                    }
                })
            }
        }
    }.toTypedArray()
}

@UnstableApi
private class DolbyTrackOutput(track: TrackOutput) : ForwardingTrackOutput(track) {
    private var pending: Format? = null
    private val prefix = ByteArray(4096)
    private var count = 0
    override fun format(format: Format) {
        count = 0
        pending = format.takeIf { it.sampleMimeType == MimeTypes.AUDIO_E_AC3 }
        if (pending == null) super.format(format)
    }
    private fun collect(data: ByteArray, offset: Int, length: Int) {
        val size = minOf(length, prefix.size - count)
        if (size <= 0) return
        data.copyInto(prefix, count, offset, offset + size)
        count += size
    }
    override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean): Int =
        sampleData(input, length, allowEndOfInput, TrackOutput.SAMPLE_DATA_PART_MAIN)
    override fun sampleData(data: ParsableByteArray, length: Int) =
        sampleData(data, length, TrackOutput.SAMPLE_DATA_PART_MAIN)
    override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int): Int {
        if (pending == null || sampleDataPart != TrackOutput.SAMPLE_DATA_PART_MAIN)
            return super.sampleData(input, length, allowEndOfInput, sampleDataPart)
        return super.sampleData(DataReader { data, offset, len ->
            input.read(data, offset, len).also { if (it > 0) collect(data, offset, it) }
        }, length, allowEndOfInput, sampleDataPart)
    }
    override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
        if (pending != null && sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN)
            collect(data.data, data.position, length)
        super.sampleData(data, length, sampleDataPart)
    }
    override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
        pending?.let { format ->
            val joc = count >= 7 && prefix[0] == 0x0b.toByte() && prefix[1] == 0x77.toByte() &&
                try {
                    Ac3Util.parseAc3SyncframeInfo(ParsableBitArray(prefix, count)).mimeType == MimeTypes.AUDIO_E_AC3_JOC
                } catch (_: IndexOutOfBoundsException) { false } catch (_: IllegalStateException) { false }
            super.format(if (joc) format.buildUpon().setSampleMimeType(MimeTypes.AUDIO_E_AC3_JOC).build() else format)
            pending = null
        }
        super.sampleMetadata(timeUs, flags, size, offset, cryptoData)
    }
}

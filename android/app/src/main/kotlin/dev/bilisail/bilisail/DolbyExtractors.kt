package dev.bilisail.bilisail

import androidx.media3.common.C
import androidx.media3.common.DataReader
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
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
    private val probe by lazy(LazyThreadSafetyMode.NONE) { Eac3SampleProbe() }

    override fun format(format: Format) {
        pending = format.takeIf { it.sampleMimeType == MimeTypes.AUDIO_E_AC3 }
        if (pending == null) super.format(format) else probe.reset()
    }
    override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean): Int =
        sampleData(input, length, allowEndOfInput, TrackOutput.SAMPLE_DATA_PART_MAIN)
    override fun sampleData(data: ParsableByteArray, length: Int) =
        sampleData(data, length, TrackOutput.SAMPLE_DATA_PART_MAIN)
    override fun sampleData(input: DataReader, length: Int, allowEndOfInput: Boolean, sampleDataPart: Int): Int {
        if (pending == null || sampleDataPart != TrackOutput.SAMPLE_DATA_PART_MAIN)
            return super.sampleData(input, length, allowEndOfInput, sampleDataPart)
        return super.sampleData(DataReader { data, offset, len ->
            input.read(data, offset, len).also { if (it > 0) probe.append(data, offset, it) }
        }, length, allowEndOfInput, sampleDataPart)
    }
    override fun sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
        if (pending != null && sampleDataPart == TrackOutput.SAMPLE_DATA_PART_MAIN)
            probe.append(data.data, data.position, length)
        super.sampleData(data, length, sampleDataPart)
    }
    override fun sampleMetadata(timeUs: Long, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
        pending?.let { format ->
            val joc = flags and C.BUFFER_FLAG_ENCRYPTED == 0 && probe.containsJoc(size, offset)
            super.format(if (joc) format.buildUpon().setSampleMimeType(MimeTypes.AUDIO_E_AC3_JOC).build() else format)
            pending = null
        }
        super.sampleMetadata(timeUs, flags, size, offset, cryptoData)
    }
}

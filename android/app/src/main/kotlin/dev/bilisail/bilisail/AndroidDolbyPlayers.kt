package dev.bilisail.bilisail

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodecList
import android.media.audiofx.LoudnessEnhancer
import android.net.Uri
import android.view.Display
import androidx.annotation.RequiresApi
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.pow
import kotlin.math.roundToInt

/** A single platform player owns both tracks. No independently running audio player. */
@UnstableApi
@RequiresApi(29)
internal class AndroidDolbyPlayers(
    private val context: Context, messenger: BinaryMessenger,
    private val createOutput: (Int, Int) -> HdrVideoSurfaces.Output,
    private val releaseOutput: (Long) -> Unit,
    private val supportsVideoHdr: () -> IntArray,
) {
    private val channel = MethodChannel(messenger, "bilisail/dolby_player")
    private val sessions = mutableMapOf<Long, Session>()
    private val codecs by lazy {
        MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder }
    }

    init {
        channel.setMethodCallHandler { call, result ->
            val id = call.argument<Number>("id")?.toLong()
            if (id == null) {
                result.error("argument", "Missing player ID", null)
                return@setMethodCallHandler
            }
            try {
                val session = sessions[id]
                when (call.method) {
                    "open" -> {
                        if (session != null) { result.error("duplicate", "Player exists", null); return@setMethodCallHandler }
                        val buffer = requireNotNull(call.argument<Number>("bufferMs")).toLong()
                            .coerceIn(1, Int.MAX_VALUE.toLong()).toInt()
                        val loadControl = DefaultLoadControl.Builder().setBufferDurationsMs(
                            buffer, buffer, minOf(buffer, 1000), minOf(buffer, 2000)).build()
                        val player = Session(ExoPlayer.Builder(context).setLoadControl(loadControl).build())
                        sessions[id] = player
                        val source = requireNotNull(call.argument<String>("media"))
                        val audio = call.argument<String>("audio")
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        val http = DefaultHttpDataSource.Factory().setDefaultRequestProperties(headers)
                        val factory = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context, http), dolbyExtractors())
                        fun track(url: String) = factory.createMediaSource(MediaItem.fromUri(Uri.parse(url)))
                        val media = track(source)
                        player.exo.setMediaSource(if (audio == null) media else MergingMediaSource(media, track(audio)),
                            call.argument<Number>("position")?.toLong() ?: 0)
                        player.volume = (call.argument<Number>("volume")?.toFloat() ?: 100f) / 100f
                        player.applyVolume()
                        player.exo.prepare()
                        result.success(null)
                    }
                    "release" -> { sessions.remove(id)?.close(); result.success(null) }
                    "state" -> result.success(session?.state())
                    else -> {
                        if (session == null) { result.error("closed", "Player closed", null); return@setMethodCallHandler }
                        when (call.method) {
                            "play" -> session.exo.play()
                            "pause" -> session.exo.pause()
                            "rate" -> session.exo.setPlaybackSpeed(requireNotNull(call.argument<Number>("value")).toFloat())
                            "volume" -> {
                                session.volume = requireNotNull(call.argument<Number>("value")).toFloat()
                                session.applyVolume()
                            }
                            "gain" -> {
                                session.gain = requireNotNull(call.argument<Number>("value")).toDouble()
                                session.applyVolume()
                            }
                            "seek" -> session.exo.seekTo(requireNotNull(call.argument<Number>("value")).toLong())
                            else -> { result.notImplemented(); return@setMethodCallHandler }
                        }
                        result.success(null)
                    }
                }
            } catch (error: RuntimeException) {
                if (call.method == "open") sessions.remove(id)?.close()
                result.error("dolby_playback", error.javaClass.simpleName, null)
            }
        }
    }

    private inner class Session(val exo: ExoPlayer) : Player.Listener, AnalyticsListener {
        private var output: HdrVideoSurfaces.Output? = null
        private var audioDecoder: String? = null
        private var videoDecoder: String? = null
        private var encoding: Int? = null
        private var channels: Int? = null
        private var sampleRate: Int? = null
        private var rendered = false
        private var rejected = false
        var volume = 1f
        var gain = 0.0
        private var gainEffect: LoudnessEnhancer? = null

        fun applyVolume() {
            val amplitude = volume * 10.0.pow(gain / 20)
            exo.volume = amplitude.coerceIn(0.0, 1.0).toFloat()
            if (amplitude > 1 && exo.audioSessionId != C.AUDIO_SESSION_ID_UNSET) {
                val effect = gainEffect ?: LoudnessEnhancer(exo.audioSessionId).also { gainEffect = it }
                effect.setTargetGain((2000 * kotlin.math.log10(amplitude)).roundToInt())
                effect.enabled = true
            } else {
                gainEffect?.release()
                gainEffect = null
            }
        }

        init { exo.addListener(this); exo.addAnalyticsListener(this) }

        override fun onTracksChanged(tracks: Tracks) {
            if (tracks.groups.isEmpty()) return
            val formats = tracks.groups.flatMap { group ->
                (0 until group.length).filter(group::isTrackSelected).map(group::getTrackFormat)
            }
            if (formats.none { it.sampleMimeType == MimeTypes.AUDIO_E_AC3_JOC }) { rejected = true; return }
            val video = formats.firstOrNull { MimeTypes.isVideo(it.sampleMimeType) } ?: return
            val displays = supportsVideoHdr()
            val dolby = video.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION
            val hdrType = when {
                dolby -> Display.HdrCapabilities.HDR_TYPE_DOLBY_VISION
                video.colorInfo?.colorTransfer == C.COLOR_TRANSFER_ST2084 -> Display.HdrCapabilities.HDR_TYPE_HDR10
                video.colorInfo?.colorTransfer == C.COLOR_TRANSFER_HLG -> Display.HdrCapabilities.HDR_TYPE_HLG
                else -> null
            }
            if ((hdrType != null && hdrType !in displays) ||
                video.width !in 1..16384 || video.height !in 1..16384) { rejected = true; return }
            if (output == null) {
                try {
                    output = createOutput(video.width, video.height)
                    exo.setVideoSurface(output?.surface)
                } catch (_: RuntimeException) { rejected = true }
            }
        }

        override fun onRenderedFirstFrame() { rendered = true }
        override fun onAudioDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String,
            initializedTimestampMs: Long, initializationDurationMs: Long) { audioDecoder = decoderName }
        override fun onVideoDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String,
            initializedTimestampMs: Long, initializationDurationMs: Long) { videoDecoder = decoderName }
        override fun onAudioTrackInitialized(eventTime: AnalyticsListener.EventTime, audioTrackConfig: AudioSink.AudioTrackConfig) {
            encoding = audioTrackConfig.encoding
            channels = Integer.bitCount(audioTrackConfig.channelConfig)
            sampleRate = audioTrackConfig.sampleRate
        }

        fun state(): Map<String, Any?> {
            val video = exo.videoFormat
            if (video?.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION && videoDecoder != null &&
                codecs.none { it.name == videoDecoder && MimeTypes.VIDEO_DOLBY_VISION in it.supportedTypes }) rejected = true
            val audio = exo.audioFormat
            val jocDecoder = audioDecoder?.let { decoder ->
                codecs.any { it.name == decoder && MimeTypes.AUDIO_E_AC3_JOC in it.supportedTypes }
            } == true
            return mapOf(
                "failed" to (rejected || exo.playerError != null),
                "ready" to (exo.playbackState == Player.STATE_READY),
                "buffering" to (exo.playbackState == Player.STATE_BUFFERING),
                "ended" to (exo.playbackState == Player.STATE_ENDED),
                "position" to exo.currentPosition, "duration" to exo.duration.coerceAtLeast(0),
                "buffered" to exo.bufferedPosition, "surface" to output?.reference,
                "frame" to rendered, "width" to exo.videoSize.width, "height" to exo.videoSize.height,
                "video" to video?.sampleMimeType, "videoDecoder" to videoDecoder,
                "audio" to audio?.sampleMimeType, "audioDecoder" to audioDecoder, "gain" to gain,
                "dolbyRenderer" to (jocDecoder || encoding == AudioFormat.ENCODING_E_AC3_JOC ||
                    encoding == AudioFormat.ENCODING_E_AC3),
                "channels" to channels, "sampleRate" to sampleRate,
                "output" to when (encoding) {
                    AudioFormat.ENCODING_E_AC3_JOC -> "E-AC-3 JOC"
                    AudioFormat.ENCODING_E_AC3 -> "E-AC-3"
                    AudioFormat.ENCODING_PCM_16BIT -> "PCM 16-bit"
                    AudioFormat.ENCODING_PCM_FLOAT -> "PCM float"
                    null -> null
                    else -> "Android AudioTrack encoding ${encoding}"
                }
            )
        }
        fun close() {
            gainEffect?.release()
            try { exo.release() } finally { output?.let { releaseOutput(it.reference) }; output = null }
        }
    }

    fun releaseSessions() {
        sessions.values.forEach { it.close() }
        sessions.clear()
    }

    fun close() {
        channel.setMethodCallHandler(null)
        releaseSessions()
    }
}

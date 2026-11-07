package dev.bilisail.bili_player;

import android.os.Handler;
import android.os.Looper;
import android.view.Surface;
import com.debugly.fsplayer.player.FSPlayer;
import com.debugly.fsplayer.player.FSMeta;
import com.debugly.fsplayer.player.IMediaPlayer;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Off-main native commands. Raw source strings and native messages never leave this bridge. */
public final class BiliPlayerPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private TextureRegistry textures;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Map<Long, Runtime> players = new HashMap<>();
    private long nextId;

    private static final class Runtime {
        FSPlayer player;
        TextureRegistry.SurfaceTextureEntry texture;
        Surface surface;
        volatile boolean prepared, videoFrame, audioDecoded, ended, buffering, seekDone = true;
        volatile Integer error;
        long duration;
        boolean video;
        FSMeta meta;
        void close(Handler main) {
            // release() joins the native player before the Surface and descriptor leases go away.
            player.setOnPreparedListener(null);
            player.setOnInfoListener(null);
            player.setOnErrorListener(null);
            player.setOnCompletionListener(null);
            player.setOnSeekCompleteListener(null);
            player.release();
            surface.release();
            main.post(texture::release);
        }
    }

    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        textures = binding.getTextureRegistry();
        channel = new MethodChannel(binding.getBinaryMessenger(), "dev.bilisail/fsplayer");
        channel.setMethodCallHandler(this);
    }

    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        worker.execute(() -> {
            for (Runtime runtime : players.values()) runtime.close(main);
            players.clear();
        });
        worker.shutdown();
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        // Flutter texture registration belongs to the platform thread.
        final TextureRegistry.SurfaceTextureEntry texture = call.method.equals("create")
            ? textures.createSurfaceTexture() : null;
        worker.execute(() -> {
            try {
                Object value = execute(call, texture);
                main.post(() -> result.success(value));
            } catch (Exception | LinkageError error) {
                if (texture != null) main.post(texture::release);
                // Exception messages can contain URLs, manifests or filesystem paths.
                main.post(() -> result.error("fsplayer", "Native player operation failed", null));
            }
        });
    }

    private Object execute(MethodCall call, TextureRegistry.SurfaceTextureEntry texture) throws Exception {
        if (call.method.equals("create")) {
            Runtime r = new Runtime();
            r.texture = texture;
            r.surface = new Surface(texture.surfaceTexture());
            r.video = Boolean.TRUE.equals(call.argument("video"));
            r.duration = ((Number) call.argument("durationMs")).longValue();
            r.player = new FSPlayer();
            try {
                FSPlayer.native_setLogLevel(8); // AV_LOG_QUIET / IJK_LOG_SILENT
                r.player.setLogEnabled(false);
                r.player.setAllowHDRDirectDisplay(false);
                r.player.setOnPreparedListener(mp -> r.prepared = true);
                r.player.setOnCompletionListener(mp -> r.ended = true);
                r.player.setOnErrorListener((mp, what, extra) -> { r.error = what; return true; });
                r.player.setOnVideoSizeChangedListener((mp, w, h, sn, sd) -> {
                    if (w > 0 && h > 0) texture.surfaceTexture().setDefaultBufferSize(w, h);
                });
                r.player.setOnInfoListener((mp, what, extra) -> {
                    if (what == IMediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START) r.videoFrame = true;
                    if (what == IMediaPlayer.MEDIA_INFO_AUDIO_DECODED_START) r.audioDecoded = true;
                    if (what == IMediaPlayer.MEDIA_INFO_BUFFERING_START) r.buffering = true;
                    if (what == IMediaPlayer.MEDIA_INFO_BUFFERING_END) r.buffering = false;
                    if (what == IMediaPlayer.MEDIA_INFO_VIDEO_SEEK_RENDERING_START ||
                        (!r.video && what == IMediaPlayer.MEDIA_INFO_MEDIA_ACCURATE_SEEK_COMPLETE)) r.seekDone = true;
                    return true;
                });
                r.player.setOnSeekCompleteListener(mp -> { if (!r.video) r.seekDone = true; });
                boolean software = Boolean.TRUE.equals(call.argument("software"));
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "mediacodec-all-videos", software ? 0 : 1);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "enable-accurate-seek", 1);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "accurate-seek-timeout", 10000);
                // Android's AudioTrack PlaybackParams supplies tempo and pitch.
                // The optional legacy SoundTouch path does not preserve the
                // requested media-clock rate reliably in this published SDK.
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "soundtouch", 0);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "max-fps", 0);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "framedrop", 1);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "subtitle_mix", 0);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "packet-buffering", 1);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "max-buffer-size", 256L * 1024 * 1024);
                r.player.setOption(FSPlayer.OPT_CATEGORY_PLAYER, "min-frames", Math.max(2, Math.min(50000,
                    ((Number)call.argument("bufferMs")).longValue() * 24 / 1000)));
                r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "file,data,http,tcp,crypto");
                r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "allowed_extensions", "ALL");
                r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "rw_timeout", 15000000);
                r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "reconnect", 0);
                r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "tls_verify", 1);
                Map<String, String> headers = call.argument("headers");
                StringBuilder headerText = new StringBuilder();
                for (Map.Entry<String, String> entry : headers.entrySet()) {
                    if (entry.getKey().equals("user-agent"))
                        r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "user_agent", entry.getValue());
                    else headerText.append(entry.getKey()).append(": ").append(entry.getValue()).append("\r\n");
                }
                if (headerText.length() > 0) r.player.setOption(FSPlayer.OPT_CATEGORY_FORMAT, "headers", headerText.toString());
                r.player.setVolume(0, 0);
                r.player.setSurface(r.surface);
                r.player.setDataSource((String) call.argument("url"));
                long id = ++nextId;
                players.put(id, r);
                r.player.prepareAsync();
                return Map.of("id", id, "texture", texture.id());
            } catch (Exception | LinkageError error) {
                r.close(main);
                throw error;
            }
        }
        Number id = call.argument("id");
        Runtime r = id == null ? null : players.get(id.longValue());
        if (r == null) throw new IllegalStateException("No player");
        switch (call.method) {
            case "dispose": r.close(main); players.remove(id.longValue()); return null;
            case "play": r.player.start(); return null;
            case "pause": r.player.pause(); return null;
            case "seek":
                r.seekDone = false; r.ended = false;
                r.player.seekTo(((Number)call.argument("positionMs")).longValue()); return null;
            case "rate": r.player.setSpeed(((Number)call.argument("rate")).floatValue()); return null;
            case "volume":
                float volume = ((Number)call.argument("amplitude")).floatValue();
                r.player.setVolume(volume, volume); return null;
            case "status": return status(r);
            default: throw new IllegalArgumentException("Unknown operation");
        }
    }

    private Map<String, Object> status(Runtime r) {
        FSPlayer p = r.player;
        Map<String, Object> s = new HashMap<>();
        s.put("prepared", r.prepared); s.put("videoFrame", r.videoFrame);
        s.put("audioDecoded", r.audioDecoded); s.put("ended", r.ended);
        s.put("buffering", r.buffering); s.put("seekDone", r.seekDone);
        if (r.error != null) s.put("error", r.error);
        s.put("positionMs", p.getCurrentPosition());
        s.put("durationMs", Math.max(r.duration, p.getDuration()));
        s.put("width", p.getVideoWidth()); s.put("height", p.getVideoHeight());
        long cache = r.video ? p.getVideoCachedDuration() : p.getAudioCachedDuration();
        s.put("bufferedMs", p.getCurrentPosition() + cache);
        s.put("cacheMs", cache);
        s.put("cacheBytes", p.getVideoCachedBytes() + p.getAudioCachedBytes());
        s.put("cacheSpeed", p.getTcpSpeed());
        int decoder = p.getVideoDecoder();
        s.put("decoder", decoder == FSPlayer.FFP_PROPV_DECODER_MEDIACODEC ||
            decoder == FSPlayer.FFP_PROPV_DECODER_AVCODEC_HW ? "mediacodec" : "no");
        s.put("output", "Vulkan / Flutter.Texture");
        s.put("outputFps", (double)p.getVideoOutputFramesPerSecond());
        s.put("frameDrops", p.getDropFrameCount());
        s.put("avSync", (double)p.getVMDiff());
        if (r.prepared) {
            if (r.meta == null) r.meta = FSMeta.parse(p.getMediaMeta());
            FSMeta meta = r.meta;
            if (meta != null && meta.mVideoStream != null) {
                s.put("videoCodec", meta.mVideoStream.mCodecName);
                if (meta.mVideoStream.mFpsDen > 0) s.put("fps", (double)meta.mVideoStream.mFpsNum/meta.mVideoStream.mFpsDen);
            }
            if (meta != null && meta.mAudioStream != null) {
                s.put("audioCodec", meta.mAudioStream.mCodecName);
                s.put("sampleRate", meta.mAudioStream.mSampleRate);
                s.put("channels", Long.bitCount(meta.mAudioStream.mChannelLayout));
            }
        }
        return s;
    }
}

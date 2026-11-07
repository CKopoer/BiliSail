#import "BiliPlayerPlugin.h"
#import <FSPlayer/FSPlayer.h>
#import <FSPlayer/FSMediaPlayback.h>

// Keep at most the current frame. Flutter retains its own reference while sampling.
@interface BSFsRuntime : NSObject <FlutterTexture, FSVideoRenderingDelegate>
@property(nonatomic) FSPlayer *player;
@property(nonatomic) NSObject<FlutterTextureRegistry> *textures;
@property(nonatomic) int64_t textureId;
@property(nonatomic) BOOL video, videoFrame, audioDecoded, seekDone, closed;
@property(nonatomic) BOOL unsupportedColor;
@property(nonatomic) int64_t durationMs;
@property(nonatomic) uint64_t audioFrames, videoFrames;
@property(nonatomic) CVPixelBufferRef pixel;
- (void)audioReady:(NSNotification *)notification;
- (void)seekReady:(NSNotification *)notification;
- (void)accurateSeekReady:(NSNotification *)notification;
@end

@implementation BSFsRuntime
- (CVPixelBufferRef)copyPixelBuffer {
    @synchronized(self) { return self.pixel ? CVPixelBufferRetain(self.pixel) : NULL; }
}
- (CVPixelBufferRef)videoRenderingWillDisplay:(id<FSVideoRenderingProtocol>)renderer
                                  videoFrame:(CVPixelBufferRef)pixel {
    @synchronized(self) {
        if (self.closed) return pixel;
        CFTypeRef transfer = CVBufferGetAttachment(pixel, kCVImageBufferTransferFunctionKey, NULL);
        if (transfer && (CFEqual(transfer, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ) ||
                         CFEqual(transfer, kCVImageBufferTransferFunction_ITU_R_2100_HLG))) {
            self.unsupportedColor = YES;
            return pixel;
        }
        CVPixelBufferRetain(pixel);
        if (self.pixel) CVPixelBufferRelease(self.pixel);
        self.pixel = pixel;
        self.videoFrame = YES;
        self.videoFrames++;
    }
    // Notification is cheap and carries no pixel copies or media identifiers.
    [self.textures textureFrameAvailable:self.textureId];
    return pixel;
}
- (void)dealloc { if (_pixel) CVPixelBufferRelease(_pixel); }
@end

@interface BiliPlayerPlugin ()
@property(nonatomic) NSObject<FlutterTextureRegistry> *textures;
@property(nonatomic) NSMutableDictionary<NSNumber *, BSFsRuntime *> *players;
@property(nonatomic) int64_t nextId;
@end

@implementation BiliPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    BiliPlayerPlugin *plugin = [[self alloc] init];
    plugin.textures = [registrar textures];
    plugin.players = [NSMutableDictionary dictionary];
    FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"dev.bilisail/fsplayer"
        binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:plugin channel:channel];
}

- (void)closeRuntime:(BSFsRuntime *)r completion:(dispatch_block_t)completion {
    [[NSNotificationCenter defaultCenter] removeObserver:r];
    @synchronized(r) { r.closed = YES; }
    r.player.audioSamplesCallback = nil;
    [r.player pause];
    // Join native threads away from Flutter's platform thread, then retire its texture.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [r.player shutdownSync:YES];
        dispatch_async(dispatch_get_main_queue(), ^{
            [r.textures unregisterTexture:r.textureId];
            r.player = nil;
            completion();
        });
    });
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    NSDictionary *args = call.arguments;
    if ([call.method isEqualToString:@"create"]) {
        FSOptions *options = [FSOptions optionsByDefault];
        options.showHudView = NO;
        // iOS needs the SDK's playback category, activation and interruption handling.
        // macOS ignores this option; the application has no separate audio-session owner.
        options.automaticallySetupAudioSession = YES;
        options.protocolWhitelist = @"file,data,http,tcp,crypto";
        [options setFormatOptionValue:@"file,data,http,tcp,crypto" forKey:@"protocol_whitelist"];
        [options setFormatOptionValue:@"ALL" forKey:@"allowed_extensions"];
        [options setFormatOptionIntValue:15000000 forKey:@"rw_timeout"];
        [options setFormatOptionIntValue:1 forKey:@"tls_verify"];
        [options setPlayerOptionIntValue:0 forKey:@"start-on-prepared"];
        [options setPlayerOptionIntValue:1 forKey:@"enable-accurate-seek"];
        [options setPlayerOptionIntValue:10000 forKey:@"accurate-seek-timeout"];
        [options setPlayerOptionIntValue:0 forKey:@"max-fps"];
        [options setPlayerOptionIntValue:1 forKey:@"framedrop"];
        [options setPlayerOptionIntValue:0 forKey:@"subtitle_mix"];
        [options setPlayerOptionIntValue:256 * 1024 * 1024 forKey:@"max-buffer-size"];
        // FSPlayer exposes packet and byte bounds, not a native time-window option.
        [options setPlayerOptionIntValue:MAX(2, MIN(50000, [args[@"bufferMs"] longLongValue] * 24 / 1000))
                                  forKey:@"min-frames"];
        [options setPlayerOptionIntValue:[args[@"software"] boolValue] ? 0 : 1 forKey:@"videotoolbox_hwaccel"];
        NSMutableString *headers = [NSMutableString string];
        [args[@"headers"] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            if ([key isEqualToString:@"user-agent"]) [options setFormatOptionValue:value forKey:@"user_agent"];
            else [headers appendFormat:@"%@: %@\r\n", key, value];
        }];
        if (headers.length) [options setFormatOptionValue:headers forKey:@"headers"];
        [FSPlayer setLogReport:NO];
        [FSPlayer setLogLevel:(FSLogLevel)8];
        BSFsRuntime *r = [[BSFsRuntime alloc] init];
        r.textures = self.textures;
        r.seekDone = YES;
        r.video = [args[@"video"] boolValue];
        r.durationMs = [args[@"durationMs"] longLongValue];
        r.textureId = [self.textures registerTexture:r];
        r.player = [[FSPlayer alloc] initWithContent:args[@"url"] options:options];
        r.player.shouldAutoplay = NO;
        r.player.playbackVolume = 0;
        // The public delegate receives CVPixelBuffer before Metal rendering.
        // Flutter owns composition; bypass FSPlayer's separate drawable pass.
        id<FSVideoRenderingProtocol> view = (id<FSVideoRenderingProtocol>)r.player.view;
        view.displayDelegate = r;
        view.preventDisplay = YES;
        __weak BSFsRuntime *weakRuntime = r;
        r.player.audioSamplesCallback = ^(int16_t *samples, int sampleSize, int sampleRate, int channels) {
            BSFsRuntime *runtime = weakRuntime;
            if (!runtime || !samples || sampleSize <= 0) return;
            @synchronized(runtime) {
                if (!runtime.closed) runtime.audioFrames++;
            }
        };
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        // Use selector observers so releasing a runtime removes every subscription.
        [center addObserver:r selector:@selector(audioReady:)
                       name:FSPlayerFirstAudioFrameDecodedNotification object:r.player];
        [center addObserver:r selector:@selector(seekReady:)
                       name:FSPlayerSeekVideoStartNotification object:r.player];
        [center addObserver:r selector:@selector(accurateSeekReady:)
                       name:FSPlayerAccurateSeekCompleteNotification object:r.player];
        NSNumber *identifier = @(++self.nextId);
        self.players[identifier] = r;
        [weakRuntime.player prepareToPlay];
        result(@{@"id": identifier, @"texture": @(r.textureId)});
        return;
    }
    BSFsRuntime *r = self.players[args[@"id"]];
    if (!r) { result([FlutterError errorWithCode:@"fsplayer" message:@"No native player" details:nil]); return; }
    if ([call.method isEqualToString:@"dispose"]) {
        [self closeRuntime:r completion:^{ [self.players removeObjectForKey:args[@"id"]]; result(nil); }];
        return;
    }
    if ([call.method isEqualToString:@"play"]) [r.player play];
    else if ([call.method isEqualToString:@"pause"]) [r.player pause];
    else if ([call.method isEqualToString:@"rate"]) r.player.playbackRate = [args[@"rate"] floatValue];
    else if ([call.method isEqualToString:@"volume"]) r.player.playbackVolume = [args[@"amplitude"] floatValue];
    else if ([call.method isEqualToString:@"seek"]) {
        r.seekDone = NO;
        r.player.currentPlaybackTime = [args[@"positionMs"] doubleValue] / 1000;
    } else if ([call.method isEqualToString:@"status"]) {
        FSPlayer *p = r.player;
        FSMonitor *m = p.monitor;
        uint64_t audioFrames, videoFrames;
        @synchronized(r) { audioFrames = r.audioFrames; videoFrames = r.videoFrames; }
        NSMutableDictionary *s = [@{
            @"prepared": @(p.isPreparedToPlay), @"videoFrame": @(r.videoFrame),
            @"audioDecoded": @(r.audioDecoded), @"seekDone": @(r.seekDone),
            @"audioFrames": @(audioFrames), @"videoFrames": @(videoFrames),
            @"unsupportedColor": @(r.unsupportedColor),
            @"ended": @(p.playbackSchedule == FSPlayerPlaybackScheduleCompleted),
            @"buffering": @((p.loadState & FSPlayerLoadStateStalled) != 0),
            @"positionMs": @((int64_t)(p.currentPlaybackTime * 1000)),
            @"durationMs": @(MAX(r.durationMs, m.duration)),
            @"bufferedMs": @((int64_t)(p.playableDuration * 1000)),
            @"width": @(m.width), @"height": @(m.height),
            @"output": @"CVPixelBuffer / Flutter.Texture", @"fps": @(p.fpsInMeta),
            @"decoder": m.vdecoder ?: @"no", @"outputFps": @(p.fpsAtOutput),
            @"frameDrops": @(p.dropFrameCount), @"avSync": @(p.currentVMDiff),
            @"sampleRate": @(m.sampleRate), @"cacheSpeed": @(p.currentDownloadSpeed)
        } mutableCopy];
        if (m.vcodec) s[@"videoCodec"] = m.vcodec;
        if (m.acodec) s[@"audioCodec"] = m.acodec;
        if (p.playbackSchedule == FSPlayerPlaybackScheduleError) s[@"error"] = @1;
        result(s); return;
    } else { result(FlutterMethodNotImplemented); return; }
    result(nil);
}

- (void)detachFromEngineForRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    for (BSFsRuntime *r in self.players.allValues) [self closeRuntime:r completion:^{}];
    [self.players removeAllObjects];
}
@end

@implementation BSFsRuntime (Notifications)
- (void)audioReady:(NSNotification *)notification { self.audioDecoded = YES; }
- (void)seekReady:(NSNotification *)notification { self.seekDone = YES; }
- (void)accurateSeekReady:(NSNotification *)notification { if (!self.video) self.seekDone = YES; }
@end

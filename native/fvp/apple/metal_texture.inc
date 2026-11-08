// Build-local replacement for wang-bin/fvp e816374 (BSD-3-Clause).
// Keep the decoder target private; publish only completed, write-once IOSurfaces.
#import <dispatch/dispatch.h>
@interface MetalTexture : NSObject<FlutterTexture>
- (instancetype _Nullable)initWithWidth:(int)width height:(int)height;
- (void)bindRegistry:(NSObject<FlutterTextureRegistry>* _Nullable)registry textureId:(int64_t)textureId;
- (void)invalidate;
@end

@implementation MetalTexture {
 @public
    id<MTLDevice> device;
    id<MTLCommandQueue> cmdQueue;
    id<MTLTexture> texture;
    mutex mtx;
    uint64_t revision;
 @private
    CVPixelBufferRef currentBuffer;
    CVPixelBufferRef pendingBuffer;
    id<MTLCommandBuffer> pendingCommand;
    id<MTLTexture> pendingTexture;
    uint64_t currentRevision;
    uint64_t pendingRevision;
    uint64_t failedRevision;
    BOOL active;
    __weak NSObject<FlutterTextureRegistry>* registry_;
    int64_t textureId_;
}

- (instancetype _Nullable)initWithWidth:(int)width height:(int)height {
    self = [super init];
    if (!self) return nil;
    device = MTLCreateSystemDefaultDevice();
    cmdQueue = [device newCommandQueue];
    auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
        width:width height:height mipmapped:NO];
    desc.usage = MTLTextureUsageRenderTarget;
    texture = [device newTextureWithDescriptor:desc];
    active = YES;
    return self;
}

- (void)bindRegistry:(NSObject<FlutterTextureRegistry>* _Nullable)registry textureId:(int64_t)textureId {
    scoped_lock lock(mtx);
    registry_ = registry;
    textureId_ = textureId;
}

- (void)invalidate {
    scoped_lock lock(mtx);
    active = NO;
    registry_ = nil;
}

- (void)dealloc {
    if (currentBuffer) CVPixelBufferRelease(currentBuffer);
    if (pendingBuffer) CVPixelBufferRelease(pendingBuffer);
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    scoped_lock lock(mtx);
    if (pendingCommand) {
        const auto status = pendingCommand.status;
        if (status == MTLCommandBufferStatusCompleted || status == MTLCommandBufferStatusError) {
            if (status == MTLCommandBufferStatusCompleted && active) {
                if (currentBuffer) CVPixelBufferRelease(currentBuffer);
                currentBuffer = pendingBuffer;
                currentRevision = pendingRevision;
                pendingBuffer = nullptr;
            } else {
                failedRevision = pendingRevision;
            }
            if (pendingBuffer) CVPixelBufferRelease(pendingBuffer);
            pendingBuffer = nullptr;
            pendingCommand = nil;
            pendingTexture = nil;
        }
    }

    // One in-flight blit bounds allocation and queue growth. Completion wakes
    // Flutter again even if playback paused while the copy was outstanding.
    if (active && revision && revision != currentRevision &&
        revision != failedRevision && !pendingCommand) {
        NSDictionary* attributes = @{
            (__bridge id)kCVPixelBufferMetalCompatibilityKey: @YES,
            (__bridge id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        CVPixelBufferRef buffer = nullptr;
        const auto result = CVPixelBufferCreate(kCFAllocatorDefault,
            texture.width, texture.height, kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attributes, &buffer);
        if (result == kCVReturnSuccess && buffer) {
            auto desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                width:texture.width height:texture.height mipmapped:NO];
            desc.storageMode = MTLStorageModeShared;
            desc.usage = MTLTextureUsageShaderRead;
            auto destination = [device newTextureWithDescriptor:desc
                iosurface:CVPixelBufferGetIOSurface(buffer) plane:0];
            auto command = [cmdQueue commandBuffer];
            auto blit = [command blitCommandEncoder];
            if (destination && command && blit) {
                [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                    sourceSize:MTLSizeMake(texture.width, texture.height, texture.depth)
                    toTexture:destination destinationSlice:0 destinationLevel:0
                    destinationOrigin:MTLOriginMake(0, 0, 0)];
                [blit endEncoding];
                pendingBuffer = buffer;
                pendingTexture = destination;
                pendingRevision = revision;
                pendingCommand = command;
                __weak MetalTexture* weakSelf = self;
                [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
                    (void)completed;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        MetalTexture* owner = weakSelf;
                        if (!owner) return;
                        NSObject<FlutterTextureRegistry>* registry;
                        int64_t textureId;
                        {
                            scoped_lock callbackLock(owner->mtx);
                            if (!owner->active) return;
                            registry = owner->registry_;
                            textureId = owner->textureId_;
                        }
                        [registry textureFrameAvailable:textureId];
                    });
                }];
                // MDK renderVideo and the blit submit to this same queue;
                // later decoder renders cannot overtake the source read.
                [command commit];
            } else {
                if (blit) [blit endEncoding];
                CVPixelBufferRelease(buffer);
                failedRevision = revision;
            }
        } else {
            if (buffer) CVPixelBufferRelease(buffer);
            failedRevision = revision;
        }
    }
    return currentBuffer ? CVPixelBufferRetain(currentBuffer) : nullptr;
}
@end

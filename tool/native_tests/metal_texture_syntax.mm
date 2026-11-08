// Controlled declarations check the real replacement's Objective-C++/ARC
// syntax. They deliberately do not claim Apple SDK or Metal runtime validation.
#include <mutex>
#include <cstdint>
using namespace std;
using NSUInteger = unsigned long;
using BOOL = signed char;
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#define nil ((id)0)
__attribute__((objc_root_class))
@interface NSObject
+ (instancetype)alloc;
- (instancetype)init;
@end
@interface NSNumber : NSObject
+ (instancetype)numberWithBool:(BOOL)value;
@end
@interface NSDictionary : NSObject
+ (instancetype)dictionaryWithObjects:(const id[])objects forKeys:(const id[])keys count:(NSUInteger)count;
@end
struct CVBuffer;
using CVPixelBufferRef = CVBuffer*;
using CFDictionaryRef = const void*;
constexpr const void* kCFAllocatorDefault = nullptr;
extern const void* kCVPixelBufferMetalCompatibilityKey;
extern const void* kCVPixelBufferIOSurfacePropertiesKey;
constexpr int kCVReturnSuccess = 0, kCVPixelFormatType_32BGRA = 1;
int CVPixelBufferCreate(const void*, NSUInteger, NSUInteger, int, CFDictionaryRef, CVPixelBufferRef*);
void CVPixelBufferRelease(CVPixelBufferRef);
CVPixelBufferRef CVPixelBufferRetain(CVPixelBufferRef);
void* CVPixelBufferGetIOSurface(CVPixelBufferRef);
struct MTLOrigin { NSUInteger x, y, z; };
struct MTLSize { NSUInteger width, height, depth; };
MTLOrigin MTLOriginMake(NSUInteger, NSUInteger, NSUInteger);
MTLSize MTLSizeMake(NSUInteger, NSUInteger, NSUInteger);
enum MTLPixelFormat { MTLPixelFormatBGRA8Unorm };
enum MTLTextureUsage { MTLTextureUsageRenderTarget, MTLTextureUsageShaderRead };
enum MTLStorageMode { MTLStorageModeShared };
enum MTLCommandBufferStatus { MTLCommandBufferStatusEnqueued, MTLCommandBufferStatusCompleted, MTLCommandBufferStatusError };
@interface MTLTextureDescriptor : NSObject
+ (instancetype)texture2DDescriptorWithPixelFormat:(MTLPixelFormat)format width:(NSUInteger)width height:(NSUInteger)height mipmapped:(BOOL)mipmapped;
@property MTLTextureUsage usage;
@property MTLStorageMode storageMode;
@end
@protocol MTLTexture
@property(readonly) NSUInteger width, height, depth;
@end
@protocol MTLBlitCommandEncoder
- (void)copyFromTexture:(id<MTLTexture>)source sourceSlice:(NSUInteger)slice sourceLevel:(NSUInteger)level sourceOrigin:(MTLOrigin)origin sourceSize:(MTLSize)size toTexture:(id<MTLTexture>)destination destinationSlice:(NSUInteger)destinationSlice destinationLevel:(NSUInteger)destinationLevel destinationOrigin:(MTLOrigin)destinationOrigin;
- (void)endEncoding;
@end
@protocol MTLCommandBuffer
@property(readonly) MTLCommandBufferStatus status;
- (id<MTLBlitCommandEncoder>)blitCommandEncoder;
- (void)addCompletedHandler:(void (^)(id<MTLCommandBuffer>))handler;
- (void)commit;
@end
@protocol MTLCommandQueue
- (id<MTLCommandBuffer>)commandBuffer;
@end
@protocol MTLDevice
- (id<MTLCommandQueue>)newCommandQueue;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor*)descriptor;
- (id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor*)descriptor iosurface:(void*)surface plane:(NSUInteger)plane;
@end
id<MTLDevice> MTLCreateSystemDefaultDevice();
@protocol FlutterTexture
- (CVPixelBufferRef)copyPixelBuffer;
@end
@protocol FlutterTextureRegistry
- (void)textureFrameAvailable:(int64_t)texture;
@end
#include "metal_texture.inc"

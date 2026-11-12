// Controlled CoreVideo/OpenGLES substitutes for the real production Swift code.
import Foundation

public typealias GLenum = UInt32
public typealias GLuint = UInt32
public typealias GLint = Int32
public typealias GLsizei = Int32
public typealias CVReturn = Int32
public typealias CFString = String
public typealias CFDictionary = [String: Any]
let kCFAllocatorDefault: Int? = nil
let kCFStringEncodingASCII: UInt32 = 0
let kCVReturnSuccess: CVReturn = 0
let kCVPixelFormatType_32BGRA: UInt32 = 111
let kCVPixelBufferMetalCompatibilityKey = "metal"
let kCVPixelBufferOpenGLESCompatibilityKey = "gles"
let kCVPixelBufferIOSurfacePropertiesKey = "surface"
let GL_TEXTURE_2D: UInt32 = 1
let GL_RGBA: Int32 = 2
let GL_BGRA: UInt32 = 3
let GL_UNSIGNED_BYTE: UInt32 = 4
let GL_FRAMEBUFFER: UInt32 = 5
let GL_COLOR_ATTACHMENT0: UInt32 = 6
let GL_FRAMEBUFFER_COMPLETE: UInt32 = 7
let GL_NO_ERROR: UInt32 = 0
var failure = ""
var nextID: UInt32 = 0
var pixelCount = 0
var framebuffers = Set<UInt32>()
var manualDeletes = 0
var finished = false
var attributesValid = false
var nativeContexts = 0
var releasedContexts = 0
var update: ((UnsafeMutableRawPointer?) -> Void)?
var updateData: UnsafeMutableRawPointer?

public class EAGLContext: NSObject {
  public enum API { case openGLES3 }
  private static var active: EAGLContext?
  public init?(api: API) {}
  public static func current() -> EAGLContext? { active }
  @discardableResult public static func setCurrent(_ context: EAGLContext?) -> Bool {
    if failure == "context" && context != nil { return false }
    active = context
    return true
  }
}
public final class CVPixelBuffer {
  let id: UInt32
  var value = 0
  let bytes = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
  init() { nextID += 1; id = nextID; pixelCount += 1 }
  deinit { bytes.deallocate(); pixelCount -= 1 }
}
public struct CVPixelBufferLockFlags: OptionSet {
  public let rawValue: UInt64
  public init(rawValue: UInt64) { self.rawValue = rawValue }
}
func CVPixelBufferLockBaseAddress(_ pixel: CVPixelBuffer, _ flags: CVPixelBufferLockFlags) -> CVReturn { 0 }
func CVPixelBufferUnlockBaseAddress(_ pixel: CVPixelBuffer, _ flags: CVPixelBufferLockFlags) -> CVReturn { 0 }
func CVPixelBufferGetBytesPerRow(_ pixel: CVPixelBuffer) -> Int { 7680 }
func CVPixelBufferGetBaseAddress(_ pixel: CVPixelBuffer) -> UnsafeMutableRawPointer? { pixel.bytes }
public final class CVOpenGLESTexture {
  let pixel: CVPixelBuffer
  init(_ pixel: CVPixelBuffer) { self.pixel = pixel }
}
public final class CVOpenGLESTextureCache {
  var textures: [CVOpenGLESTexture] = []
}
func CVOpenGLESTextureCacheCreate(_ a: Int?, _ b: CFDictionary?, _ c: EAGLContext,
                                _ d: CFDictionary?, _ out: inout CVOpenGLESTextureCache?) -> CVReturn {
  out = CVOpenGLESTextureCache(); return 0
}
func CVPixelBufferCreate(_ a: Int?, _ w: Int, _ h: Int, _ f: UInt32,
                         _ attrs: CFDictionary?, _ out: inout CVPixelBuffer?) -> CVReturn {
  attributesValid = attrs?[kCVPixelBufferMetalCompatibilityKey] as? Bool == true &&
    attrs?[kCVPixelBufferOpenGLESCompatibilityKey] as? Bool == true &&
    attrs?[kCVPixelBufferIOSurfacePropertiesKey] != nil
  if failure == "pixel" { return -666 }
  out = CVPixelBuffer(); return 0
}
func CVOpenGLESTextureCacheCreateTextureFromImage(
  _ a: Int?, _ cache: CVOpenGLESTextureCache, _ pixel: CVPixelBuffer,
  _ attrs: CFDictionary?, _ target: GLenum, _ internalFormat: GLint, _ w: GLsizei,
  _ h: GLsizei, _ format: GLenum, _ type: GLenum, _ plane: Int,
  _ out: inout CVOpenGLESTexture?
) -> CVReturn {
  if failure == "texture" { return -6683 }
  let texture = CVOpenGLESTexture(pixel)
  cache.textures.append(texture); out = texture; return 0
}
func CVOpenGLESTextureGetName(_ texture: CVOpenGLESTexture) -> GLuint { texture.pixel.id }
func CVOpenGLESTextureCacheFlush(_ cache: CVOpenGLESTextureCache, _ flags: Int) {
  cache.textures.removeAll()
}
func glBindTexture(_ target: GLenum, _ name: GLuint) {}
func glDeleteTextures(_ count: Int32, _ name: inout GLuint) { manualDeletes += 1 }
func glGenFramebuffers(_ count: Int32, _ name: inout GLuint) {
  nextID += 1; name = nextID; framebuffers.insert(name)
}
func glBindFramebuffer(_ target: GLenum, _ name: GLuint) {}
func glDeleteFramebuffers(_ count: Int32, _ name: inout GLuint) { framebuffers.remove(name) }
func glFramebufferTexture2D(_ a: GLenum, _ b: GLenum, _ c: GLenum, _ d: GLuint, _ e: Int32) {}
func glCheckFramebufferStatus(_ target: GLenum) -> GLenum { failure == "framebuffer" ? 999 : GL_FRAMEBUFFER_COMPLETE }
func glGetError() -> GLenum { 0 }
func glFinish() { finished = true }
func glFlush() {}
func autoreleasepool(_ body: () -> Void) { body() }
func CFStringCreateWithCString(_ a: Int?, _ b: UnsafePointer<Int8>?, _ c: UInt32) -> CFString { "symbol" }
func CFBundleGetBundleWithIdentifier(_ name: CFString) -> Int { 0 }
func CFBundleGetFunctionPointerForName(_ bundle: Int, _ name: CFString) -> UnsafeMutableRawPointer? { nil }
public protocol FlutterTexture {}
public protocol ResizableTextureProtocol {
  func resize(_ size: CGSize)
  func render(_ size: CGSize)
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>?
}
let MPV_RENDER_API_TYPE_OPENGL = "opengl"
let MPV_RENDER_API_TYPE_SW = "sw"
let MPV_RENDER_PARAM_API_TYPE = 1
let MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2
let MPV_RENDER_PARAM_OPENGL_FBO = 3
let MPV_RENDER_PARAM_INVALID = 0
let MPV_RENDER_PARAM_SW_SIZE = 4
let MPV_RENDER_PARAM_SW_FORMAT = 5
let MPV_RENDER_PARAM_SW_STRIDE = 6
let MPV_RENDER_PARAM_SW_POINTER = 7
struct mpv_opengl_init_params {
  var get_proc_address: (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?
  var get_proc_address_ctx: UnsafeMutableRawPointer?
}
struct mpv_opengl_fbo { var fbo: Int32; var w: Int32; var h: Int32; var internal_format: Int32 }
struct mpv_render_param { var type: Int = 0; var data: UnsafeMutableRawPointer? = nil }
enum MPVHelpers { static func checkError(_ status: Int32) { precondition(status == 0) } }
func mpv_render_context_create(_ out: inout OpaquePointer?, _ handle: OpaquePointer,
                               _ params: inout [mpv_render_param]) -> Int32 {
  nativeContexts += 1; out = handle; return 0
}
func mpv_render_context_set_update_callback(_ context: OpaquePointer?,
  _ callback: ((UnsafeMutableRawPointer?) -> Void)?, _ data: UnsafeMutableRawPointer?) {
  update = callback; updateData = data
}
func mpv_render_context_free(_ context: OpaquePointer?) {
  precondition(context != nil && nativeContexts > 0)
  nativeContexts -= 1; releasedContexts += 1
}
func mpv_render_context_render(_ context: OpaquePointer?, _ params: inout [mpv_render_param]) -> Int32 {
  precondition(context != nil && nativeContexts > 0)
  if params[0].type == MPV_RENDER_PARAM_OPENGL_FBO {
    precondition(EAGLContext.current() != nil)
    let fbo = params[0].data!.assumingMemoryBound(to: mpv_opengl_fbo.self).pointee
    precondition(framebuffers.contains(UInt32(fbo.fbo)))
  } else {
    let dimensions = params[0].data!.assumingMemoryBound(to: Int32.self)
    precondition(dimensions[0] == 1920 && dimensions[1] == 1080)
  }
  finished = false
  if failure == "render" { return -20 }
  return 0
}

// PRODUCTION_CLASSES

let scenario = CommandLine.arguments[1]
let size = CGSize(width: 1920, height: 1080)
if scenario.hasPrefix("software") {
  var renderer: TextureSW? = TextureSW(handle: OpaquePointer(bitPattern: 1)!, updateCallback: {})
  precondition(nativeContexts == 1)
  renderer!.render(size)
  var saved = renderer!.copyPixelBuffer()?.takeRetainedValue()
  precondition(saved != nil)
  if scenario != "software" {
    failure = String(scenario.dropFirst("software-".count))
    for _ in 0..<30 { renderer!.render(size) }
    precondition(renderer!.copyPixelBuffer()?.takeRetainedValue() === saved && pixelCount == 1)
    failure = ""
    renderer!.render(size)
    precondition(renderer!.copyPixelBuffer()?.takeRetainedValue() !== saved)
  }
  renderer!.dispose()
  renderer!.dispose()
  renderer!.render(size)
  precondition(nativeContexts == 0 && releasedContexts == 1 && renderer!.copyPixelBuffer() == nil)
  renderer = nil
  saved = nil
  precondition(pixelCount == 0)
  print("Passed software renderer: \(scenario)")
  exit(0)
}
var callbacks = 0
var renderer: TextureHW? = TextureHW(handle: OpaquePointer(bitPattern: 1)!, updateCallback: { callbacks += 1 })
let previousContext = EAGLContext(api: .openGLES3)!
EAGLContext.setCurrent(previousContext)
func currentFrame() -> CVPixelBuffer? { renderer!.copyPixelBuffer()?.takeRetainedValue() }
renderer!.render(size)
precondition(finished && EAGLContext.current() === previousContext)
var first = currentFrame()
precondition(first != nil)
first!.value = 42
if scenario == "dispose" {
  renderer!.dispose()
  renderer!.dispose()
  renderer!.render(size)
  precondition(nativeContexts == 0 && releasedContexts == 1 && renderer!.copyPixelBuffer() == nil)
} else if scenario == "callbacks" {
  for _ in 0..<10000 { update?(updateData) }
  precondition(callbacks == 10000)
} else if scenario == "frames" {
  for _ in 0..<2000 {
    renderer!.render(size)
    precondition(finished && attributesValid && manualDeletes == 0 && framebuffers.isEmpty)
    precondition(EAGLContext.current() === previousContext)
    precondition(currentFrame() !== first && first!.value == 42)
    precondition(pixelCount <= 2)
  }
} else if scenario == "dimensions" {
  for invalid in [CGSize.zero, CGSize(width: -1, height: 2),
                  CGSize(width: Double.nan, height: 2), CGSize(width: Double.infinity, height: 2),
                  CGSize(width: Double(Int32.max) + 1, height: 2)] {
    renderer!.render(invalid)
    precondition(currentFrame() === first && framebuffers.isEmpty)
  }
} else {
  failure = scenario
  for _ in 0..<30 { renderer!.render(size) }
  precondition(currentFrame() === first && framebuffers.isEmpty && pixelCount == 1)
  precondition(EAGLContext.current() === previousContext)
  failure = ""
  renderer!.render(size)
  precondition(currentFrame() !== first && finished)
}
renderer = nil
precondition(nativeContexts == 0 && releasedContexts == 1 && update == nil)
precondition(first!.value == 42 && framebuffers.isEmpty && manualDeletes == 0)
first = nil
precondition(pixelCount == 0)
print("Passed iOS renderer: \(scenario)")

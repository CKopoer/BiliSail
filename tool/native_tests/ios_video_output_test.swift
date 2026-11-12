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
  init() { nextID += 1; id = nextID; pixelCount += 1 }
  deinit { pixelCount -= 1 }
}
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
let MPV_RENDER_PARAM_API_TYPE = 1
let MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2
let MPV_RENDER_PARAM_OPENGL_FBO = 3
let MPV_RENDER_PARAM_INVALID = 0
struct mpv_opengl_init_params {
  var get_proc_address: (UnsafeMutableRawPointer?, UnsafePointer<Int8>?) -> UnsafeMutableRawPointer?
  var get_proc_address_ctx: UnsafeMutableRawPointer?
}
struct mpv_opengl_fbo { var fbo: Int32; var w: Int32; var h: Int32; var internal_format: Int32 }
struct mpv_render_param { var type: Int = 0; var data: UnsafeMutableRawPointer? = nil }
enum MPVHelpers { static func checkError(_ status: Int32) { precondition(status == 0) } }
func mpv_render_context_create(_ out: inout OpaquePointer?, _ handle: OpaquePointer,
                               _ params: inout [mpv_render_param]) -> Int32 {
  out = handle; return 0
}
func mpv_render_context_set_update_callback(_ context: OpaquePointer?,
  _ callback: ((UnsafeMutableRawPointer?) -> Void)?, _ data: UnsafeMutableRawPointer?) {}
func mpv_render_context_free(_ context: OpaquePointer?) {}
func mpv_render_context_render(_ context: OpaquePointer?, _ params: inout [mpv_render_param]) -> Int32 {
  precondition(EAGLContext.current() != nil)
  let fbo = params[0].data!.assumingMemoryBound(to: mpv_opengl_fbo.self).pointee
  precondition(framebuffers.contains(UInt32(fbo.fbo)))
  finished = false
  if failure == "render" { return -20 }
  return 0
}

// PRODUCTION_CLASSES

let scenario = CommandLine.arguments[1]
let size = CGSize(width: 1920, height: 1080)
var renderer: TextureHW? = TextureHW(handle: OpaquePointer(bitPattern: 1)!, updateCallback: {})
let previousContext = EAGLContext(api: .openGLES3)!
EAGLContext.setCurrent(previousContext)
func currentFrame() -> CVPixelBuffer? { renderer!.copyPixelBuffer()?.takeRetainedValue() }
renderer!.render(size)
precondition(finished && EAGLContext.current() === previousContext)
var first = currentFrame()
precondition(first != nil)
first!.value = 42
if scenario == "frames" {
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
precondition(first!.value == 42 && framebuffers.isEmpty && manualDeletes == 0)
first = nil
precondition(pixelCount == 0)
print("Passed iOS renderer: \(scenario)")

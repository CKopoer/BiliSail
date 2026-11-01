import 'dart:ffi' hide Size;
import 'dart:ui' show PlatformDispatcher, Size;

/// Native observations/actions are restricted to this engine's playback view.
final class NativePlaybackWindow {
  NativePlaybackWindow(int viewId)
    : handle = _windowHandle(PlatformDispatcher.instance.engineId!, viewId);

  final Pointer<Void> handle;

  bool get isMaximized => _isZoomed(handle) != 0;
  bool get isMinimized => _isIconic(handle) != 0;

  Size get outerSize {
    final heap = _getProcessHeap();
    final rect = _heapAlloc(heap, 8, sizeOf<_Rect>()).cast<_Rect>();
    try {
      if (_getWindowRect(handle, rect) == 0) {
        throw StateError('The playback window rectangle is unavailable.');
      }
      return Size(
        (rect.ref.right - rect.ref.left).toDouble(),
        (rect.ref.bottom - rect.ref.top).toDouble(),
      );
    } finally {
      _heapFree(heap, 0, rect.cast());
    }
  }

  void resize(int width, int height) => _setWindowPos(
    handle,
    nullptr,
    0,
    0,
    width,
    height,
    0x0002 | 0x0004 | 0x0010, // NOMOVE | NOZORDER | NOACTIVATE
  );

  void maximize() => _showWindow(handle, 3);
  void restore() => _showWindow(handle, 9);
  void minimize() => _showWindow(handle, 6);
  void back() => _postMessage(handle, 0x00A2, 3, 0); // NC left-up, HTSYSMENU
  void doubleBack() {
    back();
    _postMessage(handle, 0x00A3, 3, 0); // NC double-click
    back();
  }

  void close() => _postMessage(handle, 0x0010, 0, 0);
}

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

@Native<Pointer<Void> Function(Int64, Int64)>(
  symbol: 'InternalFlutterWindows_WindowManager_GetTopLevelWindowHandle',
)
external Pointer<Void> _windowHandle(int engineId, int viewId);

@Native<Int32 Function(Pointer<Void>, Pointer<_Rect>)>(symbol: 'GetWindowRect')
external int _getWindowRect(Pointer<Void> window, Pointer<_Rect> rect);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'IsZoomed')
external int _isZoomed(Pointer<Void> window);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'IsIconic')
external int _isIconic(Pointer<Void> window);

@Native<Int32 Function(Pointer<Void>, Int32)>(symbol: 'ShowWindow')
external int _showWindow(Pointer<Void> window, int state);

@Native<
  Int32 Function(
    Pointer<Void>,
    Pointer<Void>,
    Int32,
    Int32,
    Int32,
    Int32,
    Uint32,
  )
>(symbol: 'SetWindowPos')
external int _setWindowPos(
  Pointer<Void> window,
  Pointer<Void> after,
  int x,
  int y,
  int width,
  int height,
  int flags,
);

@Native<Int32 Function(Pointer<Void>, Uint32, IntPtr, IntPtr)>(
  symbol: 'PostMessageW',
)
external int _postMessage(
  Pointer<Void> window,
  int message,
  int wparam,
  int lparam,
);

@Native<Pointer<Void> Function()>(symbol: 'GetProcessHeap')
external Pointer<Void> _getProcessHeap();

@Native<Pointer<Void> Function(Pointer<Void>, Uint32, UintPtr)>(
  symbol: 'HeapAlloc',
)
external Pointer<Void> _heapAlloc(Pointer<Void> heap, int flags, int bytes);

@Native<Int32 Function(Pointer<Void>, Uint32, Pointer<Void>)>(
  symbol: 'HeapFree',
)
external int _heapFree(Pointer<Void> heap, int flags, Pointer<Void> memory);

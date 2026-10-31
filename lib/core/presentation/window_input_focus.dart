import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

// Observe from application bootstrap, before native window creation. Hosts in
// widget tests also subscribe without requiring the production entry point.
final class WindowInputFocus with WidgetsBindingObserver {
  WindowInputFocus({this._nativeSnapshotTimeout = const Duration(seconds: 2)});

  static final instance = WindowInputFocus();
  Duration _nativeSnapshotTimeout;
  final _listeners = <VoidCallback>{};
  int? viewId;
  bool observed = false;
  int revision = 0;
  String source = 'unknown';
  bool diagnostics = false;
  int _snapshotRequest = 0;
  int _nativeRevision = -1;
  static const _channel = MethodChannel('bilisail/application_window');

  Future<void> synchronizeNativeFocusIfSupported() async {
    if (Platform.isMacOS) await synchronizeNativeFocus();
  }

  // Read keyWindow after native creation, not mainWindow or a focus request.
  // SDK 3.47.6 can omit the initial event by installing its delegate too late.
  Future<void> synchronizeNativeFocus() async {
    final request = ++_snapshotRequest;
    for (var attempt = 0; attempt < 3; attempt++) {
      final eventRevision = revision;
      final snapshot = await _channel
          .invokeMapMethod<String, Object?>('getWindowFocus')
          .timeout(_nativeSnapshotTimeout);
      if (request != _snapshotRequest) return;
      if (eventRevision != revision) {
        // A known newer focus wins. A blur can precede a new window's omitted
        // focus event, so reread that unknown state with a bounded retry.
        if (viewId == null) continue;
        return;
      }
      if (snapshot == null) {
        throw StateError('Native window focus is unavailable');
      }
      final nativeRevision = snapshot['revision'];
      if (nativeRevision is! int) {
        throw StateError('Invalid native focus revision');
      }
      if (nativeRevision < _nativeRevision) return;
      _nativeRevision = nativeRevision;
      diagnostics = snapshot['diagnostics'] == true;
      final focusedView = snapshot['viewId'];
      viewId = focusedView is int ? focusedView : null;
      observed = true;
      source = 'native';
      revision++;
      if (diagnostics) {
        debugPrint(
          'BILISAIL_FOCUS source=$source revision=$revision '
          'nativeRevision=$_nativeRevision view=$viewId '
          'active=${snapshot['active']} responder=${snapshot['responder']}',
        );
      }
      _notify();
      return;
    }
  }

  void _notify() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  bool _initialized = false;
  bool _applicationLifetime = false;

  // Call at application bootstrap, before the explicit macOS main window.
  void initialize({Duration? nativeSnapshotTimeout}) {
    if (nativeSnapshotTimeout != null) {
      _nativeSnapshotTimeout = nativeSnapshotTimeout;
    }
    _applicationLifetime = true;
    _observe();
  }

  void _observe() {
    if (_initialized) return;
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  void addListener(VoidCallback listener) {
    _observe();
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty || _applicationLifetime) return;
    WidgetsBinding.instance.removeObserver(this);
    _initialized = false;
    _snapshotRequest++;
    _nativeRevision = -1;
    source = 'unknown';
    diagnostics = false;
    viewId = null;
    observed = false;
    revision++;
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    observed = true;
    source = 'flutter';
    revision++;
    if (event.state == ViewFocusState.focused) {
      viewId = event.viewId;
    } else if (viewId == event.viewId) {
      // A late blur from A must not clear a newer focus on B.
      viewId = null;
    }
    if (diagnostics) {
      debugPrint(
        'BILISAIL_FOCUS source=$source revision=$revision '
        'eventView=${event.viewId} state=${event.state.name} view=$viewId',
      );
    }
    _notify();
  }
}

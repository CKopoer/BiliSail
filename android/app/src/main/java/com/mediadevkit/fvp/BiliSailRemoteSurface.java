package com.mediadevkit.fvp;

import android.view.Surface;

/** Uses the fixed fvp commit's surface bridge inside the worker process only. */
public final class BiliSailRemoteSurface {
    private BiliSailRemoteSurface() {}

    public static void attach(long handle, long id, Surface surface, int width, int height, boolean direct) {
        FvpPlugin.nativeSetSurface(handle, id, surface, width, height, direct);
    }

    public static void detach(long id) {
        FvpPlugin.nativeSetSurface(0, id, null, -1, -1, false);
    }
}

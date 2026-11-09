#pragma once

// Only stable dependency headers belong here; application and plugin state
// must continue to be compiled from their own translation units.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <WebView2.h>
#include <flutter/standard_method_codec.h>
#include <wil/com.h>

#ifndef RUNNER_SYSTEM_FONTS_H_
#define RUNNER_SYSTEM_FONTS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterSystemFonts(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SYSTEM_FONTS_H_

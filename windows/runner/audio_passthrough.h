#ifndef RUNNER_AUDIO_PASSTHROUGH_H_
#define RUNNER_AUDIO_PASSTHROUGH_H_

#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterAudioPassthrough(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_AUDIO_PASSTHROUGH_H_

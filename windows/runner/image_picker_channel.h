#ifndef RUNNER_IMAGE_PICKER_CHANNEL_H_
#define RUNNER_IMAGE_PICKER_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <functional>
#include <memory>

#include "image_picker.h"

class ImagePickerChannel final {
 public:
  using ViewResolver = std::function<HWND(int64_t)>;
  ImagePickerChannel(
      flutter::BinaryMessenger* messenger, ViewResolver resolve_view,
      image_picker::Request::Factory factory = image_picker::CreateImageDialog);
  ~ImagePickerChannel();
  ImagePickerChannel(const ImagePickerChannel&) = delete;
  ImagePickerChannel& operator=(const ImagePickerChannel&) = delete;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_IMAGE_PICKER_CHANNEL_H_

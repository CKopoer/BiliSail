#include "audio_passthrough.h"

#include <audioclient.h>
#include <mmdeviceapi.h>
#include <ks.h>
#include <ksmedia.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>

namespace {
bool DefaultEndpointAcceptsEac3() {
  using Microsoft::WRL::ComPtr;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  ComPtr<IAudioClient> audio;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&enumerator))) ||
      FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device)) ||
      FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_INPROC_SERVER,
                              nullptr, reinterpret_cast<void**>(audio.GetAddressOf())))) {
    return false;
  }

  // Match the pinned mpv IEC 61937 carrier, including its ordinary DD+ subtype.
  WAVEFORMATEXTENSIBLE format{};
  format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
  format.Format.nChannels = 2;
  format.Format.nSamplesPerSec = 192000;
  format.Format.wBitsPerSample = 16;
  format.Format.nBlockAlign = 4;
  format.Format.nAvgBytesPerSec = 192000 * 4;
  format.Format.cbSize = sizeof(format) - sizeof(WAVEFORMATEX);
  format.Samples.wValidBitsPerSample = 16;
  format.dwChannelMask = KSAUDIO_SPEAKER_STEREO;
  format.SubFormat = KSDATAFORMAT_SUBTYPE_IEC61937_DOLBY_DIGITAL_PLUS;
  return audio->IsFormatSupported(AUDCLNT_SHAREMODE_EXCLUSIVE, &format.Format,
                                  nullptr) == S_OK;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterAudioPassthrough(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "bilisail/audio_passthrough",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call, auto result) {
    if (call.method_name() == "acceptsEac3") {
      result->Success(flutter::EncodableValue(DefaultEndpointAcceptsEac3()));
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}

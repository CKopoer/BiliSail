#include "gpu_devices.h"

#include <dxgi1_2.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <cstdint>
#include <map>
#include <string>

#include "utils.h"

namespace {

HRESULT ReadGpuDevices(flutter::EncodableList& devices) {
  Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
  HRESULT status = CreateDXGIFactory1(IID_PPV_ARGS(factory.GetAddressOf()));
  if (FAILED(status)) return status;

  std::map<std::string, unsigned int> occurrences;
  // Preserve DXGI's indices even when excluding the software/WARP adapter.
  for (UINT index = 0; index < 64; ++index) {
    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    status = factory->EnumAdapters1(index, adapter.GetAddressOf());
    if (status == DXGI_ERROR_NOT_FOUND) return S_OK;
    if (FAILED(status)) return status;
    DXGI_ADAPTER_DESC1 description{};
    status = adapter->GetDesc1(&description);
    if (FAILED(status)) return status;
    if (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;

    // LUID is only valid until reboot. PCI identifiers plus an occurrence
    // distinguish persistent preferences without retaining enumeration indices.
    const std::string hardware_id =
        std::to_string(description.VendorId) + ":" +
        std::to_string(description.DeviceId) + ":" +
        std::to_string(description.SubSysId) + ":" +
        std::to_string(description.Revision);
    const std::string id = "dxgi:" + hardware_id + ":" +
                           std::to_string(occurrences[hardware_id]++);
    const std::string name = Utf8FromUtf16(description.Description);
    if (name.empty()) return E_FAIL;
    devices.emplace_back(flutter::EncodableMap{
        {flutter::EncodableValue("id"), flutter::EncodableValue(id)},
        {flutter::EncodableValue("name"), flutter::EncodableValue(name)},
        {flutter::EncodableValue("index"),
         flutter::EncodableValue(static_cast<int32_t>(index))},
    });
  }
  return E_FAIL;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterGpuDevices(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "bilisail/gpu_devices",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "listDevices") {
          result->NotImplemented();
          return;
        }
        flutter::EncodableList devices;
        if (FAILED(ReadGpuDevices(devices))) {
          result->Error("gpu_catalog_unavailable", "Could not read GPU devices");
          return;
        }
        result->Success(flutter::EncodableValue(std::move(devices)));
      });
  return channel;
}

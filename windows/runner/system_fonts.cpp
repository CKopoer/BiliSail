#include "system_fonts.h"

#include <dwrite.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <string>

namespace {

HRESULT ReadFontFamilies(flutter::EncodableList& families) {
  Microsoft::WRL::ComPtr<IDWriteFactory> factory;
  HRESULT status = DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(factory.GetAddressOf()));
  if (FAILED(status)) return status;

  Microsoft::WRL::ComPtr<IDWriteFontCollection> collection;
  status = factory->GetSystemFontCollection(collection.GetAddressOf(), TRUE);
  if (FAILED(status)) return status;

  const UINT32 count = collection->GetFontFamilyCount();
  families.reserve(count);
  for (UINT32 i = 0; i < count; ++i) {
    Microsoft::WRL::ComPtr<IDWriteFontFamily> family;
    status = collection->GetFontFamily(i, family.GetAddressOf());
    if (FAILED(status)) return status;

    Microsoft::WRL::ComPtr<IDWriteLocalizedStrings> names;
    status = family->GetFamilyNames(names.GetAddressOf());
    if (FAILED(status)) return status;
    UINT32 index = 0;
    BOOL exists = FALSE;
    status = names->FindLocaleName(L"en-us", &index, &exists);
    if (FAILED(status)) return status;
    if (!exists) index = 0;

    UINT32 length = 0;
    status = names->GetStringLength(index, &length);
    if (FAILED(status)) return status;
    // Match the settings boundary; font family names are not file paths.
    constexpr UINT32 kMaxFamilyLength = 200;
    if (length == 0 || length > kMaxFamilyLength) continue;
    std::wstring name(length + 1, L'\0');
    status = names->GetString(index, name.data(), length + 1);
    if (FAILED(status)) return status;
    const int byte_count = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, name.data(), static_cast<int>(length),
        nullptr, 0, nullptr, nullptr);
    if (byte_count == 0) return HRESULT_FROM_WIN32(GetLastError());
    std::string utf8(byte_count, '\0');
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, name.data(),
                            static_cast<int>(length), utf8.data(), byte_count,
                            nullptr, nullptr) == 0) {
      return HRESULT_FROM_WIN32(GetLastError());
    }
    families.emplace_back(std::move(utf8));
  }
  return S_OK;
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterSystemFonts(flutter::BinaryMessenger* messenger) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "bilisail/system_fonts",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "listFamilies") {
          result->NotImplemented();
          return;
        }
        flutter::EncodableList families;
        const HRESULT status = ReadFontFamilies(families);
        if (FAILED(status)) {
          result->Error("font_catalog_unavailable",
                        "Could not read installed font families");
          return;
        }
        result->Success(flutter::EncodableValue(std::move(families)));
      });
  return channel;
}

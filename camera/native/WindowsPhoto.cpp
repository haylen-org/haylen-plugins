#include "WindowsPhoto.hpp"

#include <cstring>

#include <windows.h>

#include <wincodec.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

std::optional<std::vector<std::uint8_t>> WindowsPhoto::encode(const std::vector<std::uint8_t>& pixels, int width, int height) {
    const std::size_t count = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
    std::vector<std::uint8_t> rows(count * 3);
    for (std::size_t pixel = 0; pixel < count; ++pixel) {
        std::memcpy(&rows[pixel * 3], &pixels[pixel * 4], 3);
    }

    ComPtr<IWICImagingFactory> factory;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory)))) {
        return std::nullopt;
    }
    ComPtr<IStream> stream;
    if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
        return std::nullopt;
    }
    ComPtr<IWICBitmapEncoder> encoder;
    if (FAILED(factory->CreateEncoder(GUID_ContainerFormatJpeg, nullptr, &encoder)) || FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
        return std::nullopt;
    }
    ComPtr<IWICBitmapFrameEncode> frame;
    ComPtr<IPropertyBag2> options;
    if (FAILED(encoder->CreateNewFrame(&frame, &options))) {
        return std::nullopt;
    }

    wchar_t qualityName[] = L"ImageQuality";
    PROPBAG2 option{};
    option.pstrName = qualityName;
    VARIANT quality{};
    quality.vt = VT_R4;
    quality.fltVal = 0.85f;
    if (FAILED(options->Write(1, &option, &quality)) || FAILED(frame->Initialize(options.Get()))) {
        return std::nullopt;
    }
    WICPixelFormatGUID format = GUID_WICPixelFormat24bppBGR;
    if (FAILED(frame->SetSize(static_cast<UINT>(width), static_cast<UINT>(height))) || FAILED(frame->SetPixelFormat(&format)) || format != GUID_WICPixelFormat24bppBGR) {
        return std::nullopt;
    }

    const UINT stride = static_cast<UINT>(width) * 3;
    if (FAILED(frame->WritePixels(static_cast<UINT>(height), stride, static_cast<UINT>(rows.size()), rows.data()))) {
        return std::nullopt;
    }
    if (FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
        return std::nullopt;
    }

    STATSTG status{};
    HGLOBAL memory = nullptr;
    if (FAILED(stream->Stat(&status, STATFLAG_NONAME)) || FAILED(GetHGlobalFromStream(stream.Get(), &memory))) {
        return std::nullopt;
    }
    const auto* bytes = static_cast<const std::uint8_t*>(GlobalLock(memory));
    std::vector<std::uint8_t> jpeg(bytes, bytes + status.cbSize.QuadPart);
    GlobalUnlock(memory);
    return jpeg;
}

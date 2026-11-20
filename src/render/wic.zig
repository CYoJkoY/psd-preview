const std = @import("std");
const abi = @import("../com/abi.zig");
const config = @import("../config.zig");
const pixels = @import("pixels.zig");

const HRESULT = abi.HRESULT;
const GUID = abi.GUID;
const IStream = abi.IStream;

pub const imaging_factory_clsid = GUID.parse("{CACAF262-9370-4615-A13B-9F5539DA4C0A}");
pub const imaging_factory_iid = GUID.parse("{EC5EC8A9-C395-4314-9C77-54D7A935FF70}");
pub const pixel_format_32bppBGRA = GUID.parse("{6FDDC324-4E03-4B03-B8FE-F8CBF2D2E9F3}");

pub const IWICImagingFactory = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICImagingFactory) callconv(abi.WINAPI) u32,
        CreateDecoderFromFilename: *const anyopaque,
        CreateDecoderFromStream: *const fn (*IWICImagingFactory, *IStream, ?*const GUID, u32, *?*IWICBitmapDecoder) callconv(abi.WINAPI) HRESULT,
        CreateDecoderFromFileHandle: *const anyopaque,
        CreateComponentEnumerator: *const anyopaque,
        CreateDecoder: *const anyopaque,
        CreateEncoder: *const anyopaque,
        CreatePalette: *const anyopaque,
        CreateFormatConverter: *const fn (*IWICImagingFactory, *?*IWICFormatConverter) callconv(abi.WINAPI) HRESULT,
        CreateBitmapScaler: *const fn (*IWICImagingFactory, *?*IWICBitmapScaler) callconv(abi.WINAPI) HRESULT,
    };
};

pub const IWICBitmapDecoder = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICBitmapDecoder) callconv(abi.WINAPI) u32,
        GetContainerFormat: *const anyopaque,
        GetDecoderInfo: *const anyopaque,
        CopyPalette: *const anyopaque,
        GetMetadataQueryReader: *const anyopaque,
        Initialize: *const anyopaque,
        GetColorContexts: *const anyopaque,
        GetPreview: *const anyopaque,
        GetThumbnail: *const anyopaque,
        GetFrameCount: *const fn (*IWICBitmapDecoder, *u32) callconv(abi.WINAPI) HRESULT,
        GetFrame: *const fn (*IWICBitmapDecoder, u32, *?*IWICBitmapFrameDecode) callconv(abi.WINAPI) HRESULT,
    };
};

pub const IWICBitmapSource = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICBitmapSource) callconv(abi.WINAPI) u32,
        GetSize: *const fn (*IWICBitmapSource, *u32, *u32) callconv(abi.WINAPI) HRESULT,
        GetPixelFormat: *const fn (*IWICBitmapSource, *GUID) callconv(abi.WINAPI) HRESULT,
        GetResolution: *const anyopaque,
        CopyPalette: *const anyopaque,
        CopyPixels: *const fn (*IWICBitmapSource, ?*const WICRect, u32, u32, [*]u8) callconv(abi.WINAPI) HRESULT,
    };
};

pub const IWICBitmapFrameDecode = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICBitmapFrameDecode) callconv(abi.WINAPI) u32,
        GetSize: *const fn (*IWICBitmapFrameDecode, *u32, *u32) callconv(abi.WINAPI) HRESULT,
        GetPixelFormat: *const anyopaque,
        GetResolution: *const anyopaque,
        CopyPalette: *const anyopaque,
        CopyPixels: *const anyopaque,
        GetMetadataQueryReader: *const anyopaque,
        GetColorContexts: *const anyopaque,
        GetThumbnail: *const anyopaque,
    };
};

pub const IWICFormatConverter = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICFormatConverter) callconv(abi.WINAPI) u32,
        GetSize: *const fn (*IWICFormatConverter, *u32, *u32) callconv(abi.WINAPI) HRESULT,
        GetPixelFormat: *const anyopaque,
        GetResolution: *const anyopaque,
        CopyPalette: *const anyopaque,
        CopyPixels: *const fn (*IWICFormatConverter, ?*const WICRect, u32, u32, [*]u8) callconv(abi.WINAPI) HRESULT,
        CanConvert: *const fn (*IWICFormatConverter, *const GUID, *const GUID, *u8) callconv(abi.WINAPI) HRESULT,
        Initialize: *const fn (*IWICFormatConverter, *IWICBitmapSource, *const GUID, u32, ?*const anyopaque, f64, u32) callconv(abi.WINAPI) HRESULT,
    };
};

pub const IWICBitmapScaler = extern struct {
    vtable: *const VTable,

    pub const VTable = extern struct {
        QueryInterface: *const anyopaque,
        AddRef: *const anyopaque,
        Release: *const fn (*IWICBitmapScaler) callconv(abi.WINAPI) u32,
        GetSize: *const fn (*IWICBitmapScaler, *u32, *u32) callconv(abi.WINAPI) HRESULT,
        GetPixelFormat: *const anyopaque,
        GetResolution: *const anyopaque,
        CopyPalette: *const anyopaque,
        CopyPixels: *const fn (*IWICBitmapScaler, ?*const WICRect, u32, u32, [*]u8) callconv(abi.WINAPI) HRESULT,
        Initialize: *const fn (*IWICBitmapScaler, *IWICBitmapSource, u32, u32, u32) callconv(abi.WINAPI) HRESULT,
    };
};

pub const WICRect = extern struct { x: i32, y: i32, width: i32, height: i32 };

extern "ole32" fn CoCreateInstance(class_id: *const GUID, outer: ?*anyopaque, context: u32, interface_id: *const GUID, object: *?*anyopaque) callconv(abi.WINAPI) HRESULT;
extern "shlwapi" fn SHCreateMemStream(data: [*]const u8, length: u32) callconv(abi.WINAPI) ?*IStream;

pub const DecodedImage = struct { width: u32, height: u32, pixels: []u8 };

fn initializeFactory(factory: *?*IWICImagingFactory) error{DecodeFailed}!void {
    var created: ?*IWICImagingFactory = null;
    if (CoCreateInstance(&imaging_factory_clsid, null, 0x1, &imaging_factory_iid, @ptrCast(&created)) != abi.S_OK) {
        return error.DecodeFailed;
    }
    factory.* = created orelse return error.DecodeFailed;
}

fn decodeJpegSource(factory: *IWICImagingFactory, jpeg: []const u8, converter: *?*IWICFormatConverter) error{DecodeFailed}!void {
    const jpeg_length = std.math.cast(u32, jpeg.len) orelse return error.DecodeFailed;
    const stream = SHCreateMemStream(jpeg.ptr, jpeg_length) orelse return error.DecodeFailed;
    defer _ = stream.vtable.Release(stream);
    var decoder: ?*IWICBitmapDecoder = null;
    if (factory.vtable.CreateDecoderFromStream(factory, stream, null, 0, &decoder) != abi.S_OK) return error.DecodeFailed;
    const active_decoder = decoder orelse return error.DecodeFailed;
    defer _ = active_decoder.vtable.Release(active_decoder);
    var frame_count: u32 = 0;
    if (active_decoder.vtable.GetFrameCount(active_decoder, &frame_count) != abi.S_OK or frame_count == 0) return error.DecodeFailed;
    var frame: ?*IWICBitmapFrameDecode = null;
    if (active_decoder.vtable.GetFrame(active_decoder, 0, &frame) != abi.S_OK) return error.DecodeFailed;
    const active_frame = frame orelse return error.DecodeFailed;
    defer _ = active_frame.vtable.Release(active_frame);
    var created_converter: ?*IWICFormatConverter = null;
    if (factory.vtable.CreateFormatConverter(factory, &created_converter) != abi.S_OK) return error.DecodeFailed;
    const created = created_converter orelse return error.DecodeFailed;
    converter.* = created;
    if (created.vtable.Initialize(created, @ptrCast(active_frame), &pixel_format_32bppBGRA, 1, null, 0.0, 0) != abi.S_OK) {
        _ = created.vtable.Release(created);
        converter.* = null;
        return error.DecodeFailed;
    }
}

pub fn decodeJpeg(allocator: std.mem.Allocator, jpeg: []const u8) error{ OutOfMemory, DecodeFailed }!DecodedImage {
    var factory: ?*IWICImagingFactory = null;
    try initializeFactory(&factory);
    const active_factory = factory orelse return error.DecodeFailed;
    defer _ = active_factory.vtable.Release(active_factory);
    var converter: ?*IWICFormatConverter = null;
    try decodeJpegSource(active_factory, jpeg, &converter);
    const active_converter = converter orelse return error.DecodeFailed;
    defer _ = active_converter.vtable.Release(active_converter);
    var width: u32 = 0;
    var height: u32 = 0;
    if (active_converter.vtable.GetSize(active_converter, &width, &height) != abi.S_OK) return error.DecodeFailed;
    if (width == 0 or height == 0 or width > config.max_image_dimension or height > config.max_image_dimension) return error.DecodeFailed;
    const stride = pixels.bgraStride(width) catch return error.DecodeFailed;
    const byte_count = pixels.bgraBytes(width, height) catch return error.DecodeFailed;
    const image_bytes = std.math.cast(u32, byte_count) orelse return error.DecodeFailed;
    const output = try allocator.alloc(u8, byte_count);
    if (active_converter.vtable.CopyPixels(active_converter, null, stride, image_bytes, output.ptr) != abi.S_OK) {
        allocator.free(output);
        return error.DecodeFailed;
    }
    return .{ .width = width, .height = height, .pixels = output };
}

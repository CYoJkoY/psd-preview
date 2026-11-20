const std = @import("std");
const windows = std.os.windows;

pub const HRESULT = i32;
pub const GUID = windows.GUID;
pub const WINAPI = std.builtin.CallingConvention.winapi;
pub const HWND = windows.HWND;
pub const HBITMAP = *opaque {};
pub const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
pub const WTS_ALPHATYPE = enum(u32) { unknown = 0, rgb = 1, argb = 2 };
pub const S_OK: HRESULT = 0;
pub const S_FALSE: HRESULT = 1;
pub const E_NOINTERFACE: HRESULT = @bitCast(@as(u32, 0x80004002));
pub const E_POINTER: HRESULT = @bitCast(@as(u32, 0x80004003));
pub const E_NOTIMPL: HRESULT = @bitCast(@as(u32, 0x80004001));
pub const E_FAIL: HRESULT = @bitCast(@as(u32, 0x80004005));
pub const CLASS_E_CLASSNOTAVAILABLE: HRESULT = @bitCast(@as(u32, 0x80040111));
pub const E_INVALIDARG: HRESULT = @bitCast(@as(u32, 0x80070057));
pub const CLASS_E_NOAGGREGATION: HRESULT = @bitCast(@as(u32, 0x80040110));
pub const E_OUTOFMEMORY: HRESULT = @bitCast(@as(u32, 0x8007000e));

pub const IUnknown = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IUnknown, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IUnknown) callconv(WINAPI) u32,
        Release: *const fn (*IUnknown) callconv(WINAPI) u32,
    };
};

pub const IStream = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IStream, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IStream) callconv(WINAPI) u32,
        Release: *const fn (*IStream) callconv(WINAPI) u32,
        Read: *const fn (*IStream, [*]u8, u32, ?*u32) callconv(WINAPI) HRESULT,
        Write: *const anyopaque,
        Seek: *const fn (*IStream, i64, u32, ?*u64) callconv(WINAPI) HRESULT,
        SetSize: *const anyopaque,
        CopyTo: *const anyopaque,
        Commit: *const anyopaque,
        Revert: *const anyopaque,
        LockRegion: *const anyopaque,
        UnlockRegion: *const anyopaque,
        Stat: *const anyopaque,
        Clone: *const anyopaque,
    };
};

pub const IInitializeWithStream = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IInitializeWithStream, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IInitializeWithStream) callconv(WINAPI) u32,
        Release: *const fn (*IInitializeWithStream) callconv(WINAPI) u32,
        Initialize: *const fn (*IInitializeWithStream, *IStream, u32) callconv(WINAPI) HRESULT,
    };
};

pub const IThumbnailProvider = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IThumbnailProvider, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IThumbnailProvider) callconv(WINAPI) u32,
        Release: *const fn (*IThumbnailProvider) callconv(WINAPI) u32,
        GetThumbnail: *const fn (*IThumbnailProvider, u32, *?HBITMAP, *WTS_ALPHATYPE) callconv(WINAPI) HRESULT,
    };
};

pub const IPreviewHandler = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IPreviewHandler, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IPreviewHandler) callconv(WINAPI) u32,
        Release: *const fn (*IPreviewHandler) callconv(WINAPI) u32,
        SetWindow: *const fn (*IPreviewHandler, HWND, *const RECT) callconv(WINAPI) HRESULT,
        SetRect: *const fn (*IPreviewHandler, *const RECT) callconv(WINAPI) HRESULT,
        DoPreview: *const fn (*IPreviewHandler) callconv(WINAPI) HRESULT,
        Unload: *const fn (*IPreviewHandler) callconv(WINAPI) HRESULT,
        SetFocus: *const fn (*IPreviewHandler) callconv(WINAPI) HRESULT,
        QueryFocus: *const fn (*IPreviewHandler, *?HWND) callconv(WINAPI) HRESULT,
        TranslateAccelerator: *const fn (*IPreviewHandler, *anyopaque) callconv(WINAPI) HRESULT,
    };
};

pub const BITMAPINFOHEADER = extern struct {
    size: u32 = 40,
    width: i32,
    height: i32,
    planes: u16 = 1,
    bit_count: u16 = 32,
    compression: u32 = 0,
    size_image: u32,
    x_pixels_per_meter: i32 = 0,
    y_pixels_per_meter: i32 = 0,
    colors_used: u32 = 0,
    colors_important: u32 = 0,
};

pub const BITMAPINFO = extern struct {
    header: BITMAPINFOHEADER,
    colors: [1]u32 = .{0},
};

pub const IClassFactory = extern struct {
    vtable: *const VTable,
    pub const VTable = extern struct {
        QueryInterface: *const fn (*IClassFactory, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        AddRef: *const fn (*IClassFactory) callconv(WINAPI) u32,
        Release: *const fn (*IClassFactory) callconv(WINAPI) u32,
        CreateInstance: *const fn (*IClassFactory, ?*IUnknown, *const GUID, *?*anyopaque) callconv(WINAPI) HRESULT,
        LockServer: *const fn (*IClassFactory, i32) callconv(WINAPI) HRESULT,
    };
};

const std = @import("std");
const parser = @import("../psd/parser.zig");
const config = @import("../config.zig");
const abi = @import("abi.zig");
const rendering = @import("../render/rendering.zig");
const state = @import("state.zig");
const stream_reader = @import("stream_reader.zig");

const HRESULT = abi.HRESULT;
const GUID = abi.GUID;
const IStream = abi.IStream;
const IUnknown = abi.IUnknown;
const IInitializeWithStream = abi.IInitializeWithStream;
const IThumbnailProvider = abi.IThumbnailProvider;
const IPreviewHandler = abi.IPreviewHandler;
const WTS_ALPHATYPE = abi.WTS_ALPHATYPE;

pub const Handler = struct {
    initialize: IInitializeWithStream,
    thumbnail: IThumbnailProvider,
    preview: IPreviewHandler,
    refs: std.atomic.Value(u32),
    allocator: std.mem.Allocator,
    stream: ?*IStream,
    document: ?parser.Document,
    host_window: ?abi.HWND,
    host_rect: abi.RECT,
    child_window: ?abi.HWND,
    view: rendering.ViewState,
    /// Owns the bytes the parsed `Document` slices point into. Freed only after
    /// the document is released, which keeps `document.jpeg` valid.
    source_data: ?[]u8,
    pixels: ?[]u8,
    pixels_width: u32,
    pixels_height: u32,

    const vtable_initialize = IInitializeWithStream.VTable{
        .QueryInterface = initializeQueryInterface,
        .AddRef = initializeAddRef,
        .Release = initializeRelease,
        .Initialize = initializeStream,
    };
    const vtable_thumbnail = IThumbnailProvider.VTable{
        .QueryInterface = thumbnailQueryInterface,
        .AddRef = thumbnailAddRef,
        .Release = thumbnailRelease,
        .Initialize = thumbnailInitialize,
        .GetThumbnail = getThumbnail,
    };
    const vtable_preview = IPreviewHandler.VTable{
        .QueryInterface = previewQueryInterface,
        .AddRef = previewAddRef,
        .Release = previewRelease,
        .SetWindow = previewSetWindow,
        .SetRect = previewSetRect,
        .DoPreview = previewDoPreview,
        .Unload = previewUnload,
        .SetFocus = previewSetFocus,
        .QueryFocus = previewQueryFocus,
        .TranslateAccelerator = previewTranslateAccelerator,
    };

    pub fn create(allocator: std.mem.Allocator) error{OutOfMemory}!*Handler {
        const handler = try allocator.create(Handler);
        handler.* = .{
            .initialize = .{ .vtable = &vtable_initialize },
            .thumbnail = .{ .vtable = &vtable_thumbnail },
            .preview = .{ .vtable = &vtable_preview },
            .refs = std.atomic.Value(u32).init(1),
            .allocator = allocator,
            .stream = null,
            .document = null,
            .host_window = null,
            .host_rect = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
            .child_window = null,
            .view = rendering.ViewState{},
            .source_data = null,
            .pixels = null,
            .pixels_width = 0,
            .pixels_height = 0,
        };
        _ = state.object_count.fetchAdd(1, .monotonic);
        return handler;
    }

    fn supportedInterface(iid: *const GUID) bool {
        return abi.guidEql(iid, &config.unknown_iid) or
            abi.guidEql(iid, &config.initialize_stream_iid) or
            abi.guidEql(iid, &config.thumbnail_iid) or
            abi.guidEql(iid, &config.preview_iid);
    }

    fn retain(self_object: *Handler) u32 {
        return self_object.refs.fetchAdd(1, .monotonic) + 1;
    }

    fn release(self_object: *Handler) u32 {
        const value = self_object.refs.fetchSub(1, .acq_rel);
        if (value == 1) {
            rendering.destroyPreviewWindow(self_object);
            self_object.clearDocument();
            if (self_object.stream) |stream| _ = stream.vtable.Release(stream);
            _ = state.object_count.fetchSub(1, .monotonic);
            self_object.allocator.destroy(self_object);
            return 0;
        }
        return value - 1;
    }

    /// Drops every decoded artifact in dependency order: the document first
    /// (it borrows `source_data`), then the source buffer, then the cached
    /// preview pixels.
    fn clearDocument(handler: *Handler) void {
        if (handler.document) |*document| {
            document.deinit();
            handler.document = null;
        }
        if (handler.source_data) |data| {
            handler.allocator.free(data);
            handler.source_data = null;
        }
        if (handler.pixels) |pixels| {
            handler.allocator.free(pixels);
            handler.pixels = null;
        }
        handler.pixels_width = 0;
        handler.pixels_height = 0;
    }

    /// Stores an already-referenced stream, dropping any previous document.
    /// Callers that receive a fresh reference (for example `BindToHandler`)
    /// pass it straight in; `initializeStream` adds a reference first.
    fn adoptStream(handler: *Handler, stream: *IStream) void {
        if (handler.stream) |existing| _ = existing.vtable.Release(existing);
        handler.stream = null;
        handler.clearDocument();
        handler.stream = stream;
    }

    fn queryInterface(handler: *Handler, iid: *const GUID, object: *?*anyopaque) HRESULT {
        if (!supportedInterface(iid)) {
            object.* = null;
            return abi.E_NOINTERFACE;
        }
        if (abi.guidEql(iid, &config.thumbnail_iid)) {
            object.* = @ptrCast(&handler.thumbnail);
        } else if (abi.guidEql(iid, &config.preview_iid)) {
            object.* = @ptrCast(&handler.preview);
        } else {
            object.* = @ptrCast(&handler.initialize);
        }
        _ = retain(handler);
        return abi.S_OK;
    }

    fn initializeQueryInterface(interface: *IInitializeWithStream, iid: *const GUID, object: *?*anyopaque) callconv(abi.WINAPI) HRESULT {
        return queryInterface(selfFromInitialize(interface), iid, object);
    }

    fn thumbnailQueryInterface(interface: *IThumbnailProvider, iid: *const GUID, object: *?*anyopaque) callconv(abi.WINAPI) HRESULT {
        return queryInterface(selfFromThumbnail(interface), iid, object);
    }

    fn previewQueryInterface(interface: *IPreviewHandler, iid: *const GUID, object: *?*anyopaque) callconv(abi.WINAPI) HRESULT {
        return queryInterface(selfFromPreview(interface), iid, object);
    }

    fn initializeAddRef(interface: *IInitializeWithStream) callconv(abi.WINAPI) u32 {
        return retain(selfFromInitialize(interface));
    }

    fn initializeRelease(interface: *IInitializeWithStream) callconv(abi.WINAPI) u32 {
        return release(selfFromInitialize(interface));
    }

    fn initializeStream(interface: *IInitializeWithStream, stream: *IStream, mode: u32) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromInitialize(interface);
        if (mode != 0) return abi.E_INVALIDARG;
        _ = stream.vtable.AddRef(stream);
        handler.adoptStream(stream);
        return abi.S_OK;
    }

    fn thumbnailAddRef(interface: *IThumbnailProvider) callconv(abi.WINAPI) u32 {
        return retain(selfFromThumbnail(interface));
    }

    fn thumbnailRelease(interface: *IThumbnailProvider) callconv(abi.WINAPI) u32 {
        return release(selfFromThumbnail(interface));
    }

    fn thumbnailInitialize(interface: *IThumbnailProvider, item: *abi.IShellItem, cache: *abi.IThumbnailCache) callconv(abi.WINAPI) HRESULT {
        _ = cache;
        const handler = selfFromThumbnail(interface);
        var stream_ptr: ?*anyopaque = null;
        const result = item.vtable.BindToHandler(item, null, &config.stream_bhid, &config.stream_iid, &stream_ptr);
        if (result != abi.S_OK) return result;
        const stream = @as(?*IStream, @ptrCast(@alignCast(stream_ptr))) orelse return abi.E_FAIL;
        handler.adoptStream(stream);
        return abi.S_OK;
    }

    fn previewAddRef(interface: *IPreviewHandler) callconv(abi.WINAPI) u32 {
        return retain(selfFromPreview(interface));
    }

    fn previewRelease(interface: *IPreviewHandler) callconv(abi.WINAPI) u32 {
        return release(selfFromPreview(interface));
    }

    fn ensureDocument(handler: *Handler) HRESULT {
        if (handler.document != null) return abi.S_OK;
        const stream = handler.stream orelse return abi.E_POINTER;
        const data = stream_reader.readAll(handler.allocator, stream) catch return abi.E_FAIL;
        const document = parser.parse(handler.allocator, data) catch {
            handler.allocator.free(data);
            return abi.E_FAIL;
        };
        handler.source_data = data;
        handler.document = document;
        return abi.S_OK;
    }

    fn getThumbnail(interface: *IThumbnailProvider, requested_size: u32, bitmap: *?abi.HBITMAP, alpha_type: *WTS_ALPHATYPE) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromThumbnail(interface);
        bitmap.* = null;
        alpha_type.* = .unknown;
        if (requested_size == 0) return abi.E_INVALIDARG;
        if (ensureDocument(handler) != abi.S_OK) return abi.E_FAIL;
        const document = handler.document orelse return abi.E_FAIL;
        const bitmap_handle = rendering.createThumbnail(handler.allocator, document, requested_size) catch return abi.E_FAIL;
        bitmap.* = bitmap_handle;
        alpha_type.* = .argb;
        return abi.S_OK;
    }

    fn previewSetWindow(interface: *IPreviewHandler, parent: abi.HWND, rect: *const abi.RECT) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        handler.host_window = parent;
        handler.host_rect = rect.*;
        return rendering.updatePreviewWindow(handler, true);
    }

    fn previewSetRect(interface: *IPreviewHandler, rect: *const abi.RECT) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        handler.host_rect = rect.*;
        return rendering.updatePreviewWindow(handler, false);
    }

    fn previewDoPreview(interface: *IPreviewHandler) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        const result = ensureDocument(handler);
        if (result != abi.S_OK) return result;
        return rendering.updatePreviewWindow(handler, true);
    }

    fn previewUnload(interface: *IPreviewHandler) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        rendering.destroyPreviewWindow(handler);
        handler.clearDocument();
        return abi.S_OK;
    }

    fn previewSetFocus(interface: *IPreviewHandler) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        const child = handler.child_window orelse return abi.E_FAIL;
        return if (rendering.user32.SetFocus(child) == null) abi.E_FAIL else abi.S_OK;
    }

    fn previewQueryFocus(interface: *IPreviewHandler, focused: *?abi.HWND) callconv(abi.WINAPI) HRESULT {
        const handler = selfFromPreview(interface);
        focused.* = null;
        const child = handler.child_window orelse return abi.E_FAIL;
        focused.* = rendering.user32.GetFocus();
        if (focused.* == null) return abi.E_FAIL;
        if (child != focused.*) return abi.S_FALSE;
        return abi.S_OK;
    }

    fn previewTranslateAccelerator(interface: *IPreviewHandler, message: *anyopaque) callconv(abi.WINAPI) HRESULT {
        _ = interface;
        _ = message;
        return abi.S_FALSE;
    }
};

fn selfFromInitialize(interface: *IInitializeWithStream) *Handler {
    return @fieldParentPtr("initialize", interface);
}

fn selfFromThumbnail(interface: *IThumbnailProvider) *Handler {
    return @fieldParentPtr("thumbnail", interface);
}

fn selfFromPreview(interface: *IPreviewHandler) *Handler {
    return @fieldParentPtr("preview", interface);
}

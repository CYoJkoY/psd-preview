const std = @import("std");
const parser = @import("../psd/parser.zig");
const config = @import("../config.zig");
const abi = @import("../com/abi.zig");
const wic = @import("wic.zig");
const pixel_math = @import("pixels.zig");
const thumbnail_math = @import("thumbnail.zig");
const Handler = @import("../com/handler.zig").Handler;

const HRESULT = abi.HRESULT;
const HBITMAP = abi.HBITMAP;
const HWND = abi.HWND;

pub const COLORREF = u32;

const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: usize,
    lParam: isize,
    time: u32,
    point: POINT,
};

const POINT = extern struct {
    x: i32,
    y: i32,
};

const PAINTSTRUCT = extern struct {
    hdc: ?HDC,
    erased: i32,
    paint: RECT,
    restore: i32,
    update: i32,
    reserved: [32]u8,
};

const HDC = *opaque {};
const HBRUSH = *opaque {};
const HCURSOR = *opaque {};
const HGDIOBJ = *opaque {};
const HICON = *opaque {};
const HINSTANCE = *opaque {};
const HMODULE = opaque {};
const CREATESTRUCT = extern struct {
    create_params: ?*anyopaque,
    instance: ?HINSTANCE,
    menu: ?*anyopaque,
    parent: ?HWND,
    cy: i32,
    cx: i32,
    y: i32,
    x: i32,
    style: i32,
    name: ?[*:0]const u16,
    class: ?[*:0]const u16,
    ex_style: u32,
};

const GWLP_USERDATA = -21;
const WM_NCCREATE = 0x0081;
const WM_PAINT = 0x000F;
const WM_SIZE = 0x0005;
const WM_MOUSEWHEEL = 0x020A;
const WM_LBUTTONDOWN = 0x0201;
const WM_LBUTTONUP = 0x0202;
const WM_LBUTTONDBLCLK = 0x0203;
const WM_MOUSEMOVE = 0x0200;
const WM_NCDESTROY = 0x0082;

pub const Viewport = struct {
    offset_x: i32 = 0,
    offset_y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    scale: f32 = 1.0,
};

pub const ViewState = struct {
    viewport: Viewport = .{},
    fit: bool = true,
    dragging: bool = false,
    drag_start: POINT = .{ .x = 0, .y = 0 },
    drag_offset: POINT = .{ .x = 0, .y = 0 },
};

const window_class_name = [_]u16{ 'P', 'S', 'D', 'P', 'r', 'e', 'v', 'i', 'e', 'w', 0 };
const cell_size = 16;

pub const user32 = struct {
    pub extern "user32" fn RegisterClassW(class: *const WNDCLASS) callconv(.winapi) u16;
    pub extern "user32" fn CreateWindowExW(style: u32, class: [*]const u16, title: [*]const u16, style2: u32, x: i32, y: i32, width: i32, height: i32, parent: ?HWND, menu: ?*anyopaque, instance: ?HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?HWND;
    pub extern "user32" fn DestroyWindow(window: HWND) callconv(.winapi) i32;
    pub extern "user32" fn SetWindowPos(window: HWND, insert_after: ?HWND, x: i32, y: i32, width: i32, height: i32, flags: u32) callconv(.winapi) i32;
    pub extern "user32" fn DefWindowProcW(window: HWND, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;
    pub extern "user32" fn InvalidateRect(window: HWND, rect: ?*const RECT, erase: i32) callconv(.winapi) i32;
    pub extern "user32" fn GetClientRect(window: HWND, rect: *RECT) callconv(.winapi) i32;
    pub extern "user32" fn GetFocus() callconv(.winapi) ?HWND;
    pub extern "user32" fn SetFocus(window: HWND) callconv(.winapi) ?HWND;
    pub extern "user32" fn LoadCursorW(instance: ?HINSTANCE, cursor: ?*const anyopaque) callconv(.winapi) ?HCURSOR;
    pub extern "user32" fn ShowWindow(window: HWND, command: i32) callconv(.winapi) i32;
    pub extern "user32" fn GetMessageW(message: *MSG, window: ?HWND, first: u32, last: u32) callconv(.winapi) i32;
    pub extern "user32" fn TranslateMessage(message: *const MSG) callconv(.winapi) i32;
    pub extern "user32" fn DispatchMessageW(message: *const MSG) callconv(.winapi) isize;
    pub extern "user32" fn GetDoubleClickTime() callconv(.winapi) u32;
    pub extern "user32" fn BeginPaint(window: HWND, paint: *PAINTSTRUCT) callconv(.winapi) ?HDC;
    pub extern "user32" fn EndPaint(window: HWND, paint: *const PAINTSTRUCT) callconv(.winapi) i32;
    pub extern "user32" fn SetWindowLongPtrW(window: HWND, index: i32, value: isize) callconv(.winapi) isize;
    pub extern "user32" fn GetWindowLongPtrW(window: HWND, index: i32) callconv(.winapi) isize;
    pub extern "user32" fn SetCapture(window: HWND) callconv(.winapi) ?HWND;
    pub extern "user32" fn ReleaseCapture() callconv(.winapi) i32;
    pub extern "user32" fn ScreenToClient(window: HWND, point: *POINT) callconv(.winapi) i32;
};

pub const gdi32 = struct {
    pub extern "gdi32" fn CreateDIBSection(hdc: ?HDC, info: *const abi.BITMAPINFO, usage: u32, bits: *[*]u8, section: ?*anyopaque, offset: u32) callconv(.winapi) ?HBITMAP;
    pub extern "gdi32" fn CreateCompatibleDC(hdc: ?HDC) callconv(.winapi) ?HDC;
    pub extern "gdi32" fn DeleteDC(hdc: HDC) callconv(.winapi) i32;
    pub extern "gdi32" fn DeleteObject(object: HGDIOBJ) callconv(.winapi) i32;
    pub extern "gdi32" fn SelectObject(hdc: HDC, object: HGDIOBJ) callconv(.winapi) HGDIOBJ;
    pub extern "gdi32" fn BitBlt(destination: HDC, x: i32, y: i32, width: i32, height: i32, source: HDC, source_x: i32, source_y: i32, rop: u32) callconv(.winapi) i32;
    pub extern "gdi32" fn CreateSolidBrush(color: COLORREF) callconv(.winapi) ?HBRUSH;
    pub extern "gdi32" fn SetStretchBltMode(hdc: HDC, mode: i32) callconv(.winapi) i32;
    pub extern "gdi32" fn AlphaBlend(destination: HDC, x: i32, y: i32, width: i32, height: i32, source: HDC, source_x: i32, source_y: i32, source_width: i32, source_height: i32, blend: BLENDFUNCTION) callconv(.winapi) i32;
};

const BLENDFUNCTION = extern struct { operation: u8 = 0, flags: u8 = 0, constant_alpha: u8 = 255, alpha_format: u8 = 1 };

const WNDCLASS = extern struct {
    style: u32,
    proc: *const fn (HWND, u32, usize, isize) callconv(.winapi) isize,
    extra: i32,
    window_extra: i32,
    instance: ?HINSTANCE,
    icon: ?HICON,
    cursor: ?HCURSOR,
    brush: ?HBRUSH,
    menu_name: ?[*]const u16,
    class_name: [*]const u16,
};

var class_registered = false;

fn registerClass() HRESULT {
    if (class_registered) return abi.S_OK;
    var class = WNDCLASS{
        .style = 0,
        .proc = windowProc,
        .extra = 0,
        .window_extra = 0,
        .instance = null,
        .icon = null,
        .cursor = user32.LoadCursorW(null, @ptrFromInt(32512)),
        .brush = null,
        .menu_name = null,
        .class_name = @ptrCast(&window_class_name),
    };
    if (user32.RegisterClassW(&class) == 0) return abi.E_FAIL;
    class_registered = true;
    return abi.S_OK;
}

fn windowProc(window: HWND, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    if (message == WM_NCCREATE) {
        const create: *const CREATESTRUCT = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (create.create_params) |params| _ = user32.SetWindowLongPtrW(window, GWLP_USERDATA, @intCast(@intFromPtr(params)));
    }
    const raw_handler = user32.GetWindowLongPtrW(window, GWLP_USERDATA);
    if (raw_handler == 0) return user32.DefWindowProcW(window, message, wparam, lparam);
    const handler: *Handler = @ptrFromInt(@as(usize, @bitCast(raw_handler)));
    switch (message) {
        WM_PAINT => handlePaint(handler, window),
        WM_SIZE => _ = user32.InvalidateRect(window, null, 0),
        WM_MOUSEWHEEL => {
            const wheel_delta: i16 = @bitCast(@as(u16, @truncate(wparam >> 16)));
            var point = POINT{ .x = @truncate(lparam), .y = @truncate(lparam >> 16) };
            _ = user32.ScreenToClient(window, &point);
            handleWheel(handler, wheel_delta, point);
        },
        WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK => {
            const point = POINT{ .x = @truncate(lparam), .y = @truncate(lparam >> 16) };
            handleMouseButton(handler, message, point);
            if (message == WM_LBUTTONDOWN) _ = user32.SetCapture(window);
            if (message == WM_LBUTTONUP) _ = user32.ReleaseCapture();
        },
        WM_MOUSEMOVE => {
            const point = POINT{ .x = @truncate(lparam), .y = @truncate(lparam >> 16) };
            handleMouseMove(handler, point);
        },
        WM_NCDESTROY => {
            _ = user32.SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            if (handler.child_window == window) handler.child_window = null;
            return user32.DefWindowProcW(window, message, wparam, lparam);
        },
        else => return user32.DefWindowProcW(window, message, wparam, lparam),
    }
    return 0;
}

pub fn updatePreviewWindow(handler: *Handler, recreate: bool) HRESULT {
    if (registerClass() != abi.S_OK) return abi.E_FAIL;
    if (handler.child_window != null and !recreate) {
        if (handler.child_window) |window| {
            const rect = &handler.host_rect;
            const width = @max(1, rect.right - rect.left);
            const height = @max(1, rect.bottom - rect.top);
            if (user32.SetWindowPos(window, null, rect.left, rect.top, width, height, 0x0010 | 0x0004) == 0) return abi.E_FAIL;
            _ = user32.InvalidateRect(window, null, 0);
        }
        return abi.S_OK;
    }
    destroyPreviewWindow(handler);
    if (handler.host_window == null) return abi.S_OK;
    const rect = &handler.host_rect;
    const width = @max(1, rect.right - rect.left);
    const height = @max(1, rect.bottom - rect.top);
    const child = user32.CreateWindowExW(
        0,
        @ptrCast(&window_class_name),
        @ptrCast(&window_class_name),
        0x10000000 | 0x04000000,
        rect.left,
        rect.top,
        width,
        height,
        handler.host_window,
        null,
        null,
        handler,
    ) orelse return abi.E_FAIL;
    handler.child_window = child;
    _ = user32.ShowWindow(child, 5);
    _ = user32.InvalidateRect(child, null, 1);
    return abi.S_OK;
}

pub fn destroyPreviewWindow(handler: *Handler) void {
    if (handler.child_window) |window| {
        _ = user32.DestroyWindow(window);
        handler.child_window = null;
    }
}

pub fn handlePaint(handler: *Handler, window: HWND) void {
    var paint: PAINTSTRUCT = undefined;
    const destination = user32.BeginPaint(window, &paint) orelse return;
    defer _ = user32.EndPaint(window, &paint);
    var client: RECT = undefined;
    _ = user32.GetClientRect(window, &client);
    const width = @max(1, client.right - client.left);
    const height = @max(1, client.bottom - client.top);

    const screen_bytes = pixel_math.bgraBytes(@intCast(width), @intCast(height)) catch return;
    const screen_size_image = std.math.cast(u32, screen_bytes) orelse return;
    var screen_info = abi.BITMAPINFO{
        .header = .{
            .width = width,
            .height = -@as(i32, @intCast(height)),
            .size_image = screen_size_image,
        },
    };
    var screen_bits: [*]u8 = undefined;
    const screen_dc = gdi32.CreateCompatibleDC(destination) orelse return;
    defer _ = gdi32.DeleteDC(screen_dc);
    const screen_bitmap = gdi32.CreateDIBSection(destination, &screen_info, 0, &screen_bits, null, 0) orelse return;
    defer _ = gdi32.DeleteObject(@ptrCast(screen_bitmap));
    const old_bitmap = gdi32.SelectObject(screen_dc, @ptrCast(screen_bitmap));
    defer _ = gdi32.SelectObject(screen_dc, old_bitmap);
    drawCheckerboard(screen_bits[0..screen_bytes], width, height);

    if (prepareSource(handler)) |source| {
        if (prepareView(handler, width, height, source.width, source.height)) |viewport| {
            if (createSourceBitmap(destination, source.width, source.height, source.bytes)) |source_bitmap| {
                defer _ = gdi32.DeleteObject(@ptrCast(source_bitmap));
                const source_dc = gdi32.CreateCompatibleDC(destination) orelse return;
                defer _ = gdi32.DeleteDC(source_dc);
                const old_source_bitmap = gdi32.SelectObject(source_dc, @ptrCast(source_bitmap));
                defer _ = gdi32.SelectObject(source_dc, old_source_bitmap);
                _ = gdi32.SetStretchBltMode(screen_dc, 4);
                _ = gdi32.AlphaBlend(
                    screen_dc,
                    viewport.offset_x,
                    viewport.offset_y,
                    viewport.width,
                    viewport.height,
                    source_dc,
                    0,
                    0,
                    @intCast(source.width),
                    @intCast(source.height),
                    .{},
                );
            }
        }
    }
    _ = gdi32.BitBlt(destination, 0, 0, width, height, screen_dc, 0, 0, 0x00CC0020);
}

fn prepareView(handler: *Handler, client_width: i32, client_height: i32, source_width_u32: u32, source_height_u32: u32) ?Viewport {
    if (handler.document == null) return null;
    if (source_width_u32 == 0 or source_height_u32 == 0) return null;
    const source_width: f32 = @floatFromInt(source_width_u32);
    const source_height: f32 = @floatFromInt(source_height_u32);
    const scale_x = @as(f32, @floatFromInt(client_width)) / source_width;
    const scale_y = @as(f32, @floatFromInt(client_height)) / source_height;
    var scale = @min(@min(scale_x, scale_y), 1.0);
    if (!handler.view.fit) scale = handler.view.viewport.scale;
    scale = std.math.clamp(scale, config.min_zoom, config.max_zoom);
    const output_width: i32 = @intFromFloat(source_width * scale);
    const output_height: i32 = @intFromFloat(source_height * scale);
    const offset_x = @divTrunc(client_width - output_width, 2) + handler.view.viewport.offset_x;
    const offset_y = @divTrunc(client_height - output_height, 2) + handler.view.viewport.offset_y;
    return .{
        .offset_x = offset_x,
        .offset_y = offset_y,
        .width = output_width,
        .height = output_height,
        .scale = scale,
    };
}

const SourcePixels = struct {
    width: u32,
    height: u32,
    bytes: []const u8,
};

fn prepareSource(handler: *Handler) ?SourcePixels {
    const document = handler.document orelse return null;
    if (document.pixels) |pixels| return .{ .width = document.width, .height = document.height, .bytes = pixels };
    if (handler.pixels) |pixels| return .{ .width = handler.pixels_width, .height = handler.pixels_height, .bytes = pixels };
    const jpeg = document.jpeg orelse return null;
    const decoded = wic.decodeJpeg(handler.allocator, jpeg) catch return null;
    handler.pixels = decoded.pixels;
    handler.pixels_width = decoded.width;
    handler.pixels_height = decoded.height;
    return .{ .width = decoded.width, .height = decoded.height, .bytes = decoded.pixels };
}

fn effectiveSourceSize(handler: *Handler) ?struct { width: u32, height: u32 } {
    const document = handler.document orelse return null;
    if (handler.pixels != null and handler.pixels_width != 0 and handler.pixels_height != 0) {
        return .{ .width = handler.pixels_width, .height = handler.pixels_height };
    }
    return .{ .width = document.width, .height = document.height };
}

pub fn handleWheel(handler: *Handler, wheel_delta: isize, point: POINT) void {
    const size = effectiveSourceSize(handler) orelse return;
    const old_scale = if (handler.view.fit) 1.0 else handler.view.viewport.scale;
    const factor: f32 = if (wheel_delta > 0) 1.2 else 1.0 / 1.2;
    const new_scale = std.math.clamp(old_scale * factor, config.min_zoom, config.max_zoom);
    const source_width: f32 = @floatFromInt(size.width);
    const source_height: f32 = @floatFromInt(size.height);
    var client: RECT = undefined;
    if (handler.child_window) |window| _ = user32.GetClientRect(window, &client) else return;
    const old_fit_scale = @min(@as(f32, @floatFromInt(client.right)) / source_width, @as(f32, @floatFromInt(client.bottom)) / source_height);
    const old_scale_actual = if (handler.view.fit) @min(old_fit_scale, 1.0) else old_scale;
    const origin_x = (@as(f32, @floatFromInt(client.right)) - source_width * old_scale_actual) / 2.0 + @as(f32, @floatFromInt(handler.view.viewport.offset_x));
    const origin_y = (@as(f32, @floatFromInt(client.bottom)) - source_height * old_scale_actual) / 2.0 + @as(f32, @floatFromInt(handler.view.viewport.offset_y));
    const local_x = @as(f32, @floatFromInt(point.x)) - origin_x;
    const local_y = @as(f32, @floatFromInt(point.y)) - origin_y;
    if (old_scale > 0.0) {
        const fit_scale = @min(@as(f32, @floatFromInt(client.right)) / source_width, @as(f32, @floatFromInt(client.bottom)) / source_height);
        const anchor_scale = if (handler.view.fit) @min(fit_scale, 1.0) else old_scale;
        handler.view.viewport.offset_x = @intFromFloat(@as(f32, @floatFromInt(point.x)) - (local_x / anchor_scale) * new_scale - (@as(f32, @floatFromInt(client.right)) - source_width * new_scale) / 2.0);
        handler.view.viewport.offset_y = @intFromFloat(@as(f32, @floatFromInt(point.y)) - (local_y / anchor_scale) * new_scale - (@as(f32, @floatFromInt(client.bottom)) - source_height * new_scale) / 2.0);
    }
    handler.view.viewport.scale = new_scale;
    handler.view.fit = false;
    if (handler.child_window) |window| _ = user32.InvalidateRect(window, null, 0);
}

pub fn handleMouseButton(handler: *Handler, message: u32, point: POINT) void {
    switch (message) {
        0x0201 => {
            handler.view.dragging = true;
            handler.view.drag_start = point;
            handler.view.drag_offset = .{
                .x = handler.view.viewport.offset_x,
                .y = handler.view.viewport.offset_y,
            };
        },
        0x0203 => {
            handler.view.fit = !handler.view.fit;
            handler.view.viewport.offset_x = 0;
            handler.view.viewport.offset_y = 0;
            if (!handler.view.fit) handler.view.viewport.scale = 1.0;
            if (handler.child_window) |window| _ = user32.InvalidateRect(window, null, 0);
        },
        0x0202 => handler.view.dragging = false,
        else => {},
    }
}

pub fn handleMouseMove(handler: *Handler, point: POINT) void {
    if (!handler.view.dragging) return;
    handler.view.viewport.offset_x = handler.view.drag_offset.x + point.x - handler.view.drag_start.x;
    handler.view.viewport.offset_y = handler.view.drag_offset.y + point.y - handler.view.drag_start.y;
    if (handler.child_window) |window| _ = user32.InvalidateRect(window, null, 0);
}

fn createSourceBitmap(destination: HDC, width: u32, height: u32, pixels: []const u8) ?HBITMAP {
    const byte_count = pixel_math.bgraBytes(width, height) catch return null;
    if (pixels.len < byte_count) return null;
    const size_image = std.math.cast(u32, byte_count) orelse return null;
    var info = abi.BITMAPINFO{
        .header = .{
            .width = @intCast(width),
            .height = -@as(i32, @intCast(height)),
            .size_image = size_image,
        },
    };
    var bits: [*]u8 = undefined;
    const dc = gdi32.CreateCompatibleDC(destination) orelse return null;
    defer _ = gdi32.DeleteDC(dc);
    const bitmap = gdi32.CreateDIBSection(destination, &info, 0, &bits, null, 0) orelse return null;
    @memcpy(bits[0..byte_count], pixels[0..byte_count]);
    return bitmap;
}

fn drawCheckerboard(bits: []u8, width: i32, height: i32) void {
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        var x: i32 = 0;
        while (x < width) : (x += 1) {
            const offset = @as(usize, @intCast(y)) * @as(usize, @intCast(width)) * 4 + @as(usize, @intCast(x)) * 4;
            const cell = ((@divTrunc(x, cell_size) + @divTrunc(y, cell_size)) & 1) == 0;
            const value: u8 = if (cell) 255 else 220;
            bits[offset] = value;
            bits[offset + 1] = value;
            bits[offset + 2] = value;
            bits[offset + 3] = 255;
        }
    }
}

pub fn createThumbnail(
    allocator: std.mem.Allocator,
    document: parser.Document,
    requested_size: u32,
) error{ OutOfMemory, DecodeFailed, InvalidImage }!HBITMAP {
    const size = thumbnailSize(document.width, document.height, requested_size);
    var output_width = size.width;
    var output_height = size.height;
    var pixels: []u8 = undefined;
    if (document.jpeg) |jpeg| {
        const decoded = try wic.decodeJpeg(allocator, jpeg);
        defer allocator.free(decoded.pixels);
        const jpeg_size = thumbnailSize(decoded.width, decoded.height, requested_size);
        output_width = jpeg_size.width;
        output_height = jpeg_size.height;
        pixels = try resizedBgra(allocator, decoded.pixels, decoded.width, decoded.height, jpeg_size);
    } else if (document.pixels) |source| {
        pixels = try resizedBgra(allocator, source, document.width, document.height, size);
    } else return error.DecodeFailed;
    defer allocator.free(pixels);
    return createThumbnailHandle(pixels, output_width, output_height) orelse error.DecodeFailed;
}

pub const ThumbnailSize = thumbnail_math.Size;

pub fn thumbnailSize(width: u32, height: u32, requested_size: u32) ThumbnailSize {
    return thumbnail_math.thumbnailSize(width, height, requested_size);
}

pub fn resizedBgra(allocator: std.mem.Allocator, source: []const u8, source_width: u32, source_height: u32, output: ThumbnailSize) error{ OutOfMemory, InvalidImage }![]u8 {
    return thumbnail_math.resizedBgra(allocator, source, source_width, source_height, output) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidImage, error.SizeOverflow, error.DecodeBudgetExceeded => return error.InvalidImage,
    };
}

fn createThumbnailHandle(pixels: []const u8, width: u32, height: u32) ?HBITMAP {
    const byte_count = pixel_math.bgraBytes(width, height) catch return null;
    if (pixels.len < byte_count) return null;
    const size_image = std.math.cast(u32, byte_count) orelse return null;
    var info = abi.BITMAPINFO{
        .header = .{
            .width = @intCast(width),
            .height = -@as(i32, @intCast(height)),
            .size_image = size_image,
        },
    };
    var bits: [*]u8 = undefined;
    const screen_dc = gdi32.CreateCompatibleDC(null) orelse return null;
    defer _ = gdi32.DeleteDC(screen_dc);
    const bitmap = gdi32.CreateDIBSection(screen_dc, &info, 0, &bits, null, 0) orelse return null;
    @memcpy(bits[0..byte_count], pixels[0..byte_count]);
    return bitmap;
}

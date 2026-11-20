const std = @import("std");
const abi = @import("com/abi.zig");
const config = @import("config.zig");

const HRESULT = abi.HRESULT;

const HKEY = *anyopaque;
const HKEY_CURRENT_USER: HKEY = @ptrFromInt(0x80000001);
const HKEY_LOCAL_MACHINE: HKEY = @ptrFromInt(0x80000002);

const KEY_QUERY_VALUE: u32 = 0x0001;
const KEY_SET_VALUE: u32 = 0x0002;
const KEY_WRITE: u32 = 0x20006;
const REG_OPTION_NON_VOLATILE: u32 = 0;
const REG_SZ: u32 = 1;
const REG_DWORD: u32 = 4;
const ERROR_FILE_NOT_FOUND: u32 = 2;
const ERROR_PATH_NOT_FOUND: u32 = 3;
const ERROR_ACCESS_DENIED: u32 = 5;
const TOKEN_QUERY: u32 = 0x0008;
const TOKEN_ELEVATION_CLASS: u32 = 20;
const SHCNE_ASSOCCHANGED: i32 = 0x08000000;
const SHCNF_IDLIST: u32 = 0;
const max_path_units: usize = 32768;

const classes_prefix = "Software\\Classes\\";
const preview_handlers_key = "Software\\Microsoft\\Windows\\CurrentVersion\\PreviewHandlers";

pub const Mode = enum { auto, user, machine };
pub const Root = enum { machine, user };

pub var module_handle: ?*anyopaque = null;

extern "advapi32" fn RegCreateKeyExW(
    key: HKEY,
    sub_key: [*:0]const u16,
    reserved: u32,
    class: ?[*:0]const u16,
    options: u32,
    desired: u32,
    security: ?*anyopaque,
    result: *HKEY,
    disposition: ?*u32,
) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegOpenKeyExW(
    key: HKEY,
    sub_key: [*:0]const u16,
    options: u32,
    desired: u32,
    result: *HKEY,
) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegSetValueExW(
    key: HKEY,
    name: ?[*:0]const u16,
    reserved: u32,
    kind: u32,
    data: [*]const u8,
    size: u32,
) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegQueryValueExW(
    key: HKEY,
    name: ?[*:0]const u16,
    reserved: ?*u32,
    kind: ?*u32,
    data: ?[*]u8,
    size: ?*u32,
) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegDeleteTreeW(key: HKEY, sub_key: [*:0]const u16) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegDeleteValueW(key: HKEY, name: [*:0]const u16) callconv(abi.WINAPI) u32;
extern "advapi32" fn RegCloseKey(key: HKEY) callconv(abi.WINAPI) u32;
extern "advapi32" fn OpenProcessToken(process: *anyopaque, desired: u32, token: *?*anyopaque) callconv(abi.WINAPI) i32;
extern "advapi32" fn GetTokenInformation(token: *anyopaque, info_class: u32, info: *anyopaque, length: u32, returned: *u32) callconv(abi.WINAPI) i32;
extern "kernel32" fn GetCurrentProcess() callconv(abi.WINAPI) *anyopaque;
extern "kernel32" fn CloseHandle(handle: *anyopaque) callconv(abi.WINAPI) i32;
extern "kernel32" fn GetModuleFileNameW(module: ?*anyopaque, buffer: [*]u16, size: u32) callconv(abi.WINAPI) u32;
extern "shell32" fn SHChangeNotify(event: i32, flags: u32, item1: ?*const anyopaque, item2: ?*const anyopaque) callconv(abi.WINAPI) void;

pub fn setModuleHandle(handle: ?*anyopaque) void {
    module_handle = handle;
}

fn wide(comptime text: []const u8) *const [text.len:0]u16 {
    const result = comptime blk: {
        var buffer: [text.len:0]u16 = undefined;
        for (text, 0..) |character, index| {
            buffer[index] = character;
        }
        buffer[text.len] = 0;
        break :blk buffer;
    };
    return &result;
}

/// UTF-16 registry path assembled from ASCII segments. Every key segment in
/// this project is ASCII, so rejecting non-ASCII characters keeps the builder
/// honest without a UTF-8 conversion routine.
const PathBuffer = struct {
    data: [max_path_units]u16 = undefined,
    length: usize = 0,

    fn init(comptime prefix: []const u8) error{PathTooLong}!PathBuffer {
        var buffer = PathBuffer{};
        try buffer.append(prefix);
        return buffer;
    }

    fn append(self: *PathBuffer, text: []const u8) error{PathTooLong}!void {
        if (self.length + text.len + 1 > self.data.len) return error.PathTooLong;
        for (text, 0..) |character, index| {
            if (character >= 0x80) return error.PathTooLong;
            self.data[self.length + index] = character;
        }
        self.length += text.len;
        self.data[self.length] = 0;
    }

    fn ptr(self: *PathBuffer) [*:0]const u16 {
        return @ptrCast(&self.data);
    }
};

fn classesPath(segments: []const []const u8) error{PathTooLong}!PathBuffer {
    var path = try PathBuffer.init(classes_prefix);
    for (segments, 0..) |segment, index| {
        if (index != 0) try path.append("\\");
        try path.append(segment);
    }
    return path;
}

const clsidSegments = [_][]const u8{ "CLSID", config.clsid_text };
const inprocSegments = [_][]const u8{ "CLSID", config.clsid_text, "InprocServer32" };

fn shellExSegments(extension: []const u8, interface_id: []const u8) [4][]const u8 {
    return .{ extension, "ShellEx", interface_id, "" };
}

fn systemFileAssociationSegments(extension: []const u8, interface_id: []const u8) [5][]const u8 {
    return .{ "SystemFileAssociations", extension, "ShellEx", interface_id, "" };
}

pub fn clsidRelativePath() []const u8 {
    return "CLSID\\" ++ config.clsid_text;
}

pub fn inprocServerRelativePath() []const u8 {
    return "CLSID\\" ++ config.clsid_text ++ "\\InprocServer32";
}

pub fn shellExRelativePath(allocator: std.mem.Allocator, extension: []const u8, interface_id: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "{s}\\ShellEx\\{s}", .{ extension, interface_id });
}

pub fn systemFileAssociationsRelativePath(allocator: std.mem.Allocator, extension: []const u8, interface_id: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "SystemFileAssociations\\{s}\\ShellEx\\{s}", .{ extension, interface_id });
}

fn createClassesKey(root: Root, path: *PathBuffer) ?HKEY {
    var key: HKEY = undefined;
    const status = RegCreateKeyExW(
        rootHandle(root),
        path.ptr(),
        0,
        null,
        REG_OPTION_NON_VOLATILE,
        KEY_WRITE,
        null,
        &key,
        null,
    );
    if (status != 0) return null;
    return key;
}

fn openClassesKey(root: Root, path: *PathBuffer, access: u32) ?HKEY {
    var key: HKEY = undefined;
    const status = RegOpenKeyExW(rootHandle(root), path.ptr(), 0, access, &key);
    if (status != 0) return null;
    return key;
}

fn rootHandle(root: Root) HKEY {
    return if (root == .machine) HKEY_LOCAL_MACHINE else HKEY_CURRENT_USER;
}

fn setString(key: HKEY, name: ?[*:0]const u16, value: []const u16) bool {
    if (value.len == 0) return false;
    const buffer = std.heap.page_allocator.alloc(u16, value.len + 1) catch return false;
    defer std.heap.page_allocator.free(buffer);
    @memcpy(buffer[0..value.len], value);
    buffer[value.len] = 0;
    const bytes = std.mem.sliceAsBytes(buffer);
    return RegSetValueExW(key, name, 0, REG_SZ, bytes.ptr, @intCast(bytes.len)) == 0;
}

fn setDword(key: HKEY, name: ?[*:0]const u16, value: u32) bool {
    var data = value;
    const bytes = std.mem.asBytes(&data);
    return RegSetValueExW(key, name, 0, REG_DWORD, bytes.ptr, @intCast(bytes.len)) == 0;
}

/// Writes the per-CLSID AppID association that points at the Prevhost surrogate
/// registered by Windows. This routine never creates or removes the shared
/// `HKCR\AppID` key, so uninstalling the handler cannot break other previewers.
fn registerClsid(root: Root, dll_path: []const u16) bool {
    var clsid_path = classesPath(&clsidSegments) catch return false;
    const key = createClassesKey(root, &clsid_path) orelse return false;
    defer _ = RegCloseKey(key);
    var ok = setString(key, null, wide(config.handler_name)[0..config.handler_name.len]);
    ok = setString(key, wide("AppID"), wide(config.appid_text)[0..config.appid_text.len]) and ok;
    ok = setDword(key, wide("DisableProcessIsolation"), 0) and ok;

    var inproc_path = classesPath(&inprocSegments) catch return false;
    const inproc = createClassesKey(root, &inproc_path) orelse return false;
    defer _ = RegCloseKey(inproc);
    ok = setString(inproc, null, dll_path) and ok;
    ok = setString(inproc, wide("ThreadingModel"), wide("Apartment")[0..9]) and ok;
    return ok;
}

fn registerShellEx(root: Root, segments: []const []const u8) bool {
    var path = classesPath(segments) catch return false;
    const key = createClassesKey(root, &path) orelse return false;
    defer _ = RegCloseKey(key);
    return setString(key, null, wide(config.clsid_text)[0..config.clsid_text.len]);
}

fn registerPreviewHandlerEntry(root: Root) bool {
    var key: HKEY = undefined;
    const status = RegCreateKeyExW(
        rootHandle(root),
        wide(preview_handlers_key),
        0,
        null,
        REG_OPTION_NON_VOLATILE,
        KEY_WRITE,
        null,
        &key,
        null,
    );
    if (status != 0) return false;
    defer _ = RegCloseKey(key);
    return setString(key, wide(config.clsid_text), wide(config.preview_handler_name)[0..config.preview_handler_name.len]);
}

pub fn isElevated() bool {
    var token: ?*anyopaque = null;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token) == 0) return false;
    defer _ = CloseHandle(token.?);
    var elevation: u32 = 0;
    var returned: u32 = 0;
    if (GetTokenInformation(token.?, TOKEN_ELEVATION_CLASS, &elevation, @sizeOf(u32), &returned) == 0) return false;
    return elevation != 0;
}

fn resolveRoots(mode: Mode) [2]?Root {
    return switch (mode) {
        .user => .{ .user, null },
        .machine => .{ .machine, null },
        .auto => if (isElevated()) .{ .machine, .user } else .{ .user, null },
    };
}

fn modulePath(buffer: []u16) ?[]const u16 {
    const length = GetModuleFileNameW(module_handle, buffer.ptr, @intCast(buffer.len));
    if (length == 0 or length >= buffer.len) return null;
    buffer[length] = 0;
    return buffer[0..length];
}

pub fn register(mode: Mode) HRESULT {
    const buffer = std.heap.page_allocator.alloc(u16, max_path_units) catch return abi.E_OUTOFMEMORY;
    defer std.heap.page_allocator.free(buffer);
    const dll_path = modulePath(buffer) orelse return hresultFromWin32(ERROR_FILE_NOT_FOUND);

    var last_status: u32 = ERROR_ACCESS_DENIED;
    for (resolveRoots(mode)) |maybe_root| {
        const root = maybe_root orelse continue;
        if (!registerClsid(root, dll_path)) {
            last_status = ERROR_ACCESS_DENIED;
            continue;
        }
        var ok = registerPreviewHandlerEntry(root);
        for (config.supported_extensions) |extension| {
            ok = registerShellEx(root, &shellExSegments(extension, config.thumbnail_iid_text)) and ok;
            ok = registerShellEx(root, &shellExSegments(extension, config.preview_iid_text)) and ok;
            ok = registerShellEx(root, &systemFileAssociationSegments(extension, config.thumbnail_iid_text)) and ok;
            ok = registerShellEx(root, &systemFileAssociationSegments(extension, config.preview_iid_text)) and ok;
        }
        if (!ok) {
            last_status = ERROR_ACCESS_DENIED;
            continue;
        }
        SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, null, null);
        return abi.S_OK;
    }
    return hresultFromWin32(last_status);
}

fn deleteValue(root: Root, segments: []const []const u8, name: [*:0]const u16) void {
    var path = classesPath(segments) catch return;
    const key = openClassesKey(root, &path, KEY_SET_VALUE) orelse return;
    defer _ = RegCloseKey(key);
    _ = RegDeleteValueW(key, name);
}

fn deleteClassesTree(root: Root, segments: []const []const u8) void {
    var path = classesPath(segments) catch return;
    const status = RegDeleteTreeW(rootHandle(root), path.ptr());
    if (status == ERROR_FILE_NOT_FOUND or status == ERROR_PATH_NOT_FOUND) return;
}

fn unregisterRoot(root: Root) void {
    for (config.supported_extensions) |extension| {
        deleteValue(root, &shellExSegments(extension, config.thumbnail_iid_text), wide(config.clsid_text));
        deleteValue(root, &shellExSegments(extension, config.preview_iid_text), wide(config.clsid_text));
        deleteValue(root, &systemFileAssociationSegments(extension, config.thumbnail_iid_text), wide(config.clsid_text));
        deleteValue(root, &systemFileAssociationSegments(extension, config.preview_iid_text), wide(config.clsid_text));
    }
    var key: HKEY = undefined;
    if (RegOpenKeyExW(rootHandle(root), wide(preview_handlers_key), 0, KEY_SET_VALUE, &key) == 0) {
        defer _ = RegCloseKey(key);
        _ = RegDeleteValueW(key, wide(config.clsid_text));
    }
    deleteClassesTree(root, &clsidSegments);
}

pub fn unregister(mode: Mode) HRESULT {
    switch (mode) {
        .auto => {
            unregisterRoot(.user);
            unregisterRoot(.machine);
        },
        .user => unregisterRoot(.user),
        .machine => unregisterRoot(.machine),
    }
    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, null, null);
    return abi.S_OK;
}

pub fn hresultFromWin32(status: u32) HRESULT {
    return @bitCast(@as(u32, 0x80070000) | (status & 0xffff));
}

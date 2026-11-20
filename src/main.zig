const abi = @import("com/abi.zig");
const config = @import("config.zig");
const handler_module = @import("com/handler.zig");
const registry = @import("registry.zig");
const state = @import("com/state.zig");
const std = @import("std");

const ClassFactory = abi.IClassFactory;

const factory_vtable = ClassFactory.VTable{
    .QueryInterface = factoryQueryInterface,
    .AddRef = factoryAddRef,
    .Release = factoryRelease,
    .CreateInstance = factoryCreateInstance,
    .LockServer = factoryLockServer,
};

var class_factory = ClassFactory{ .vtable = &factory_vtable };
var factory_refs = std.atomic.Value(u32).init(0);

fn factoryQueryInterface(factory: *ClassFactory, iid: *const abi.GUID, object: *?*anyopaque) callconv(abi.WINAPI) abi.HRESULT {
    object.* = null;
    if (!std.meta.eql(iid, &config.unknown_iid) and !std.meta.eql(iid, &config.class_factory_iid)) return abi.E_NOINTERFACE;
    object.* = @ptrCast(factory);
    _ = factoryAddRef(factory);
    return abi.S_OK;
}

fn factoryAddRef(_: *ClassFactory) callconv(abi.WINAPI) u32 {
    return factory_refs.fetchAdd(1, .monotonic) + 1;
}

fn factoryRelease(_: *ClassFactory) callconv(abi.WINAPI) u32 {
    const previous = factory_refs.fetchSub(1, .acq_rel);
    if (previous == 0) {
        _ = factory_refs.fetchAdd(1, .monotonic);
        return 0;
    }
    return previous - 1;
}

fn factoryCreateInstance(_: *ClassFactory, outer: ?*abi.IUnknown, iid: *const abi.GUID, object: *?*anyopaque) callconv(abi.WINAPI) abi.HRESULT {
    object.* = null;
    if (outer != null) return abi.CLASS_E_NOAGGREGATION;
    const instance = handler_module.Handler.create(std.heap.page_allocator) catch return abi.E_OUTOFMEMORY;
    const result = instance.initialize.vtable.QueryInterface(&instance.initialize, iid, object);
    _ = instance.initialize.vtable.Release(&instance.initialize);
    return result;
}

fn factoryLockServer(_: *ClassFactory, lock: i32) callconv(abi.WINAPI) abi.HRESULT {
    if (lock != 0) {
        _ = state.server_lock_count.fetchAdd(1, .monotonic);
        return abi.S_OK;
    }
    const previous = state.server_lock_count.fetchSub(1, .monotonic);
    if (previous == 0) {
        _ = state.server_lock_count.fetchAdd(1, .monotonic);
        return abi.E_INVALIDARG;
    }
    return abi.S_OK;
}

pub export fn DllMain(instance: ?*anyopaque, reason: u32, _: ?*anyopaque) callconv(abi.WINAPI) i32 {
    if (reason == 1) {
        registry.setModuleHandle(instance);
        if (instance) |handle| _ = DisableThreadLibraryCalls(handle);
    }
    return 1;
}

extern "kernel32" fn DisableThreadLibraryCalls(module: *anyopaque) callconv(abi.WINAPI) i32;

pub export fn DllGetClassObject(class_id: *const abi.GUID, iid: *const abi.GUID, object: *?*anyopaque) callconv(abi.WINAPI) abi.HRESULT {
    object.* = null;
    if (!std.meta.eql(class_id, &config.extension_clsid)) return @bitCast(@as(u32, 0x80040111));
    return factoryQueryInterface(&class_factory, iid, object);
}

pub export fn DllCanUnloadNow() callconv(abi.WINAPI) abi.HRESULT {
    if (state.object_count.load(.monotonic) == 0 and state.server_lock_count.load(.monotonic) == 0 and factory_refs.load(.monotonic) == 0) return abi.S_OK;
    return abi.S_FALSE;
}

pub export fn DllRegisterServer() callconv(abi.WINAPI) abi.HRESULT {
    return registry.register(.auto);
}

pub export fn DllUnregisterServer() callconv(abi.WINAPI) abi.HRESULT {
    return registry.unregister(.auto);
}

pub export fn DllInstall(install: i32, command_line: ?[*:0]const u16) callconv(abi.WINAPI) abi.HRESULT {
    const mode = installMode(command_line) orelse return abi.E_INVALIDARG;
    return if (install != 0) registry.register(mode) else registry.unregister(mode);
}

fn installMode(command_line: ?[*:0]const u16) ?registry.Mode {
    const raw = command_line orelse return .user;
    var text = std.mem.span(raw);
    while (text.len != 0 and (text[0] == ' ' or text[0] == '\t' or text[0] == '"')) text = text[1..];
    while (text.len != 0) {
        const last = text[text.len - 1];
        if (last != ' ' and last != '\t' and last != '"') break;
        text = text[0 .. text.len - 1 :0];
    }
    if (eqlAsciiIgnoreCase16(text, "user")) return .user;
    if (eqlAsciiIgnoreCase16(text, "machine")) return .machine;
    if (eqlAsciiIgnoreCase16(text, "auto")) return .auto;
    return null;
}

fn eqlAsciiIgnoreCase16(text: []const u16, expected: []const u8) bool {
    if (text.len != expected.len) return false;
    for (text, expected) |actual_unit, expected_byte| {
        if (actual_unit > 0x7f) return false;
        const actual = std.ascii.toLower(@intCast(actual_unit));
        if (actual != std.ascii.toLower(expected_byte)) return false;
    }
    return true;
}

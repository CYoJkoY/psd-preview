const std = @import("std");
const parser = @import("psd/parser.zig");
const packbits = parser.packbits_helpers;
const color = parser.color_helpers;

test {
    _ = @import("render/thumbnail.zig");
}

fn appendInt(comptime T: type, list: *std.ArrayList(u8), value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .big);
    try list.appendSlice(std.testing.allocator, &bytes);
}

fn appendFloat32(list: *std.ArrayList(u8), value: f32) !void {
    try appendInt(u32, list, @bitCast(value));
}

fn header(list: *std.ArrayList(u8), version: u16, channels: u16, height: u32, width: u32, depth: u16, mode: u16) !void {
    try list.appendSlice(std.testing.allocator, "8BPS");
    try appendInt(u16, list, version);
    try list.appendSlice(std.testing.allocator, &[_]u8{ 0, 0, 0, 0, 0, 0 });
    try appendInt(u16, list, channels);
    try appendInt(u32, list, height);
    try appendInt(u32, list, width);
    try appendInt(u16, list, depth);
    try appendInt(u16, list, mode);
}

fn finishSections(list: *std.ArrayList(u8), version: u16, resources: []const u8) !void {
    try appendInt(u32, list, 0);
    try appendInt(u32, list, @intCast(resources.len));
    try list.appendSlice(std.testing.allocator, resources);
    if (version == 1) {
        try appendInt(u32, list, 0);
    } else {
        try appendInt(u64, list, 0);
    }
}

test "raw RGB composite becomes premultiplied BGRA" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 3, 2, 2, 8, 3);
    try finishSections(&psd, 1, &.{});
    try appendInt(u16, &psd, 0);
    try psd.appendSlice(std.testing.allocator, &.{ 255, 0, 10, 20 });
    try psd.appendSlice(std.testing.allocator, &.{ 0, 255, 30, 40 });
    try psd.appendSlice(std.testing.allocator, &.{ 0, 0, 255, 255 });
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqual(parser.Source.composite, document.source);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255, 0, 255, 0, 255, 255, 30, 10, 255, 255, 40, 20, 255 }, document.pixels.?);
}

test "embedded JPEG resource is selected before composite decode" {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(std.testing.allocator);
    try appendInt(u32, &payload, 1);
    try appendInt(u32, &payload, 0);
    try appendInt(u32, &payload, 0);
    try appendInt(u32, &payload, 0);
    try appendInt(u32, &payload, 0);
    try appendInt(u32, &payload, 6);
    try appendInt(u16, &payload, 24);
    try appendInt(u16, &payload, 1);
    try payload.appendSlice(std.testing.allocator, "JPEG!!");
    var resources = std.ArrayList(u8).empty;
    defer resources.deinit(std.testing.allocator);
    try resources.appendSlice(std.testing.allocator, "8BIM");
    try appendInt(u16, &resources, 0x040c);
    try resources.appendSlice(std.testing.allocator, &.{ 0, 0 });
    try appendInt(u32, &resources, @intCast(payload.items.len));
    try resources.appendSlice(std.testing.allocator, payload.items);
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 3, 10, 20, 8, 3);
    try finishSections(&psd, 1, resources.items);
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqual(parser.Source.embedded_jpeg, document.source);
    try std.testing.expectEqualSlices(u8, "JPEG!!", document.jpeg.?);
    try std.testing.expectEqual(@as(u32, 20), document.width);
}

test "PSB packbits rows decode with 32-bit row table" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 2, 3, 1, 2, 8, 3);
    try finishSections(&psd, 2, &.{});
    try appendInt(u16, &psd, 1);
    for (0..3) |_| {
        try appendInt(u32, &psd, 3);
    }
    for (0..3) |_| {
        try psd.appendSlice(std.testing.allocator, &.{ 1, 0, 255 });
    }
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 255, 255, 255, 255, 255 }, document.pixels.?);
}

test "CMYK uses inverted ink channels" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 4, 1, 1, 8, 4);
    try finishSections(&psd, 1, &.{});
    try appendInt(u16, &psd, 0);
    try psd.appendSlice(std.testing.allocator, &.{ 255, 255, 255, 255 });
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 255, 255, 255, 255 }, document.pixels.?);
}

test "grayscale composite uses channel zero and channel one alpha" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 2, 1, 2, 8, 1);
    try finishSections(&psd, 1, &.{});
    try appendInt(u16, &psd, 0);
    try psd.appendSlice(std.testing.allocator, &.{ 200, 100 });
    try psd.appendSlice(std.testing.allocator, &.{ 128, 0 });
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 100, 100, 100, 128, 0, 0, 0, 0 }, document.pixels.?);
}

test "truncated and oversized documents fail closed" {
    try std.testing.expectError(error.InvalidSignature, parser.parse(std.testing.allocator, "nope"));
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 3, 1, 1, 8, 3);
    try std.testing.expectError(error.Truncated, parser.parse(std.testing.allocator, psd.items));
}

test "packbits rejects output overrun" {
    var output: [2]u8 = undefined;
    try std.testing.expectError(error.OutputOverflow, packbits.decodeRow(&.{ 2, 1, 2, 3 }, &output));
}

test "unsupported color modes fail closed" {
    for ([_]u16{ 7, 8, 9 }) |mode| {
        var psd = std.ArrayList(u8).empty;
        defer psd.deinit(std.testing.allocator);
        try header(&psd, 1, 4, 1, 1, 8, mode);
        try std.testing.expectError(error.UnsupportedColorMode, parser.parse(std.testing.allocator, psd.items));
    }
}

test "RGB and CMYK require their color channels" {
    var rgb = std.ArrayList(u8).empty;
    defer rgb.deinit(std.testing.allocator);
    try header(&rgb, 1, 2, 1, 1, 8, 3);
    try std.testing.expectError(error.InvalidChannelCount, parser.parse(std.testing.allocator, rgb.items));

    var cmyk = std.ArrayList(u8).empty;
    defer cmyk.deinit(std.testing.allocator);
    try header(&cmyk, 1, 3, 1, 1, 8, 4);
    try std.testing.expectError(error.InvalidChannelCount, parser.parse(std.testing.allocator, cmyk.items));
}

test "32-bit float alpha is sampled linearly" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 4, 1, 1, 32, 3);
    try finishSections(&psd, 1, &.{});
    try appendInt(u16, &psd, 0);
    try appendFloat32(&psd, 1.0);
    try appendFloat32(&psd, 0.0);
    try appendFloat32(&psd, 0.0);
    try appendFloat32(&psd, 0.5);
    var document = try parser.parse(std.testing.allocator, psd.items);
    defer document.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 128, 128 }, document.pixels.?);
}

test "malformed resource payload is rejected" {
    var resources = std.ArrayList(u8).empty;
    defer resources.deinit(std.testing.allocator);
    try resources.appendSlice(std.testing.allocator, "8BIM");
    try appendInt(u16, &resources, 0x040c);
    try resources.appendSlice(std.testing.allocator, &.{ 10, 1, 2, 3, 4 });
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 1, 3, 1, 1, 8, 3);
    try finishSections(&psd, 1, resources.items);
    try std.testing.expectError(error.CorruptResource, parser.parse(std.testing.allocator, psd.items));
}

test "truncated PSB layer section fails closed" {
    var psd = std.ArrayList(u8).empty;
    defer psd.deinit(std.testing.allocator);
    try header(&psd, 2, 3, 1, 1, 8, 3);
    try appendInt(u32, &psd, 0);
    try appendInt(u32, &psd, 0);
    try appendInt(u64, &psd, 4096);
    try std.testing.expectError(error.Truncated, parser.parse(std.testing.allocator, psd.items));

    var overflow = std.ArrayList(u8).empty;
    defer overflow.deinit(std.testing.allocator);
    try header(&overflow, 2, 3, 1, 1, 8, 3);
    try appendInt(u32, &overflow, 0);
    try appendInt(u32, &overflow, 0);
    try appendInt(u64, &overflow, std.math.maxInt(u64));
    try std.testing.expectError(error.Truncated, parser.parse(std.testing.allocator, overflow.items));
}

test "premultiply rounds correctly" {
    try std.testing.expectEqual(@as(u8, 1), color.premultiply(1, 128));
    try std.testing.expectEqual(@as(u8, 255), color.premultiply(255, 255));
}

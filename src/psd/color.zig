const std = @import("std");

pub fn premultiply(channel: u8, alpha: u8) u8 {
    return @intCast((@as(u16, channel) * alpha + 127) / 255);
}

pub fn sample8(data: []const u8, index: usize) u8 {
    return data[index];
}

pub fn sample16(data: []const u8, index: usize) u8 {
    const offset = index * 2;
    return data[offset];
}

pub fn sample32(data: []const u8, index: usize) u8 {
    const offset = index * 4;
    var bytes: [4]u8 = undefined;
    @memcpy(&bytes, data[offset .. offset + 4]);
    const value = @as(f32, @bitCast(std.mem.readInt(u32, &bytes, .big)));
    const clamped = std.math.clamp(value, 0.0, 1.0);
    return @intFromFloat(std.math.pow(f32, clamped, 1.0 / 2.2) * 255.0 + 0.5);
}

/// PSD 32-bit alpha is linear coverage, not sRGB-encoded color. Applying the
/// color gamma curve to it would make soft edges too opaque.
pub fn sample32Linear(data: []const u8, index: usize) u8 {
    const offset = index * 4;
    var bytes: [4]u8 = undefined;
    @memcpy(&bytes, data[offset .. offset + 4]);
    const value = @as(f32, @bitCast(std.mem.readInt(u32, &bytes, .big)));
    const clamped = std.math.clamp(value, 0.0, 1.0);
    return @intFromFloat(clamped * 255.0 + 0.5);
}

pub fn cmykToRgb(c: u8, m: u8, y: u8, k: u8) [3]u8 {
    return .{
        @intCast((@as(u16, c) * k + 127) / 255),
        @intCast((@as(u16, m) * k + 127) / 255),
        @intCast((@as(u16, y) * k + 127) / 255),
    };
}

test "color helpers use PSD conventions" {
    try std.testing.expectEqual(@as(u8, 128), premultiply(255, 128));
    try std.testing.expectEqual([3]u8{ 0, 128, 255 }, cmykToRgb(0, 128, 255, 255));
    var linear_alpha: [4]u8 = undefined;
    std.mem.writeInt(u32, &linear_alpha, @bitCast(@as(f32, 0.5)), .big);
    try std.testing.expectEqual(@as(u8, 128), sample32Linear(&linear_alpha, 0));
}

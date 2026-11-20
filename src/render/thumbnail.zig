const std = @import("std");
const config = @import("../config.zig");
const pixels = @import("pixels.zig");

pub const Size = struct {
    width: u32,
    height: u32,
};

/// Calculates an aspect-preserving thumbnail with integer arithmetic. The
/// longest side is capped at both the host request and our hard limit, so a
/// very large request still produces a bounded allocation.
pub fn thumbnailSize(width: u32, height: u32, requested_size: u32) Size {
    if (width == 0 or height == 0) return .{ .width = 1, .height = 1 };
    const requested = @max(1, @min(requested_size, config.max_thumbnail_dimension));
    const longest = @max(width, height);
    if (longest <= requested) return .{ .width = width, .height = height };

    const scaled_width = std.math.mul(u64, width, requested) catch 0;
    const scaled_height = std.math.mul(u64, height, requested) catch 0;
    const longest_u64: u64 = longest;
    const rounded_width = (scaled_width + longest_u64 / 2) / longest_u64;
    const rounded_height = (scaled_height + longest_u64 / 2) / longest_u64;
    const output_width = @max(1, @min(requested, @as(u32, @intCast(@min(rounded_width, std.math.maxInt(u32))))));
    const output_height = @max(1, @min(requested, @as(u32, @intCast(@min(rounded_height, std.math.maxInt(u32))))));
    return .{ .width = output_width, .height = output_height };
}

/// Nearest-neighbour resize into premultiplied BGRA. The source must contain a
/// complete image; a short buffer is treated as malformed input instead of
/// being padded and over-read.
pub fn resizedBgra(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_width: u32,
    source_height: u32,
    output: Size,
) error{ OutOfMemory, InvalidImage, SizeOverflow, DecodeBudgetExceeded }![]u8 {
    const source_bytes = pixels.bgraBytes(source_width, source_height) catch |err| switch (err) {
        error.InvalidDimensions, error.SizeOverflow, error.ApiSizeExceeded, error.DecodeBudgetExceeded => return error.InvalidImage,
    };
    const output_bytes = pixels.bgraBytes(output.width, output.height) catch |err| switch (err) {
        error.InvalidDimensions, error.ApiSizeExceeded => return error.InvalidImage,
        error.SizeOverflow => return error.SizeOverflow,
        error.DecodeBudgetExceeded => return error.DecodeBudgetExceeded,
    };
    if (source.len < source_bytes) return error.InvalidImage;

    const source_row_width: usize = source_width;
    const output_width: usize = output.width;
    const output_height: usize = output.height;
    const result = try allocator.alloc(u8, output_bytes);
    var y: usize = 0;
    while (y < output_height) : (y += 1) {
        const source_y = @min(@as(usize, source_height) - 1, y * source_height / output_height);
        var x: usize = 0;
        while (x < output_width) : (x += 1) {
            const source_x = @min(source_row_width - 1, x * source_width / output_width);
            const source_offset = (source_y * source_row_width + source_x) * 4;
            const output_offset = (y * output_width + x) * 4;
            @memcpy(result[output_offset .. output_offset + 4], source[source_offset .. source_offset + 4]);
        }
    }
    return result;
}

test "thumbnail size preserves aspect ratio and clamps requests" {
    try std.testing.expectEqual(Size{ .width = 50, .height = 25 }, thumbnailSize(200, 100, 50));
    try std.testing.expectEqual(Size{ .width = 1024, .height = 51 }, thumbnailSize(2000, 100, 999999));
    try std.testing.expectEqual(Size{ .width = 1, .height = 1 }, thumbnailSize(0, 100, 64));
    try std.testing.expectEqual(Size{ .width = 1, .height = 1 }, thumbnailSize(100, 20, 0));
}

test "resized BGRA rejects short sources and downsamples" {
    const source = [_]u8{
        10, 20, 30, 255, 40,  50,  60,  255,
        70, 80, 90, 255, 100, 110, 120, 255,
    };
    const output = try resizedBgra(std.testing.allocator, &source, 2, 2, .{ .width = 1, .height = 1 });
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30, 255 }, output);
    try std.testing.expectError(error.InvalidImage, resizedBgra(std.testing.allocator, source[0..15], 2, 2, .{ .width = 1, .height = 1 }));
}

test "pixel helper rejects overflowing dimensions" {
    try std.testing.expectError(error.InvalidDimensions, pixels.bgraBytes(0, 10));
    try std.testing.expectError(error.InvalidDimensions, pixels.bgraBytes(std.math.maxInt(u32), 2));
    try std.testing.expectEqual(@as(u32, 16), try pixels.bgraStride(4));
    try std.testing.expectError(error.InvalidDimensions, pixels.validateDimensions(0, 1, config.max_image_dimension));
}

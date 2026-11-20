const std = @import("std");
const color = @import("color.zig");
const packbits = @import("packbits.zig");
const config = @import("../config.zig");

pub const color_helpers = color;
pub const packbits_helpers = packbits;

pub const Error = error{
    OutOfMemory,
    InvalidSignature,
    InvalidVersion,
    InvalidDimensions,
    UnsupportedColorMode,
    UnsupportedDepth,
    InvalidChannelCount,
    UnsupportedCompression,
    Truncated,
    CorruptResource,
    CorruptPackBits,
    SizeOverflow,
    DecodeBudgetExceeded,
};

pub const Source = enum { embedded_jpeg, composite };

pub const Document = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    channels: u16,
    depth: u16,
    color_mode: u16,
    source: Source,
    jpeg: ?[]const u8 = null,
    pixels: ?[]u8 = null,

    pub fn deinit(self: *Document) void {
        if (self.pixels) |pixels| self.allocator.free(pixels);
        self.* = undefined;
    }
};

const Reader = struct {
    data: []const u8,
    offset: usize = 0,

    fn remaining(self: *const Reader) usize {
        return self.data.len - self.offset;
    }

    fn take(self: *Reader, count: usize) Error![]const u8 {
        if (count > self.remaining()) return error.Truncated;
        const result = self.data[self.offset .. self.offset + count];
        self.offset += count;
        return result;
    }

    fn readU16(self: *Reader) Error!u16 {
        var bytes: [2]u8 = undefined;
        @memcpy(&bytes, try self.take(2));
        return std.mem.readInt(u16, &bytes, .big);
    }

    fn readU32(self: *Reader) Error!u32 {
        var bytes: [4]u8 = undefined;
        @memcpy(&bytes, try self.take(4));
        return std.mem.readInt(u32, &bytes, .big);
    }

    fn readU64(self: *Reader) Error!u64 {
        var bytes: [8]u8 = undefined;
        @memcpy(&bytes, try self.take(8));
        return std.mem.readInt(u64, &bytes, .big);
    }

    fn skip(self: *Reader, count: usize) Error!void {
        _ = try self.take(count);
    }
};

pub fn parse(allocator: std.mem.Allocator, data: []const u8) Error!Document {
    var reader = Reader{ .data = data };
    if (!std.mem.eql(u8, try reader.take(4), "8BPS")) return error.InvalidSignature;
    const version = try reader.readU16();
    if (version != 1 and version != 2) return error.InvalidVersion;
    try reader.skip(6);
    const channels = try reader.readU16();
    const height = try reader.readU32();
    const width = try reader.readU32();
    const depth = try reader.readU16();
    const mode = try reader.readU16();
    if (width == 0 or height == 0 or width > config.max_image_dimension or height > config.max_image_dimension or channels == 0 or channels > 56) return error.InvalidDimensions;
    if (depth != 1 and depth != 8 and depth != 16 and depth != 32) return error.UnsupportedDepth;
    const minimum_channels: u16 = switch (mode) {
        0, 1, 2 => 1,
        3 => 3,
        4 => 4,
        // Duotone, Lab and multichannel composites do not share the RGB or
        // grayscale channel layout this renderer implements.
        else => return error.UnsupportedColorMode,
    };
    if (channels < minimum_channels) return error.InvalidChannelCount;

    const color_data_length = try reader.readU32();
    const color_data = try reader.take(@intCast(color_data_length));
    var palette: ?[]const u8 = null;
    if (mode == 2) {
        if (color_data.len < 768) return error.Truncated;
        palette = color_data[0..768];
    }

    const resource_length = try reader.readU32();
    const resources = try reader.take(@intCast(resource_length));
    var embedded_jpeg: ?[]const u8 = null;
    scanResources(resources, &embedded_jpeg) catch return error.CorruptResource;
    if (embedded_jpeg) |jpeg| {
        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .channels = channels,
            .depth = depth,
            .color_mode = mode,
            .source = .embedded_jpeg,
            .jpeg = jpeg,
        };
    }

    const layer_length = if (version == 1)
        @as(usize, @intCast(try reader.readU32()))
    else
        std.math.cast(usize, try reader.readU64()) orelse return error.SizeOverflow;
    try reader.skip(layer_length);
    const compression = try reader.readU16();
    if (compression != 0 and compression != 1) return error.UnsupportedCompression;
    const pixels = try decodeComposite(allocator, &reader, width, height, channels, depth, mode, palette, compression, version);
    return .{
        .allocator = allocator,
        .width = width,
        .height = height,
        .channels = channels,
        .depth = depth,
        .color_mode = mode,
        .source = .composite,
        .pixels = pixels,
    };
}

fn scanResources(data: []const u8, embedded_jpeg: *?[]const u8) !void {
    var reader = Reader{ .data = data };
    while (reader.remaining() != 0) {
        if (reader.remaining() < 12 or !std.mem.eql(u8, try reader.take(4), "8BIM")) return error.CorruptResource;
        const id = try reader.readU16();
        const name_length = @as(usize, (try reader.take(1))[0]);
        try reader.skip(name_length);
        if (((name_length + 1) & 1) != 0) try reader.skip(1);
        const size = @as(usize, @intCast(try reader.readU32()));
        const payload = try reader.take(size);
        if ((size & 1) != 0) try reader.skip(1);
        if (id == 0x040c and payload.len >= 28) {
            const format = readBigU32(payload[0..4]);
            const compressed_size = @as(usize, @intCast(readBigU32(payload[20..24])));
            if (format == 1 and compressed_size <= payload.len - 28 and compressed_size != 0) {
                embedded_jpeg.* = payload[28 .. 28 + compressed_size];
            }
        }
    }
}

fn readBigU32(bytes: []const u8) u32 {
    var fixed: [4]u8 = undefined;
    @memcpy(&fixed, bytes[0..4]);
    return std.mem.readInt(u32, &fixed, .big);
}

fn mapSizeError(err: anyerror) Error {
    return switch (err) {
        error.SizeOverflow => error.SizeOverflow,
        error.DecodeBudgetExceeded => error.DecodeBudgetExceeded,
        else => error.SizeOverflow,
    };
}

fn decodeComposite(
    allocator: std.mem.Allocator,
    reader: *Reader,
    width: u32,
    height: u32,
    channels: u16,
    depth: u16,
    mode: u16,
    palette: ?[]const u8,
    compression: u16,
    version: u16,
) Error![]u8 {
    const width_usize: usize = @intCast(width);
    const height_usize: usize = @intCast(height);
    const plane_samples = std.math.mul(usize, width_usize, height_usize) catch return error.SizeOverflow;
    if (plane_samples > config.max_working_bytes) return error.DecodeBudgetExceeded;
    const channel_count: usize = @intCast(channels);
    const row_bytes = if (depth == 1) (width_usize + 7) / 8 else std.math.mul(usize, width_usize, depth / 8) catch return error.SizeOverflow;
    const plane_bytes = std.math.mul(usize, row_bytes, height_usize) catch return error.SizeOverflow;
    const all_plane_bytes = std.math.mul(usize, plane_bytes, channel_count) catch return error.SizeOverflow;
    if (all_plane_bytes > config.max_working_bytes) return error.DecodeBudgetExceeded;
    var planes = try allocator.alloc(u8, all_plane_bytes);
    defer allocator.free(planes);
    @memset(planes, 0);
    if (compression == 0) {
        const raw = try reader.take(all_plane_bytes);
        @memcpy(planes, raw);
    } else {
        const row_count = std.math.mul(usize, height_usize, channel_count) catch return error.SizeOverflow;
        const row_entry_bytes: usize = if (version == 1) 2 else 4;
        const table_bytes = std.math.mul(usize, row_count, row_entry_bytes) catch return error.SizeOverflow;
        const table = try reader.take(table_bytes);
        var table_reader = Reader{ .data = table };
        var channel: usize = 0;
        while (channel < channel_count) : (channel += 1) {
            var row: usize = 0;
            while (row < height_usize) : (row += 1) {
                const encoded_size = if (version == 1) @as(usize, try table_reader.readU16()) else @as(usize, @intCast(try table_reader.readU32()));
                const encoded = try reader.take(encoded_size);
                const start = channel * plane_bytes + row * row_bytes;
                packbits.decodeRow(encoded, planes[start .. start + row_bytes]) catch return error.CorruptPackBits;
            }
        }
    }
    const result_size = std.math.mul(usize, plane_samples, 4) catch return error.SizeOverflow;
    const working_bytes = std.math.add(usize, all_plane_bytes, result_size) catch return error.SizeOverflow;
    if (working_bytes > config.max_working_bytes) return error.DecodeBudgetExceeded;
    var result = try allocator.alloc(u8, result_size);
    errdefer allocator.free(result);
    var pixel: usize = 0;
    while (pixel < plane_samples) : (pixel += 1) {
        const red_raw = readSample(planes, 0, pixel, depth, plane_bytes);
        var red = red_raw;
        var green = red_raw;
        var blue = red_raw;
        var alpha: u8 = 255;
        if (mode == 2) {
            const lut = palette orelse return error.Truncated;
            const palette_index: usize = red_raw;
            red = lut[palette_index];
            green = lut[256 + palette_index];
            blue = lut[512 + palette_index];
        } else if (mode == 4 and channel_count >= 4) {
            const rgb = color.cmykToRgb(
                readSample(planes, 0, pixel, depth, plane_bytes),
                readSample(planes, 1, pixel, depth, plane_bytes),
                readSample(planes, 2, pixel, depth, plane_bytes),
                readSample(planes, 3, pixel, depth, plane_bytes),
            );
            red = rgb[0];
            green = rgb[1];
            blue = rgb[2];
        } else if (mode == 3 and channel_count >= 3) {
            red = readSample(planes, 0, pixel, depth, plane_bytes);
            green = readSample(planes, 1, pixel, depth, plane_bytes);
            blue = readSample(planes, 2, pixel, depth, plane_bytes);
        } else if (mode == 1) {
            red = readSample(planes, 0, pixel, depth, plane_bytes);
            green = red;
            blue = red;
        }
        if ((mode == 3 and channel_count >= 4) or (mode == 1 and channel_count >= 2) or (mode == 4 and channel_count >= 5)) {
            alpha = readSampleLinear(planes, if (mode == 1) 1 else if (mode == 3) 3 else 4, pixel, depth, plane_bytes);
        }
        const offset = pixel * 4;
        result[offset] = color.premultiply(blue, alpha);
        result[offset + 1] = color.premultiply(green, alpha);
        result[offset + 2] = color.premultiply(red, alpha);
        result[offset + 3] = alpha;
    }
    return result;
}

fn readSample(planes: []const u8, channel: usize, index: usize, depth: u16, plane_bytes: usize) u8 {
    const plane = planes[channel * plane_bytes .. (channel + 1) * plane_bytes];
    if (depth == 1) {
        return if ((plane[index / 8] & (@as(u8, 0x80) >> @intCast(index & 7))) != 0) 255 else 0;
    }
    if (depth == 8) return color.sample8(plane, index);
    if (depth == 16) return color.sample16(plane, index);
    return color.sample32(plane, index);
}

fn readSampleLinear(planes: []const u8, channel: usize, index: usize, depth: u16, plane_bytes: usize) u8 {
    if (depth != 32) return readSample(planes, channel, index, depth, plane_bytes);
    const plane = planes[channel * plane_bytes .. (channel + 1) * plane_bytes];
    return color.sample32Linear(plane, index);
}

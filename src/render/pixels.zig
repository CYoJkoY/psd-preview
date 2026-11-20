const std = @import("std");
const config = @import("../config.zig");

pub const Error = error{
    InvalidDimensions,
    SizeOverflow,
    DecodeBudgetExceeded,
    ApiSizeExceeded,
};

/// Returns the byte count of an uncompressed 32-bpp BGRA image after checking
/// every multiplication and the decoder working-memory budget.
pub fn bgraBytes(width: u32, height: u32) Error!usize {
    try validateDimensions(width, height, config.max_image_dimension);
    const pixels = std.math.mul(usize, @as(usize, width), @as(usize, height)) catch return error.SizeOverflow;
    return checkedBytes(std.math.mul(usize, pixels, 4) catch return error.SizeOverflow);
}

/// Returns the stride of a 32-bpp BGRA row and guarantees it fits the `u32`
/// fields used by WIC and Win32.
pub fn bgraStride(width: u32) Error!u32 {
    if (width == 0 or width > config.max_image_dimension) return error.InvalidDimensions;
    const stride = std.math.mul(usize, @as(usize, width), 4) catch return error.SizeOverflow;
    return std.math.cast(u32, stride) orelse error.ApiSizeExceeded;
}

pub fn validateDimensions(width: u32, height: u32, max_dimension: u32) Error!void {
    if (width == 0 or height == 0 or width > max_dimension or height > max_dimension) return error.InvalidDimensions;
}

pub fn checkedBytes(bytes: usize) Error!usize {
    if (bytes > config.max_working_bytes) return error.DecodeBudgetExceeded;
    return bytes;
}

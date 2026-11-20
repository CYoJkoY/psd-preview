const std = @import("std");
const abi = @import("abi.zig");
const config = @import("../config.zig");

pub const Error = error{ OutOfMemory, ReadFailed, SeekFailed, TooLarge };

const STREAM_SEEK_SET: u32 = 0;

/// Rewinds the stream before reading so a handler can retry decoding against a
/// stream the host already consumed, then copies the remaining bytes in bounded
/// chunks. The caller owns the returned buffer.
pub fn readAll(allocator: std.mem.Allocator, stream: *abi.IStream) Error![]u8 {
    var position: u64 = 0;
    if (stream.vtable.Seek(stream, 0, STREAM_SEEK_SET, &position) < 0) return error.SeekFailed;

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);
    var chunk: [65536]u8 = undefined;
    while (true) {
        var bytes_read: u32 = 0;
        const status = stream.vtable.Read(stream, &chunk, chunk.len, &bytes_read);
        if (status < 0) return error.ReadFailed;
        if (bytes_read > chunk.len) return error.ReadFailed;
        if (bytes_read == 0) break;
        if (bytes_read > config.max_decode_bytes - result.items.len) return error.TooLarge;
        try result.appendSlice(allocator, chunk[0..bytes_read]);
    }
    return result.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

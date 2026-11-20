const std = @import("std");

pub const Error = error{
    UnexpectedEnd,
    OutputOverflow,
    InvalidRow,
};

pub fn decodeRow(input: []const u8, output: []u8) Error!void {
    var source_index: usize = 0;
    var output_index: usize = 0;
    while (output_index < output.len) {
        if (source_index >= input.len) return error.UnexpectedEnd;
        const control: i8 = @bitCast(input[source_index]);
        source_index += 1;
        if (control >= 0) {
            const count = @as(usize, @intCast(control)) + 1;
            if (count > input.len - source_index or count > output.len - output_index) return error.OutputOverflow;
            @memcpy(output[output_index .. output_index + count], input[source_index .. source_index + count]);
            source_index += count;
            output_index += count;
        } else if (control != -128) {
            if (source_index >= input.len) return error.UnexpectedEnd;
            const count = @as(usize, @intCast(1 - @as(i16, control)));
            if (count > output.len - output_index) return error.OutputOverflow;
            @memset(output[output_index .. output_index + count], input[source_index]);
            source_index += 1;
            output_index += count;
        }
    }
}

test "packbits decodes literal and repeat runs" {
    var output: [6]u8 = undefined;
    try decodeRow(&.{ 2, 'a', 'b', 'c', 0xfe, 'x' }, &output);
    try std.testing.expectEqualSlices(u8, "abcxxx", &output);
}

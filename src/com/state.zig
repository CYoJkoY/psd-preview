const std = @import("std");

pub var object_count = std.atomic.Value(u32).init(0);
pub var server_lock_count = std.atomic.Value(u32).init(0);

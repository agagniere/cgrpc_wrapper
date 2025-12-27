const std = @import("std");
const c = @import("cgrpc");
const t = @import("types.zig");

const Allocator = std.mem.Allocator;

const Context = struct {
    allocator: Allocator,
    allocated_size: usize,
};

fn destroy_slice(raw: [*]u8) callconv(.c) void {
    const context: *Context = @ptrCast(@alignCast(raw));
    const zig_slice: []align(@alignOf(Context)) u8 = @alignCast(raw[0..context.*.allocated_size]);
    context.*.allocator.free(zig_slice);
}

/// uses zig's allocator to benefit from leak detection.
pub fn make_slice(gpa: Allocator, data: []const u8) !t.Slice {
    if (data.len <= c.GRPC_SLICE_INLINED_SIZE)
        return .{
            .refcount = null,
            .data = .{ .inlined = .{
                .length = @truncate(data.len),
                .bytes = blk: {
                    var array: [c.GRPC_SLICE_INLINED_SIZE]u8 = undefined;
                    @memcpy(array[0..data.len], data);
                    break :blk array;
                },
            } },
        };
    const size = data.len + @sizeOf(Context);
    const memory = try gpa.alignedAlloc(u8, .of(Context), size);
    const context: *Context = @ptrCast(@alignCast(memory.ptr));
    context.*.allocator = gpa;
    context.*.allocated_size = size;
    @memcpy(memory[@sizeOf(Context)..], data);
    return c.grpc_slice_new_with_user_data(memory[@sizeOf(Context)..].ptr, data.len, @ptrCast(&destroy_slice), memory.ptr);
}

test {
    const cases: []const []const u8 = &.{
        "Short",
        "Hello World (inlined)",
        "All your codebase are belong to us (allocated)",
        "At regina gravi iamdudum saucia cura vulnus alit venis et caeco carpitur igni.",
    };
    for (cases) |case| {
        const a = try make_slice(std.testing.allocator, case);
        defer c.grpc_slice_unref(a);
        const b = c.grpc_slice_from_static_buffer(case.ptr, case.len);
        defer c.grpc_slice_unref(b);
        try std.testing.expectEqual(0, c.grpc_slice_cmp(a, b));
    }
}

// ---
// const max_inlined_length = @sizeOf(usize) + @sizeOf(*u8) - @sizeOf(u8) + @sizeOf(*opaque {});

// const slice_refcount = opaque {};

// pub const Slice = extern struct {
//     refcount: ?*slice_refcount,
//     data: extern union {
//         refcounted: extern struct {
//             length: usize,
//             bytes: [*]u8,
//         },
//         inlined: extern struct {
//             length: u8,
//             bytes: [max_inlined_length]u8,
//         },
//     },
// };

// const slice_buffer = extern struct {
//     _private: ?[*]slice,
//     slices: [*]slice,
//     slices_count: usize,
//     slices_capacity: usize,
//     length: usize,
//     inlined: [3]slice,
// };

// const byte_buffer_type = enum(u8) { raw };
// const compression_algo = enum(u8) {
//     none,
//     deflate,
//     gzip,
// };
// const byte_buffer = extern struct {
//     _reserved: *opaque {},
//     buffer_type: byte_buffer_type,
//     data: extern union {
//         _reserved: [8]*opaque {},
//         raw: extern struct {
//             compression: compression_algo,
//             buffer: slice_buffer,
//         },
//     },
// };

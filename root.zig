const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

start: [*]u8,
end: [*]u8,

pub fn init(buffer: []u8) @This() {
    return .{
        .start = buffer.ptr,
        .end = buffer.ptr + buffer.len,
    };
}

pub fn allocator(self: *@This()) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = Allocator.noResize,
            .remap = Allocator.noRemap,
            .free = free,
        },
    };
}

/// Save the current state of the allocator
pub fn savestate(self: *@This()) usize {
    return @intFromPtr(self.end);
}

/// Restore a previously saved allocator state
pub fn restore(self: *@This(), state: usize) void {
    self.end = @ptrFromInt(state);
}

pub fn alloc(
    ctx: *anyopaque,
    length: usize,
    alignment: Alignment,
    _: usize,
) ?[*]u8 {
    const self: *@This() = @alignCast(@ptrCast(ctx));

    // Only allocate memory that can fit in the buffer
    if (@intFromPtr(self.end) < length) return null;
    const unaligned = @intFromPtr(self.end) - length;
    const aligned = alignment.backward(unaligned);
    if (aligned < @intFromPtr(self.start)) return null;
    self.end = @ptrFromInt(aligned);

    return self.end;
}

pub fn free(
    ctx: *anyopaque,
    memory: []u8,
    _: Alignment,
    _: usize,
) void {
    // Only free if this is the immediate last allocation
    const self: *@This() = @alignCast(@ptrCast(ctx));
    if (memory.ptr != self.end) return;
    self.end += memory.len;
}

test "BumpAllocator" {
    var buffer: [1 << 20]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    try std.heap.testAllocator(gpa);
    try std.heap.testAllocatorAligned(gpa);
    try std.heap.testAllocatorAlignedShrink(gpa);
    try std.heap.testAllocatorLargeAlignment(gpa);
}

test "savestate and restore" {
    var buffer: [256]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    const state_before = bump_allocator.savestate();
    _ = try gpa.alloc(u8, buffer.len);

    bump_allocator.restore(state_before);
    _ = try gpa.alloc(u8, buffer.len);
}

test "avoid integer overflow for obscene allocations" {
    var buffer: [10]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    _ = try gpa.alloc(u8, 5);
    const problem = gpa.alloc(u8, std.math.maxInt(usize));
    try std.testing.expectError(error.OutOfMemory, problem);
}

const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

base: usize,
limit: usize,

pub fn init(buffer: []u8) @This() {
    const base: usize = @intFromPtr(buffer.ptr);
    const limit: usize = base + buffer.len;
    return .{ .base = base, .limit = limit };
}

pub fn allocator(self: *@This()) Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        },
    };
}

/// Save the current state of the allocator
pub fn savestate(self: *@This()) usize {
    return self.base;
}

/// Restore a previously saved allocator state
pub fn restore(self: *@This(), state: usize) void {
    self.base = state;
}

fn alloc(
    ctx: *anyopaque,
    length: usize,
    alignment: Alignment,
    _: usize,
) ?[*]u8 {
    const self: *@This() = @alignCast(@ptrCast(ctx));

    // Only allocate if we have enough space
    const aligned = alignment.forward(self.base);
    const end_addr = @addWithOverflow(aligned, length);
    if ((end_addr[1] == 1) | (end_addr[0] > self.limit)) return null;

    self.base = end_addr[0];
    return @ptrFromInt(aligned);
}

fn resize(
    ctx: *anyopaque,
    memory: []u8,
    _: Alignment,
    new_length: usize,
    _: usize,
) bool {
    const self: *@This() = @alignCast(@ptrCast(ctx));

    const alloc_base = @intFromPtr(memory.ptr);
    const next_alloc = alloc_base + memory.len;

    // Prior allocations can be shrunk, but not grown
    const shrinking = memory.len >= new_length;
    if (next_alloc != self.base) return shrinking;

    // Grow allocations only if we have enough space
    const end_addr = @addWithOverflow(alloc_base, new_length);
    const overflow = (end_addr[1] == 1) | (end_addr[0] > self.limit);
    if (!shrinking and overflow) return false;

    self.base = end_addr[0];
    return true;
}

fn remap(
    ctx: *anyopaque,
    memory: []u8,
    _: Alignment,
    new_length: usize,
    _: usize,
) ?[*]u8 {
    if (resize(ctx, memory, undefined, new_length, undefined)) {
        return memory.ptr;
    } else {
        return null;
    }
}

fn free(
    ctx: *anyopaque,
    memory: []u8,
    _: Alignment,
    _: usize,
) void {
    const self: *@This() = @alignCast(@ptrCast(ctx));

    // Only free the immediate last allocation
    const alloc_base = @intFromPtr(memory.ptr);
    const next_alloc = alloc_base + memory.len;
    if (next_alloc != self.base) return;

    self.base = self.base - memory.len;
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

test "reuse memory on realloc" {
    var buffer: [10]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    const slice_0 = try gpa.alloc(u8, 5);
    const slice_1 = try gpa.realloc(slice_0, 10);
    try std.testing.expect(slice_1.ptr == slice_0.ptr);
}

test "don't grow one allocation into another" {
    var buffer: [10]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    const slice_0 = try gpa.alloc(u8, 3);
    const slice_1 = try gpa.alloc(u8, 3);
    const slice_2 = try gpa.realloc(slice_0, 4);
    try std.testing.expect(slice_2.ptr == slice_1.ptr + 3);
}

test "avoid integer overflow for obscene allocations" {
    var buffer: [10]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    _ = try gpa.alloc(u8, 5);
    const problem = gpa.alloc(u8, std.math.maxInt(usize));
    try std.testing.expectError(error.OutOfMemory, problem);
}
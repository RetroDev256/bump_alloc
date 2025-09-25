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

    const aligned = alignment.forward(self.base);
    const overflow_bits = @bitSizeOf(usize) + 1;
    const T = std.meta.Int(.unsigned, overflow_bits);
    const end_addr = @as(T, aligned) + length;

    // Only allocate if we have enough space
    if (end_addr > self.limit) return null;

    self.base = @intCast(end_addr);
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

    const overflow_bits = @bitSizeOf(usize) + 1;
    const T = std.meta.Int(.unsigned, overflow_bits);
    const end_addr = @as(T, alloc_base) + new_length;

    // Grow allocations only if we have enough space
    const overflow = end_addr > self.limit;
    if (!shrinking and overflow) return false;

    self.base = @intCast(end_addr);
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

test "BumpAllocator General Usage" {
    var buffer: [1 << 20]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const gpa = bump_allocator.allocator();

    try std.heap.testAllocator(gpa);
    try std.heap.testAllocatorAligned(gpa);
    try std.heap.testAllocatorAlignedShrink(gpa);
    try std.heap.testAllocatorLargeAlignment(gpa);
}

test "BumpAllocator Savestates" {
    var buffer: [256]u8 = undefined;
    var bump_allocator: @This() = .init(&buffer);
    const original = bump_allocator.savestate();
    const gpa = bump_allocator.allocator();

    {
        const state = bump_allocator.savestate();
        defer bump_allocator.restore(state);

        _ = try gpa.create(usize);
        _ = try gpa.alignedAlloc(u8, .@"32", 13);
        _ = try gpa.create(struct { u8, u17, u33 });
    }

    if (original != bump_allocator.savestate()) {
        return error.BrokenSaveState;
    }
}

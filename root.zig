const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

memory: [*]u8,
length: usize,

pub fn init(buffer: []u8) @This() {
    return .{
        .memory = buffer.ptr,
        .length = buffer.len,
    };
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
    return self.length;
}

/// Restore a previously saved allocator state
pub fn restore(self: *@This(), state: usize) void {
    const change = self.length -% state;
    const old_address = @intFromPtr(self.memory);
    const new_address = old_address +% change;
    self.memory = @ptrFromInt(new_address);
    self.length = state;
}

fn alloc(
    ctx: *anyopaque,
    length: usize,
    alignment: Alignment,
    _: usize,
) ?[*]u8 {
    const self: *@This() = @alignCast(@ptrCast(ctx));

    const old_address = @intFromPtr(self.memory);
    const aligned = alignment.forward(old_address);
    const required = (aligned - old_address) + length;

    // Only allocate if we have enough space
    if (required > self.length) return null;

    const new_address = aligned + length;
    self.memory = @ptrFromInt(new_address);
    self.length = self.length - required;
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

    const next_alloc = memory.ptr + memory.len;
    const increase = new_length -% memory.len;
    const shrinking = memory.len >= new_length;
    const overflow = increase > self.length;

    // Prior allocations can be shrunk, but not grown
    if (next_alloc != self.memory) return shrinking;
    // Grow allocations only if we have enough space
    if (!shrinking and overflow) return false;

    const old_address = @intFromPtr(self.memory);
    const new_address = old_address +% increase;
    self.memory = @ptrFromInt(new_address);
    self.length = self.length -% increase;

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
    const next_alloc = memory.ptr + memory.len;
    if (next_alloc != self.memory) return;

    self.memory = self.memory - memory.len;
    self.length = self.length + memory.len;
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
    const gpa = bump_allocator.allocator();

    {
        const state = bump_allocator.savestate();
        defer bump_allocator.restore(state);

        _ = try gpa.create(usize);
        _ = try gpa.alignedAlloc(u8, .@"32", 13);
        _ = try gpa.create(struct { u8, u17, u33 });
    }

    const correct_length = bump_allocator.length == buffer.len;
    const correct_memory = bump_allocator.memory == (&buffer).ptr;

    if (!correct_length or !correct_memory) {
        return error.BrokenSaveState;
    }
}

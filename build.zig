const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("BumpAllocator", .{
        .root_source_file = b.path("root.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
}

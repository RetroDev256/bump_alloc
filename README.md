# bump_alloc

Simple bump allocator for stack backed allocations.
As of 2025-09-23, this allocator has less overhead than the
FixedBufferAllocator in zig's stdlib (24 versus 16 bytes).

This allocator supports savestates through `savestate` and `restore`.

Run `zig fetch --save git+https://github.com/RetroDev256/bump_alloc` to add this package to your project. Add this in your `build.zig` to access `@import("BumpAllocator")`:

```zig
const bump_alloc = b.dependency("bump_alloc", .{});
const BumpAllocator = bump_alloc.module("BumpAllocator");
exe_mod.addImport("BumpAllocator", BumpAllocator);
```

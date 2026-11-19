const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 4) {
        std.debug.panic("usage: {s} <minijinja> <inputs> <public>", .{args[0]});
    }
}

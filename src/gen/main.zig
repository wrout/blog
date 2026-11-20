const std = @import("std");
const post = @import("post.zig");
const static = @import("static.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 4) {
        std.debug.panic("usage: {s} <minijinja> <inputs> <public>", .{args[0]});
    }
    var inputs = try std.Io.Dir.cwd().openDir(io, args[2], .{});
    defer inputs.close(io);
    const posts = try post.readPosts(gpa, io, inputs);
    const assets = try static.readStatic(gpa, io, inputs);
    _ = posts;
    _ = assets;
}

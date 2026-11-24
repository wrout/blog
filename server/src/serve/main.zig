const std = @import("std");
const zio = @import("zio");
const Server = @import("server.zig").Server;

pub const std_options_debug_io = zio.debug_io;

const host = "0.0.0.0";
const port = 3000;

pub fn main(init: std.process.Init) !void {
    // const io = init.io;
    const gpa = init.gpa;
    const rt = try zio.Runtime.init(gpa, .{});
    defer rt.deinit();
    const io = rt.io();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.panic("usage: {s} <public>", .{args[0]});
    }
    var public = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    defer public.close(io);
    const address = try std.Io.net.IpAddress.parse(host, port);
    var server = try Server.init(io, public, address);
    defer server.deinit(io);
    try server.run(gpa, io);
}

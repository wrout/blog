const std = @import("std");

pub const Resolver = struct {
    public: std.Io.Dir,
};

pub fn handle(gpa: std.mem.Allocator, io: std.Io, resolver: Resolver, stream: std.Io.net.Stream) void {
    _ = gpa;
    _ = resolver;
    stream.close(io);
}

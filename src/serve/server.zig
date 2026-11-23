const std = @import("std");
const route = @import("route.zig");

const Outcome = union(enum) {
    serve: std.Io.net.Server.AcceptError!void,
    shutdown: std.Io.File.ReadStreamingError!void,
};

pub const Server = struct {
    listener: std.Io.net.Server,
    resolver: route.Resolver,
    signals: Signals,

    pub fn init(io: std.Io, public: std.Io.Dir, address: std.Io.net.IpAddress) !Server {
        const signals = try Signals.init();
        errdefer signals.deinit(io);
        const listener = try address.listen(io, .{ .reuse_address = true });
        std.log.info("listening on http://{f}", .{address});
        return .{
            .listener = listener,
            .resolver = .{ .public = public },
            .signals = signals,
        };
    }

    pub fn deinit(server: *Server, io: std.Io) void {
        server.listener.deinit(io);
        server.signals.deinit(io);
    }

    pub fn run(server: *Server, gpa: std.mem.Allocator, io: std.Io) !void {
        var buffer: [2]Outcome = undefined;
        var race = std.Io.Select(Outcome).init(io, &buffer);
        defer race.cancelDiscard();
        try race.concurrent(.serve, serve, .{ gpa, io, server.resolver, &server.listener });
        try race.concurrent(.shutdown, Signals.wait, .{ server.signals, io });
        switch (try race.await()) {
            .serve => |result| return result,
            .shutdown => |result| {
                try result;
                std.log.info("shutting down...", .{});
            },
        }
    }
};

fn serve(gpa: std.mem.Allocator, io: std.Io, resolver: route.Resolver, listener: *std.Io.net.Server) std.Io.net.Server.AcceptError!void {
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    while (true) {
        const stream = try listener.accept(io);
        group.concurrent(io, route.handle, .{ gpa, io, resolver, stream }) catch |err| {
            std.log.warn("dropped connection: {t}", .{err});
            stream.close(io);
        };
    }
}

// todo support windows?
const Signals = struct {
    file: std.Io.File,

    fn init() !Signals {
        var mask = std.posix.sigemptyset();
        std.posix.sigaddset(&mask, .INT);
        std.posix.sigaddset(&mask, .TERM);
        std.posix.sigprocmask(std.posix.SIG.BLOCK, &mask, null);
        const fd = try std.posix.signalfd(-1, &mask, std.os.linux.SFD.CLOEXEC);
        return .{
            .file = .{
                .handle = fd,
                .flags = .{ .nonblocking = false },
            },
        };
    }

    fn deinit(signals: Signals, io: std.Io) void {
        signals.file.close(io);
    }

    fn wait(signals: Signals, io: std.Io) std.Io.File.ReadStreamingError!void {
        var info: std.os.linux.signalfd_siginfo = undefined;
        _ = try signals.file.readStreaming(io, &.{std.mem.asBytes(&info)});
    }
};

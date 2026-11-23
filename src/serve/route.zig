const std = @import("std");

pub fn handle(gpa: std.mem.Allocator, io: std.Io, resolver: Resolver, stream: std.Io.net.Stream) void {
    defer stream.close(io);
    var in_buffer: [8192]u8 = undefined;
    var out_buffer: [8192]u8 = undefined;
    var reader = stream.reader(io, &in_buffer);
    var writer = stream.writer(io, &out_buffer);
    var connection: Connection = .init(&reader.interface, &writer.interface);
    while (connection.receive()) |received| {
        var request = received;
        respond(gpa, io, resolver, &request) catch |err| {
            std.log.warn("respond: {t}", .{err});
            return;
        };
        if (!request.inner.head.keep_alive) {
            return;
        }
    } else |err| switch (err) {
        error.ConnectionClosed => {},
        else => std.log.warn("receive: {t}", .{err}),
    }
}

fn respond(gpa: std.mem.Allocator, io: std.Io, resolver: Resolver, request: *Request) !void {
    _ = gpa;
    _ = io;
    _ = resolver;
    switch (request.inner.head.method) {
        .GET, .HEAD => {},
        else => return request.reply(.method_not_allowed),
    }
    return request.reply(.not_found);
}

pub const Resolver = struct {
    public: std.Io.Dir,
};

const Connection = struct {
    server: std.http.Server,

    fn init(reader: *std.Io.Reader, writer: *std.Io.Writer) Connection {
        return .{
            .server = .init(reader, writer),
        };
    }

    fn receive(connection: *Connection) !Request {
        const inner = connection.server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return error.ConnectionClosed,
            else => return err,
        };
        return .{
            .inner = inner,
        };
    }
};

const Request = struct {
    inner: std.http.Server.Request,

    fn reply(request: *Request, status: std.http.Status) !void {
        return request.inner.respond("", .{ .status = status });
    }
};

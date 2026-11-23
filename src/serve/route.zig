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
    switch (request.inner.head.method) {
        .GET, .HEAD => {},
        else => return request.reply(.method_not_allowed),
    }
    var asset = try resolver.find(gpa, io, request.inner.head.target);
    defer asset.close(io);
    try request.send(io, &asset);
}

pub const Resolver = struct {
    public: std.Io.Dir,

    pub fn find(resolver: Resolver, gpa: std.mem.Allocator, io: std.Io, target: []const u8) !Asset {
        const path = try Path.parse(gpa, target) orelse return resolver.missing(gpa, io);
        defer path.deinit(gpa);
        return try resolver.open(gpa, io, path, .ok) orelse resolver.missing(gpa, io);
    }

    fn missing(resolver: Resolver, gpa: std.mem.Allocator, io: std.Io) !Asset {
        return try resolver.open(gpa, io, .not_found_page, .not_found) orelse error.MissingNotFoundPage;
    }

    fn open(resolver: Resolver, gpa: std.mem.Allocator, io: std.Io, path: Path, status: std.http.Status) !?Asset {
        const file_path = try resolver.locate(gpa, io, path) orelse return null;
        defer gpa.free(file_path);
        const file = resolver.public.openFile(io, file_path, .{}) catch return null;
        return try Asset.init(io, file, status, .of(file_path));
    }

    fn locate(resolver: Resolver, gpa: std.mem.Allocator, io: std.Io, path: Path) !?[]const u8 {
        const stat = resolver.public.statFile(io, path.relative, .{}) catch return null;
        if (stat.kind == .directory) {
            return try std.fs.path.join(gpa, &.{ path.relative, "index.html" });
        }
        return try gpa.dupe(u8, path.relative);
    }
};

const Path = struct {
    relative: []const u8,

    const not_found_page: Path = .{ .relative = "404.html" };

    fn parse(gpa: std.mem.Allocator, target: []const u8) !?Path {
        const uri = std.Uri.parseAfterScheme("", target) catch return null;
        var decoded: std.Io.Writer.Allocating = .init(gpa);
        defer decoded.deinit();
        uri.path.formatRaw(&decoded.writer) catch return error.OutOfMemory;
        var components: std.ArrayList([]const u8) = .empty;
        defer components.deinit(gpa);
        try components.append(gpa, ".");
        var iterator = std.fs.path.componentIterator(decoded.written());
        while (iterator.next()) |component| {
            // paths stay scoped within public/
            if (std.mem.eql(u8, component.name, "..")) {
                return null;
            }
            try components.append(gpa, component.name);
        }
        return .{
            .relative = try std.fs.path.join(gpa, components.items),
        };
    }

    fn deinit(path: Path, gpa: std.mem.Allocator) void {
        gpa.free(path.relative);
    }
};

const Asset = struct {
    file: std.Io.File,
    size: u64,
    status: std.http.Status,
    media: Media,

    fn init(io: std.Io, file: std.Io.File, status: std.http.Status, media: Media) !Asset {
        errdefer file.close(io);
        const stat = try file.stat(io);
        return .{
            .file = file,
            .size = stat.size,
            .status = status,
            .media = media,
        };
    }

    fn close(asset: Asset, io: std.Io) void {
        asset.file.close(io);
    }
};

const Media = enum {
    html,
    css,
    text,
    woff2,
    jpeg,
    png,
    svg,
    icon,
    binary,

    const extensions = std.StaticStringMap(Media).initComptime(.{
        .{ ".html", .html },
        .{ ".css", .css },
        .{ ".txt", .text },
        .{ ".typ", .text },
        .{ ".woff2", .woff2 },
        .{ ".jpeg", .jpeg },
        .{ ".jpg", .jpeg },
        .{ ".png", .png },
        .{ ".svg", .svg },
        .{ ".ico", .icon },
    });

    fn of(file_path: []const u8) Media {
        return extensions.get(std.fs.path.extension(file_path)) orelse .binary;
    }

    fn contentType(media: Media) []const u8 {
        return switch (media) {
            .html => "text/html; charset=utf-8",
            .css => "text/css; charset=utf-8",
            .text => "text/plain; charset=utf-8",
            .woff2 => "font/woff2",
            .jpeg => "image/jpeg",
            .png => "image/png",
            .svg => "image/svg+xml",
            .icon => "image/x-icon",
            .binary => "application/octet-stream",
        };
    }
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

    const cache = "public, max-age=31536000, immutable";

    fn send(request: *Request, io: std.Io, asset: *Asset) !void {
        var headers: Headers = .{};
        try headers.add("content-type", asset.media.contentType());
        try headers.add("cache-control", cache);
        var file_buffer: [8192]u8 = undefined;
        var file_reader = asset.file.reader(io, &file_buffer);
        var body_buffer: [8192]u8 = undefined;
        var body = try request.inner.respondStreaming(&body_buffer, .{
            .content_length = asset.size,
            .respond_options = .{
                .status = asset.status,
                .extra_headers = headers.slice(),
            },
        });
        _ = try body.writer.sendFileAll(&file_reader, .unlimited);
        try body.end();
    }
};

const Headers = struct {
    items: [capacity]std.http.Header = undefined,
    len: usize = 0,

    // todo bump when need more header
    const capacity = 8;

    fn add(headers: *Headers, name: []const u8, value: []const u8) error{TooManyHeaders}!void {
        if (headers.len == capacity) {
            return error.TooManyHeaders;
        }
        headers.items[headers.len] = .{
            .name = name,
            .value = value,
        };
        headers.len += 1;
    }

    fn slice(headers: *const Headers) []const std.http.Header {
        return headers.items[0..headers.len];
    }
};

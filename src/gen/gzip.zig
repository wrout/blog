const std = @import("std");

pub fn compressTree(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !void {
    var walker = try dir.walk(gpa);
    defer walker.deinit(io);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !compressible.has(std.fs.path.extension(entry.basename))) {
            continue;
        }
        try compressFile(gpa, io, dir, entry.path);
    }
}

const compressible = std.StaticStringMap(void).initComptime(.{
    .{".html"},
    .{".css"},
    .{".txt"},
    .{".typ"},
    .{".svg"},
});

fn compressFile(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !void {
    const bytes = try dir.readFileAlloc(io, path, gpa, .unlimited);
    defer gpa.free(bytes);
    const compressed = try std.mem.concat(gpa, u8, &.{ path, ".gz" });
    defer gpa.free(compressed);
    const file = try dir.createFile(io, compressed, .{});
    defer file.close(io);
    var file_buffer: [8192]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);
    const window = try gpa.alloc(u8, std.compress.flate.max_window_len);
    defer gpa.free(window);
    var gzip = try std.compress.flate.Compress.init(&file_writer.interface, window, .gzip, .best);
    try gzip.writer.writeAll(bytes);
    try gzip.finish();
    try file_writer.interface.flush();
}

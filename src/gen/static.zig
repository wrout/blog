const std = @import("std");

pub const File = struct {
    path: []const u8,
    version: [16]u8,
    bytes: []const u8,

    pub fn init(path: []const u8, bytes: []const u8) File {
        const hash = std.hash.Wyhash.hash(0, bytes);
        return .{
            .path = path,
            .version = std.fmt.hex(hash),
            .bytes = bytes,
        };
    }

    fn lessThan(_: void, a: File, b: File) bool {
        return std.mem.lessThan(u8, a.path, b.path);
    }
};

pub const Static = struct {
    files: []const File,

    pub fn init(files: []File) Static {
        std.mem.sort(File, files, {}, File.lessThan);
        return .{
            .files = files,
        };
    }
};

pub fn readStatic(gpa: std.mem.Allocator, io: std.Io, inputs: std.Io.Dir) !Static {
    var dir = try inputs.openDir(io, "static", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit(io);
    var files: std.ArrayList(File) = .empty;
    errdefer files.deinit(gpa);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const path = try gpa.dupe(u8, entry.path);
        const bytes = try dir.readFileAlloc(io, path, gpa, .unlimited);
        try files.append(gpa, .init(path, bytes));
    }
    const owned = try files.toOwnedSlice(gpa);
    return Static.init(owned);
}

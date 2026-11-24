const std = @import("std");

pub const File = struct {
    path: []const u8,
    version: [16]u8,
    bytes: []const u8,

    pub fn init(gpa: std.mem.Allocator, path: []const u8, bytes: []const u8) !File {
        const owned = try gpa.dupe(u8, path);
        return .{
            .path = owned,
            .version = std.fmt.hex(std.hash.Wyhash.hash(0, bytes)),
            .bytes = bytes,
        };
    }

    pub fn deinit(file: File, gpa: std.mem.Allocator) void {
        gpa.free(file.path);
        gpa.free(file.bytes);
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

    pub fn deinit(static: Static, gpa: std.mem.Allocator) void {
        for (static.files) |file| {
            file.deinit(gpa);
        }
        gpa.free(static.files);
    }

    pub fn writeInto(static: Static, io: std.Io, dir: std.Io.Dir) !void {
        for (static.files) |file| {
            if (std.fs.path.dirname(file.path)) |parent| {
                try dir.createDirPath(io, parent);
            }
            try dir.writeFile(io, .{
                .sub_path = file.path,
                .data = file.bytes,
            });
        }
    }
};

pub fn readStatic(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !Static {
    var walker = try dir.walk(gpa);
    // defer walker.deinit(io);
    defer walker.deinit();
    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |file| {
            file.deinit(gpa);
        }
        files.deinit(gpa);
    }
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        const file = try readFile(gpa, io, dir, entry.path);
        errdefer file.deinit(gpa);
        try files.append(gpa, file);
    }
    const owned = try files.toOwnedSlice(gpa);
    return Static.init(owned);
}

fn readFile(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !File {
    const bytes = try dir.readFileAlloc(io, path, gpa, .unlimited);
    errdefer gpa.free(bytes);
    return File.init(gpa, path, bytes);
}

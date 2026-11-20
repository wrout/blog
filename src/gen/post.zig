const std = @import("std");
const typst = @import("typst.zig");

pub const Metadata = struct {
    title: []const u8,
    description: []const u8,
    keywords: []const []const u8,
    published: []const u8,
    updated: ?[]const u8,
};

pub const Post = struct {
    source: []const u8,
    stem: []const u8,
    document: typst.Document,
    metadata: Metadata,
    bytes: []const u8,

    pub fn init(gpa: std.mem.Allocator, source: []const u8, html: []const u8, json: []const u8, bytes: []const u8) !Post {
        const stem = try stemOf(gpa, source);
        const document = try typst.Document.init(gpa, html);
        const metadata = try std.json.parseFromSliceLeaky(Metadata, gpa, json, .{});
        return .{
            .source = source,
            .stem = stem,
            .document = document,
            .metadata = metadata,
            .bytes = bytes,
        };
    }

    fn lessThan(_: void, a: Post, b: Post) bool {
        return std.mem.lessThan(u8, a.source, b.source);
    }
};

fn stemOf(gpa: std.mem.Allocator, source: []const u8) ![]const u8 {
    const name = std.fs.path.stem(source);
    const parent = std.fs.path.dirname(source) orelse return name;
    return std.fs.path.join(gpa, &.{ parent, name });
}

pub const Posts = struct {
    items: []const Post,

    pub fn init(items: []Post) Posts {
        std.mem.sort(Post, items, {}, Post.lessThan);
        return .{
            .items = items,
        };
    }
};

const staged_page = "page.html";
const staged_meta = "meta.json";
const staged_source = "source.typ";

pub fn readPosts(gpa: std.mem.Allocator, io: std.Io, inputs: std.Io.Dir) !Posts {
    var dir = try inputs.openDir(io, "posts", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit(io);
    var items: std.ArrayList(Post) = .empty;
    errdefer items.deinit(gpa);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.eql(u8, entry.basename, staged_page)) {
            continue;
        }
        const source = std.fs.path.dirname(entry.path) orelse continue;
        const owned = try gpa.dupe(u8, source);
        const post = readPost(gpa, io, dir, owned) catch |err| {
            std.debug.panic("posts/{s}: {t}", .{ owned, err });
        };
        try items.append(gpa, post);
    }
    const owned = try items.toOwnedSlice(gpa);
    return Posts.init(owned);
}

fn readPost(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, source: []const u8) !Post {
    var staged = try dir.openDir(io, source, .{});
    defer staged.close(io);
    const html = try staged.readFileAlloc(io, staged_page, gpa, .unlimited);
    const json = try staged.readFileAlloc(io, staged_meta, gpa, .unlimited);
    const bytes = try staged.readFileAlloc(io, staged_source, gpa, .unlimited);
    return Post.init(gpa, source, html, json, bytes);
}

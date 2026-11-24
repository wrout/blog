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
    metadata: std.json.Parsed(Metadata),

    pub fn init(gpa: std.mem.Allocator, source: []const u8, document: typst.Document, metadata: std.json.Parsed(Metadata)) !Post {
        const owned = try gpa.dupe(u8, source);
        errdefer gpa.free(owned);
        const stem = try stemOf(gpa, owned);
        return .{
            .source = owned,
            .stem = stem,
            .document = document,
            .metadata = metadata,
        };
    }

    pub fn deinit(post: Post, gpa: std.mem.Allocator) void {
        gpa.free(post.source);
        gpa.free(post.stem);
        post.document.deinit(gpa);
        post.metadata.deinit();
    }

    fn lessThan(_: void, a: Post, b: Post) bool {
        return std.mem.lessThan(u8, a.source, b.source);
    }
};

fn stemOf(gpa: std.mem.Allocator, source: []const u8) ![]const u8 {
    const name = std.fs.path.stem(source);
    const parent = std.fs.path.dirname(source) orelse return gpa.dupe(u8, name);
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

    pub fn deinit(posts: Posts, gpa: std.mem.Allocator) void {
        for (posts.items) |post| {
            post.deinit(gpa);
        }
        gpa.free(posts.items);
    }
};

pub fn readPosts(gpa: std.mem.Allocator, io: std.Io, posts: std.Io.Dir, compiler: typst.Compiler) !Posts {
    var walker = try posts.walk(gpa);
    // defer walker.deinit(io);
    defer walker.deinit();
    var items: std.ArrayList(Post) = .empty;
    errdefer {
        for (items.items) |post| {
            post.deinit(gpa);
        }
        items.deinit(gpa);
    }
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.eql(u8, std.fs.path.extension(entry.basename), ".typ")) {
            continue;
        }
        const post = readPost(gpa, io, posts, compiler, entry.path) catch |err| {
            std.debug.panic("posts/{s}: {t}", .{ entry.path, err });
        };
        errdefer post.deinit(gpa);
        try items.append(gpa, post);
    }
    // posts takes ownership
    const owned = try items.toOwnedSlice(gpa);
    return Posts.init(owned);
}

fn readPost(gpa: std.mem.Allocator, io: std.Io, posts: std.Io.Dir, compiler: typst.Compiler, source: []const u8) !Post {
    const path = try posts.realPathFileAlloc(io, source, gpa);
    defer gpa.free(path);
    const document = try compiler.compile(gpa, io, path);
    errdefer document.deinit(gpa);
    const meta = try compiler.metadata(gpa, io, path);
    defer meta.deinit();
    const metadata = try meta.decode(gpa, Metadata);
    errdefer metadata.deinit();
    return Post.init(gpa, source, document, metadata);
}

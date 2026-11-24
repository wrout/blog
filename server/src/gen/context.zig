const std = @import("std");
const post = @import("post.zig");
const static = @import("static.zig");
const typst = @import("typst.zig");

pub const Summary = struct {
    stem: []const u8,
    source: []const u8,
    metadata: post.Metadata,

    fn init(p: *const post.Post) Summary {
        return .{
            .stem = p.stem,
            .source = p.source,
            .metadata = p.metadata.value,
        };
    }

    fn newerThan(_: void, a: Summary, b: Summary) bool {
        return switch (std.mem.order(u8, a.metadata.published, b.metadata.published)) {
            .gt => true,
            .lt => false,
            .eq => std.mem.lessThan(u8, a.stem, b.stem),
        };
    }
};

pub const Entry = struct {
    stem: []const u8,
    source: []const u8,
    metadata: post.Metadata,
    document: typst.Document,

    pub fn init(p: *const post.Post) Entry {
        return .{
            .stem = p.stem,
            .source = p.source,
            .metadata = p.metadata.value,
            .document = p.document,
        };
    }
};

pub const Tree = struct {
    name: []const u8,
    posts: []const Summary,
    dirs: []const Tree,

    pub fn deinit(tree: Tree, gpa: std.mem.Allocator) void {
        for (tree.dirs) |dir| {
            dir.deinit(gpa);
        }
        gpa.free(tree.dirs);
        gpa.free(tree.posts);
    }
};

pub const Asset = struct {
    path: []const u8,
    version: []const u8,
};

pub const Base = struct {};

pub const Macros = struct {};

pub const Home = struct {
    posts: []const Summary,
    tree: *const Tree,
    assets: []const Asset,

    pub fn init(site: *const Site) Home {
        return .{
            .posts = site.posts,
            .tree = &site.tree,
            .assets = site.assets,
        };
    }
};

pub const NotFound = struct {
    tree: *const Tree,
    assets: []const Asset,

    pub fn init(site: *const Site) NotFound {
        return .{
            .tree = &site.tree,
            .assets = site.assets,
        };
    }
};

pub const Post = struct {
    post: Entry,
    tree: *const Tree,
    assets: []const Asset,

    pub fn init(site: *const Site, entry: Entry) Post {
        return .{
            .post = entry,
            .tree = &site.tree,
            .assets = site.assets,
        };
    }
};

pub const Site = struct {
    tree: Tree,
    assets: []const Asset,
    posts: []const Summary,

    pub fn init(
        gpa: std.mem.Allocator,
        // borrowed
        posts: post.Posts,
        // borrowed
        files: static.Static,
    ) !Site {
        const tree = try growTree(gpa, posts);
        errdefer tree.deinit(gpa);
        const assets = try listAssets(gpa, files);
        errdefer gpa.free(assets);
        const summaries = try listPosts(gpa, posts);
        return .{
            .tree = tree,
            .assets = assets,
            .posts = summaries,
        };
    }

    pub fn deinit(site: Site, gpa: std.mem.Allocator) void {
        site.tree.deinit(gpa);
        gpa.free(site.assets);
        gpa.free(site.posts);
    }
};

fn growTree(gpa: std.mem.Allocator, posts: post.Posts) !Tree {
    var root: Node = .empty;
    defer root.deinit(gpa);
    for (posts.items) |*p| {
        try root.insert(gpa, .init(p));
    }
    return root.freeze(gpa);
}

const Node = struct {
    name: []const u8,
    posts: std.ArrayList(Summary),
    dirs: std.ArrayList(Node),

    const empty: Node = .{
        .name = "",
        .posts = .empty,
        .dirs = .empty,
    };

    fn deinit(node: *Node, gpa: std.mem.Allocator) void {
        for (node.dirs.items) |*dir| {
            dir.deinit(gpa);
        }
        node.dirs.deinit(gpa);
        node.posts.deinit(gpa);
    }

    fn insert(node: *Node, gpa: std.mem.Allocator, summary: Summary) !void {
        const parent = std.fs.path.dirname(summary.source) orelse "";
        var components = std.fs.path.componentIterator(parent);
        var current = node;
        while (components.next()) |component| {
            current = try current.child(gpa, component.name);
        }
        try current.posts.append(gpa, summary);
    }

    fn child(node: *Node, gpa: std.mem.Allocator, name: []const u8) !*Node {
        for (node.dirs.items) |*dir| {
            if (std.mem.eql(u8, dir.name, name)) {
                return dir;
            }
        }
        try node.dirs.append(gpa, .{
            .name = name,
            .posts = .empty,
            .dirs = .empty,
        });
        return &node.dirs.items[node.dirs.items.len - 1];
    }

    fn freeze(node: *Node, gpa: std.mem.Allocator) !Tree {
        const dirs = try gpa.alloc(Tree, node.dirs.items.len);
        var frozen: usize = 0;
        errdefer {
            for (dirs[0..frozen]) |dir| {
                dir.deinit(gpa);
            }
            gpa.free(dirs);
        }
        for (node.dirs.items, dirs) |*dir, *tree| {
            tree.* = try dir.freeze(gpa);
            frozen += 1;
        }
        const posts = try node.posts.toOwnedSlice(gpa);
        return .{
            .name = node.name,
            .posts = posts,
            .dirs = dirs,
        };
    }
};

fn listAssets(gpa: std.mem.Allocator, files: static.Static) ![]const Asset {
    const assets = try gpa.alloc(Asset, files.files.len);
    for (files.files, assets) |*file, *asset| {
        asset.* = .{
            .path = file.path,
            .version = &file.version,
        };
    }
    return assets;
}

fn listPosts(gpa: std.mem.Allocator, posts: post.Posts) ![]const Summary {
    const summaries = try gpa.alloc(Summary, posts.items.len);
    for (posts.items, summaries) |*p, *summary| {
        summary.* = .init(p);
    }
    std.mem.sort(Summary, summaries, {}, Summary.newerThan);
    return summaries;
}

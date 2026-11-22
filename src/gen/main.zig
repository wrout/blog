const std = @import("std");
const config = @import("config");

const typst = @import("typst.zig");
const minijinja = @import("minijinja.zig");
const post = @import("post.zig");
const static = @import("static.zig");
const context = @import("context.zig");
const gzip = @import("gzip.zig");

const Input = struct {
    content: std.Io.Dir,
    templates: std.Io.Dir,
    posts: std.Io.Dir,
    static: std.Io.Dir,

    pub fn init(io: std.Io, dir: std.Io.Dir, path: []const u8) !Input {
        var content = try dir.openDir(io, path, .{});
        errdefer content.close(io);
        var templates = try content.openDir(io, "templates", .{});
        errdefer templates.close(io);
        var posts = try content.openDir(io, "posts", .{ .iterate = true });
        errdefer posts.close(io);
        const static_dir = try content.openDir(io, "static", .{ .iterate = true });
        return .{
            .content = content,
            .templates = templates,
            .posts = posts,
            .static = static_dir,
        };
    }

    pub fn deinit(input: *Input, io: std.Io) void {
        input.content.close(io);
        input.templates.close(io);
        input.posts.close(io);
        input.static.close(io);
    }
};

const Output = struct {
    public: std.Io.Dir,
    static: std.Io.Dir,
    posts: std.Io.Dir,
    contexts: std.Io.Dir,

    pub fn init(io: std.Io, dir: std.Io.Dir, path: []const u8) !Output {
        var out = try dir.createDirPathOpen(io, path, .{});
        defer out.close(io);
        var public = try out.createDirPathOpen(io, "public", .{ .open_options = .{ .iterate = true } });
        errdefer public.close(io);
        var static_dir = try public.createDirPathOpen(io, "static", .{});
        errdefer static_dir.close(io);
        var posts = try public.createDirPathOpen(io, "posts", .{});
        errdefer posts.close(io);
        const contexts = try out.createDirPathOpen(io, "work/contexts", .{});
        return .{
            .public = public,
            .static = static_dir,
            .posts = posts,
            .contexts = contexts,
        };
    }

    pub fn deinit(output: *Output, io: std.Io) void {
        output.public.close(io);
        output.static.close(io);
        output.posts.close(io);
        output.contexts.close(io);
    }
};

const Tools = struct {
    typst: Typst,
    minijinja: MiniJinja,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !Tools {
        const typst_tool = try Typst.init(gpa, io, dir);
        errdefer typst_tool.deinit(gpa);
        const minijinja_tool = try MiniJinja.init(gpa, io, dir);
        return .{
            .typst = typst_tool,
            .minijinja = minijinja_tool,
        };
    }

    pub fn deinit(tools: Tools, gpa: std.mem.Allocator) void {
        tools.typst.deinit(gpa);
        tools.minijinja.deinit(gpa);
    }

    const Typst = struct {
        exe: [:0]const u8,
        packages: [:0]const u8,

        pub fn init(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !Typst {
            const exe = try dir.realPathFileAlloc(io, config.typst, gpa);
            errdefer gpa.free(exe);
            const packages = try dir.realPathFileAlloc(io, config.packages, gpa);
            return .{
                .exe = exe,
                .packages = packages,
            };
        }

        pub fn deinit(tool: Typst, gpa: std.mem.Allocator) void {
            gpa.free(tool.exe);
            gpa.free(tool.packages);
        }

        pub fn compiler(tool: Typst, root: std.Io.Dir) typst.Compiler {
            return .{
                .exe = tool.exe,
                .root = root,
                .packages = tool.packages,
            };
        }
    };

    const MiniJinja = struct {
        exe: [:0]const u8,

        pub fn init(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) !MiniJinja {
            const exe = try dir.realPathFileAlloc(io, config.minijinja, gpa);
            return .{
                .exe = exe,
            };
        }

        pub fn deinit(tool: MiniJinja, gpa: std.mem.Allocator) void {
            gpa.free(tool.exe);
        }

        pub fn renderer(tool: MiniJinja, templates: std.Io.Dir, contexts: std.Io.Dir) minijinja.Renderer {
            return .{
                .exe = tool.exe,
                .templates = templates,
                .contexts = contexts,
            };
        }
    };
};

// .html
fn writePage(gpa: std.mem.Allocator, io: std.Io, public: std.Io.Dir, renderer: minijinja.Renderer, template: []const u8, page: []const []const u8, ctx: anytype) !void {
    const rendered = try renderer.render(gpa, io, template, ctx);
    defer rendered.deinit(gpa);
    const path = try std.fs.path.join(gpa, page);
    defer gpa.free(path);
    if (std.fs.path.dirname(path)) |parent| {
        try public.createDirPath(io, parent);
    }
    try public.writeFile(io, .{
        .sub_path = path,
        .data = rendered.html,
    });
}

// .typ
fn writeSources(io: std.Io, from: std.Io.Dir, to: std.Io.Dir, posts: post.Posts) !void {
    for (posts.items) |p| {
        if (std.fs.path.dirname(p.source)) |parent| {
            try to.createDirPath(io, parent);
        }
        try from.copyFile(p.source, to, p.source, io, .{});
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) {
        std.debug.panic("usage: {s} <out>", .{args[0]});
    }
    const cwd = std.Io.Dir.cwd();
    var input = try Input.init(io, cwd, config.content);
    defer input.deinit(io);
    const out = args[1];
    var output = try Output.init(io, cwd, out);
    defer output.deinit(io);

    const tools = try Tools.init(gpa, io, cwd);
    defer tools.deinit(gpa);
    const compiler = tools.typst.compiler(input.content);
    const renderer = tools.minijinja.renderer(input.templates, output.contexts);

    const posts = try post.readPosts(gpa, io, input.posts, compiler);
    defer posts.deinit(gpa);
    const files = try static.readStatic(gpa, io, input.static);
    defer files.deinit(gpa);
    const site = try context.Site.init(gpa, posts, files);
    defer site.deinit(gpa);

    try files.writeInto(io, output.static);
    try writeSources(io, input.posts, output.posts, posts);
    try writePage(gpa, io, output.public, renderer, "home.html", &.{"index.html"}, context.Home.init(&site));
    try writePage(gpa, io, output.public, renderer, "404.html", &.{"404.html"}, context.NotFound.init(&site));
    for (posts.items) |*p| {
        try writePage(gpa, io, output.public, renderer, "post.html", &.{ "posts", p.stem, "index.html" }, context.Post.init(&site, .init(p)));
    }
    try gzip.compressTree(gpa, io, output.public);
}

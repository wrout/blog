const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const typst = typstPath(b) orelse return;
    // for post changes
    b.graph.poisonCache();

    const manifest = b.createModule(.{
        .root_source_file = b.path("src/manifest.zig"),
    });

    const inputs = b.addWriteFiles();
    // copy every post into one staging tree, whose dirname is hash of all file contents
    // - changing a post changes dirname... which refreshes gen...
    _ = inputs.addCopyDirectory(b.path("content/static"), "static", .{});
    for (postPaths(b)) |path| {
        const name = path[0 .. path.len - ".typ".len];
        const post = typeset(b, typst, path);
        _ = inputs.addCopyFile(post.source, b.fmt("posts/{s}", .{path}));
        _ = inputs.addCopyFile(post.page, b.fmt("posts/{s}.html", .{name}));
        _ = inputs.addCopyFile(post.meta, b.fmt("posts/{s}.json", .{name}));
    }

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen/main.zig"),
            // pick build host, since this is a build step...
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "manifest", .module = manifest },
            },
        }),
    });
    const gen_run = b.addRunArtifact(gen);
    gen_run.addDirectoryArg(inputs.getDirectory());
    const site = gen_run.addOutputDirectoryArg("site");

    const gen_cmd = b.step("gen", "generate site");
    gen_cmd.dependOn(&gen_run.step);

    const public_install = b.addInstallDirectory(.{
        .source_dir = site.path(b, "public"),
        .install_dir = .prefix,
        .install_subdir = "public",
    });
    const public_cmd = b.step("public", "install generated site");
    public_cmd.dependOn(gen_cmd);
    public_cmd.dependOn(&public_install.step);

    const serve = b.addExecutable(.{
        .name = "blog",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/serve/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const serve_run = b.addRunArtifact(serve);
    serve_run.step.dependOn(public_cmd);
    const serve_cmd = b.step("serve", "run server");
    serve_cmd.dependOn(&serve_run.step);
}

const Typeset = struct {
    source: std.Build.LazyPath,
    page: std.Build.LazyPath,
    meta: std.Build.LazyPath,
};

fn typeset(b: *std.Build, typst: std.Build.LazyPath, path: []const u8) Typeset {
    const source = b.path(b.fmt("content/posts/{s}", .{path}));
    // compile step
    const compile_run = std.Build.Step.Run.create(b, b.fmt("typst compile {s}", .{path}));
    // typst binary is hashed, bumping version necessitates post rebuild
    compile_run.addFileArg(typst);
    compile_run.addArgs(&.{ "compile", "--features", "html", "--format", "html", "--ignore-system-fonts" });
    addTypstPaths(b, compile_run);
    compile_run.addArgs(&.{ "--deps-format", "make", "--deps" });
    _ = compile_run.addDepFileOutputArg("deps.d");
    compile_run.addFileArg2(source, .{ .make_absolute = true });
    const page = compile_run.addOutputFileArg("page.html");
    // eval step
    const eval_run = std.Build.Step.Run.create(b, b.fmt("typst eval {s}", .{path}));
    eval_run.addFileArg(typst);
    eval_run.addArgs(&.{ "eval", "--features", "html", "--target", "html", "--ignore-system-fonts" });
    addTypstPaths(b, eval_run);
    eval_run.addArg("--in");
    eval_run.addFileArg2(source, .{ .make_absolute = true });
    eval_run.addArg("query(<post>).first().value");
    // eval dumps json we need to capture
    const meta = eval_run.captureStdOut(.{});
    return .{
        .source = source,
        .page = page,
        .meta = meta,
    };
}

fn addTypstPaths(b: *std.Build, run: *std.Build.Step.Run) void {
    // posts can reference anything under content/
    run.addArg("--root");
    run.addDirectoryArg(b.path("content"));
    run.addArg("--package-path");
    run.addDirectoryArg(b.path("zig-pkg/typst"));
}

// path for typst compiler
fn typstPath(b: *std.Build) ?std.Build.LazyPath {
    const host = b.graph.host.result.cpu.arch;
    const name = switch (host) {
        .x86_64 => "typst_x86_64",
        .aarch64 => "typst_aarch64",
        else => @panic("no typst for host"),
    };
    // dont want to download aarch64 on an x86_64 target, use lazy..
    const dep = b.lazyDependency(name, .{}) orelse return null;
    return dep.path("typst");
}

fn postPaths(b: *std.Build) []const []const u8 {
    const io = b.graph.io;
    const gpa = b.allocator;
    var dir = b.root.openDir(io, "content/posts", .{ .iterate = true }) catch |err| {
        std.debug.panic("unable to open content/posts: {t}", .{err});
    };
    defer dir.close(io);
    // its a me
    var walker = dir.walk(gpa) catch @panic("oom");
    defer walker.deinit(io);
    var paths: std.ArrayList([]const u8) = .empty;
    // sorta ugly but it works
    while (walker.next(io) catch |err| std.debug.panic("unable to walk content/posts: {t}", .{err})) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".typ")) {
            continue;
        }
        // walker reuses buffer
        const path = b.dupe(entry.path);
        // path is under content/posts/
        paths.append(gpa, path) catch @panic("oom");
    }
    return paths.items;
}

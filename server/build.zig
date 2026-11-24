const std = @import("std");

const Tool = struct {
    x86_64: []const u8,
    aarch64: []const u8,
    exe: []const u8,
};

const typst_tool: Tool = .{
    .x86_64 = "typst_x86_64",
    .aarch64 = "typst_aarch64",
    .exe = "typst",
};

const minijinja_tool: Tool = .{
    .x86_64 = "minijinja_x86_64",
    .aarch64 = "minijinja_aarch64",
    .exe = "minijinja-cli",
};

fn toolPath(b: *std.Build, tool: Tool) ?std.Build.LazyPath {
    const name = switch (b.graph.host.result.cpu.arch) {
        .x86_64 => tool.x86_64,
        .aarch64 => tool.aarch64,
        else => @panic("no vendored tools for host"),
    };
    const dep = b.lazyDependency(name, .{}) orelse return null;
    return dep.path(tool.exe);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const typst = toolPath(b, typst_tool) orelse return;
    const minijinja = toolPath(b, minijinja_tool) orelse return;

    const curryst = b.dependency("curryst", .{});
    const packages = b.addWriteFiles();
    _ = packages.addCopyDirectory(curryst.path(""), "preview/curryst/0.6.0", .{});

    const content = b.addWriteFiles();
    _ = content.addCopyDirectory(b.path("content"), "", .{});

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen/main.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const gen_install = b.addInstallArtifact(gen, .{});
    const gen_step = b.step("gen", "build the site generator");
    gen_step.dependOn(&gen_install.step);

    const gen_run = b.addRunArtifact(gen);
    gen_run.addFileArg(typst);
    gen_run.addFileArg(minijinja);
    gen_run.addDirectoryArg(packages.getDirectory());
    gen_run.addDirectoryArg(content.getDirectory());
    const out = gen_run.addOutputDirectoryArg("out");

    const public_install = b.addInstallDirectory(.{
        .source_dir = out.path(b, "public"),
        .install_dir = .prefix,
        .install_subdir = "public",
    });
    b.getInstallStep().dependOn(&public_install.step);
    const site_step = b.step("site", "generate the site");
    site_step.dependOn(&public_install.step);

    const serve = b.addExecutable(.{
        .name = "serve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/serve/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const zio = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    });
    serve.root_module.addImport("zio", zio.module("zio"));
    const serve_install = b.addInstallArtifact(serve, .{});
    b.getInstallStep().dependOn(&serve_install.step);
    const server_step = b.step("server", "build the server");
    server_step.dependOn(&serve_install.step);

    const serve_run = b.addRunArtifact(serve);
    serve_run.addDirectoryArg(out.path(b, "public"));
    const serve_step = b.step("serve", "serve the generated site");
    serve_step.dependOn(&serve_run.step);
}

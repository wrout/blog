const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const typst_lazy = toolPath(b, typst_tool);
    const minijinja_lazy = toolPath(b, minijinja_tool);
    const typst = typst_lazy orelse return;
    const minijinja = minijinja_lazy orelse return;

    const curryst = b.dependency("curryst", .{});
    const packages = b.addWriteFiles();
    _ = packages.addCopyDirectory(curryst.path(""), "preview/curryst/0.6.0", .{});

    const content = b.addWriteFiles();
    _ = content.addCopyDirectory(b.path("content"), "", .{});

    const config = b.addOptions();
    config.addOptionPathDirectory("content", content.getDirectory());
    config.addOptionPathDirectory("packages", packages.getDirectory());
    config.addOptionPath("typst", typst);
    config.addOptionPath("minijinja", minijinja);

    const gen = b.addExecutable(.{
        .name = "gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen/main.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    gen.root_module.addOptions("config", config);

    const gen_run = b.addRunArtifact(gen);
    // cant hand a step fresh output dir in this version of zig, todo move to config
    const out = gen_run.addOutputDirectoryArg("out");

    const public_install = b.addInstallDirectory(.{
        .source_dir = out.path(b, "public"),
        .install_dir = .prefix,
        .install_subdir = "public",
    });
    b.getInstallStep().dependOn(&public_install.step);
}

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

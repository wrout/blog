const std = @import("std");

pub const Renderer = struct {
    exe: []const u8,
    // html templates
    templates: std.Io.Dir,
    // contexts/values for those templates
    contexts: std.Io.Dir,

    pub fn render(renderer: Renderer, gpa: std.mem.Allocator, io: std.Io, template: []const u8, context: anytype) !Page {
        const path = try writeContext(gpa, io, renderer.contexts, context);
        defer gpa.free(path);
        const html = try renderer.run(gpa, io, &.{
            "--strict",
            "--trim-blocks",
            "--lstrip-blocks",
            "--safe-path",
            ".",
            "--format",
            "json",
            template,
            path,
        });
        return .{
            .html = html,
        };
    }

    // run minijinja, capture and return stdout
    fn run(renderer: Renderer, gpa: std.mem.Allocator, io: std.Io, args: []const []const u8) ![]const u8 {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, renderer.exe);
        try argv.appendSlice(gpa, args);
        const result = try std.process.run(gpa, io, .{
            .argv = argv.items,
            .cwd = .{ .dir = renderer.templates },
        });
        defer gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code == 0) return result.stdout,
            else => {},
        }
        gpa.free(result.stdout);
        std.debug.print("{s}", .{result.stderr});
        return error.MinijinjaFailed;
    }
};

fn writeContext(gpa: std.mem.Allocator, io: std.Io, contexts: std.Io.Dir, context: anytype) ![:0]const u8 {
    var json: std.Io.Writer.Allocating = .init(gpa);
    defer json.deinit();
    try std.json.Stringify.value(context, .{}, &json.writer);
    const name = std.fmt.hex(std.hash.Wyhash.hash(0, json.written()));
    try contexts.writeFile(io, .{
        .sub_path = &name,
        .data = json.written(),
    });
    return contexts.realPathFileAlloc(io, &name, gpa);
}

pub const Page = struct {
    html: []const u8,

    pub fn deinit(page: Page, gpa: std.mem.Allocator) void {
        gpa.free(page.html);
    }
};

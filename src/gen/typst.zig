const std = @import("std");

pub const Compiler = struct {
    exe: []const u8,
    root: std.Io.Dir,
    packages: []const u8,

    pub fn compile(compiler: Compiler, gpa: std.mem.Allocator, io: std.Io, source: []const u8) !Document {
        const html = try compiler.run(gpa, io, &.{
            "compile",
            "--features",
            "html",
            "--format",
            "html",
            "--ignore-system-fonts",
            "--root",
            ".",
            "--package-path",
            compiler.packages,
            source,
            "-",
        });
        defer gpa.free(html);
        return Document.init(gpa, html);
    }

    pub fn metadata(compiler: Compiler, gpa: std.mem.Allocator, io: std.Io, source: []const u8) !Metadata {
        const json = try compiler.run(gpa, io, &.{
            "eval",
            "--features",
            "html",
            "--target",
            "html",
            "--ignore-system-fonts",
            "--root",
            ".",
            "--package-path",
            compiler.packages,
            "--in",
            source,
            "query(<meta>).first().value",
        });
        defer gpa.free(json);
        return Metadata.init(gpa, json);
    }

    fn run(compiler: Compiler, gpa: std.mem.Allocator, io: std.Io, args: []const []const u8) ![]const u8 {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(gpa);
        try argv.append(gpa, compiler.exe);
        try argv.appendSlice(gpa, args);
        const result = try std.process.run(gpa, io, .{
            .argv = argv.items,
            .cwd = .{ .dir = compiler.root },
        });
        defer gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| if (code == 0) return result.stdout,
            else => {},
        }
        gpa.free(result.stdout);
        std.debug.print("{s}", .{result.stderr});
        return error.TypstFailed;
    }
};

pub const Metadata = struct {
    parsed: std.json.Parsed(std.json.Value),

    pub fn init(gpa: std.mem.Allocator, json: []const u8) !Metadata {
        const parsed = try std.json.parseFromSlice(std.json.Value, gpa, json, .{
            .allocate = .alloc_always,
        });
        return .{
            .parsed = parsed,
        };
    }

    pub fn deinit(metadata: Metadata) void {
        metadata.parsed.deinit();
    }

    pub fn decode(metadata: Metadata, gpa: std.mem.Allocator, comptime T: type) !std.json.Parsed(T) {
        return std.json.parseFromValue(T, gpa, metadata.parsed.value, .{});
    }
};

pub const Document = struct {
    styles: []const u8,
    body: []const u8,

    pub fn init(gpa: std.mem.Allocator, html: []const u8) !Document {
        const head = inner(html, "head") orelse return error.MissingHead;
        const body = inner(html, "body") orelse return error.MissingBody;
        const styles = try collect(gpa, head, "style");
        errdefer gpa.free(styles);
        return .{
            .styles = styles,
            .body = try gpa.dupe(u8, body),
        };
    }

    pub fn deinit(document: Document, gpa: std.mem.Allocator) void {
        gpa.free(document.styles);
        gpa.free(document.body);
    }
};

// string handling sucks so we keep it scoped to inner and collect...
fn inner(html: []const u8, comptime tag: []const u8) ?[]const u8 {
    const open = "<" ++ tag ++ ">";
    const close = "</" ++ tag ++ ">";
    const start = (std.mem.indexOf(u8, html, open) orelse return null) + open.len;
    const end = std.mem.indexOfPos(u8, html, start, close) orelse return null;
    return html[start..end];
}

fn collect(gpa: std.mem.Allocator, html: []const u8, comptime tag: []const u8) ![]const u8 {
    const open = "<" ++ tag ++ ">";
    const close = "</" ++ tag ++ ">";
    var elements: std.ArrayList(u8) = .empty;
    errdefer elements.deinit(gpa);
    var rest = html;
    while (std.mem.indexOf(u8, rest, open)) |start| {
        const end = (std.mem.indexOfPos(u8, rest, start, close) orelse break) + close.len;
        try elements.appendSlice(gpa, rest[start..end]);
        rest = rest[end..];
    }
    return elements.toOwnedSlice(gpa);
}

const std = @import("std");

pub const Document = struct {
    styles: []const u8,
    body: []const u8,

    pub fn init(gpa: std.mem.Allocator, html: []const u8) !Document {
        const head = inner(html, "head") orelse return error.MissingHead;
        const body = inner(html, "body") orelse return error.MissingBody;
        const styles = try collect(gpa, head, "style");
        return .{
            .styles = styles,
            .body = body,
        };
    }
};

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
    var rest = html;
    while (std.mem.indexOf(u8, rest, open)) |start| {
        const end = (std.mem.indexOfPos(u8, rest, start, close) orelse break) + close.len;
        try elements.appendSlice(gpa, rest[start..end]);
        rest = rest[end..];
    }
    return elements.toOwnedSlice(gpa);
}

const std = @import("std");

const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    fn parse(raw: []const u8) !Date {
        if (raw.len != 10 or raw[4] != '-' or raw[7] != '-') {
            return error.InvalidDate;
        }
        const date: Date = .{
            .year = try std.fmt.parseInt(u16, raw[0..4], 10),
            .month = try std.fmt.parseInt(u8, raw[5..7], 10),
            .day = try std.fmt.parseInt(u8, raw[8..10], 10),
        };
        if (date.month < 1 or date.month > 12 or date.day < 1 or date.day > 31) {
            return error.InvalidDate;
        }
        return date;
    }

    fn order(a: Date, b: Date) std.math.Order {
        if (a.year != b.year) {
            return std.math.order(a.year, b.year);
        }
        if (a.month != b.month) {
            return std.math.order(a.month, b.month);
        }
        return std.math.order(a.day, b.day);
    }

    pub fn format(date: Date, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ date.year, date.month, date.day });
    }
};

const Meta = struct {
    published: []const u8,
    updated: ?[]const u8,
};

const Head = struct {
    html: []const u8,
    title: []const u8,
    description: ?[]const u8,
    keywords: ?[]const u8,

    fn parse(html: []const u8) !Head {
        const head = between(html, "<head>", "</head>") orelse return error.Headless;
        return .{
            .html = head,
            .title = between(head, "<title>", "</title>") orelse return error.Untitled,
            .description = between(head, "<meta name=\"description\" content=\"", "\">"),
            .keywords = between(head, "<meta name=\"keywords\" content=\"", "\">"),
        };
    }

    fn append(head: Head, gpa: std.mem.Allocator, page: *std.ArrayList(u8)) !void {
        const style_open = "<style>";
        const style_close = "</style>";
        var rest = head.html;
        while (std.mem.indexOf(u8, rest, style_open)) |start| {
            const close = std.mem.indexOfPos(u8, rest, start, style_close) orelse return error.UnclosedStyle;
            const end = close + style_close.len;
            try page.appendSlice(gpa, rest[start..end]);
            rest = rest[end..];
        }
    }
};

const Body = struct {
    html: []const u8,

    fn parse(html: []const u8) !Body {
        const body = between(html, "<body>", "</body>") orelse return error.Bodiless;
        return .{
            .html = body,
        };
    }

    fn append(body: Body, gpa: std.mem.Allocator, page: *std.ArrayList(u8)) !void {
        try page.appendSlice(gpa, body.html);
    }
};

fn between(haystack: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const start = (std.mem.indexOf(u8, haystack, open) orelse return null) + open.len;
    const end = std.mem.indexOfPos(u8, haystack, start, close) orelse return null;
    return haystack[start..end];
}

const Post = struct {
    path: []const u8,
    title: []const u8,
    description: ?[]const u8,
    tags: []const []const u8,
    published: Date,
    updated: ?Date,
    page: []const u8,

    fn parse(gpa: std.mem.Allocator, path: []const u8, html: []const u8, json: []const u8) !Post {
        const head = try Head.parse(html);
        const body = try Body.parse(html);
        const meta = try std.json.parseFromSliceLeaky(Meta, gpa, json, .{});
        const published = try Date.parse(meta.published);
        const updated = if (meta.updated) |raw| try Date.parse(raw) else null;
        const tags = try parseTags(gpa, head.keywords orelse "");
        const page = try extractPage(gpa, head, body);
        return .{
            .path = path,
            .title = head.title,
            .description = head.description,
            .tags = tags,
            .published = published,
            .updated = updated,
            .page = page,
        };
    }

    fn newer(_: void, a: Post, b: Post) bool {
        return switch (a.published.order(b.published)) {
            .gt => true,
            .lt => false,
            .eq => std.mem.lessThan(u8, a.path, b.path),
        };
    }
};

fn parseTags(gpa: std.mem.Allocator, keywords: []const u8) ![]const []const u8 {
    var tags: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitSequence(u8, keywords, ", ");
    while (it.next()) |keyword| {
        if (keyword.len == 0) {
            continue;
        }
        const tag = try std.ascii.allocLowerString(gpa, keyword);
        for (tag) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
                return error.InvalidTag;
            }
        }
        try tags.append(gpa, tag);
    }
    std.mem.sort([]const u8, tags.items, {}, lessThan);
    return dedup(tags.items);
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn dedup(sorted: [][]const u8) [][]const u8 {
    if (sorted.len == 0) {
        return sorted;
    }
    var len: usize = 1;
    for (sorted[1..]) |item| {
        if (!std.mem.eql(u8, item, sorted[len - 1])) {
            sorted[len] = item;
            len += 1;
        }
    }
    return sorted[0..len];
}

fn extractPage(gpa: std.mem.Allocator, head: Head, body: Body) ![]const u8 {
    var page: std.ArrayList(u8) = .empty;
    try head.append(gpa, &page);
    try body.append(gpa, &page);
    return page.toOwnedSlice(gpa);
}

fn readPosts(gpa: std.mem.Allocator, io: std.Io, inputs: std.Io.Dir) ![]Post {
    var dir = try inputs.openDir(io, "posts", .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit(io);
    var posts: std.ArrayList(Post) = .empty;
    errdefer posts.deinit(gpa);
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".typ")) {
            continue;
        }
        const path = try gpa.dupe(u8, entry.path);
        // maybe we put this under post namespace?
        const post = readPost(gpa, io, dir, path) catch |err| {
            std.debug.panic("posts/{s}: {t}", .{ path, err });
        };
        try posts.append(gpa, post);
    }
    std.mem.sort(Post, posts.items, {}, Post.newer);
    return posts.toOwnedSlice(gpa);
}

fn readPost(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8) !Post {
    const name = path[0 .. path.len - ".typ".len];
    const html_path = try std.fmt.allocPrint(gpa, "{s}.html", .{name});
    const json_path = try std.fmt.allocPrint(gpa, "{s}.json", .{name});
    const html = try dir.readFileAlloc(io, html_path, gpa, .unlimited);
    const json = try dir.readFileAlloc(io, json_path, gpa, .unlimited);
    return Post.parse(gpa, path, html, json);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.arena.allocator();
    const args = try init.minimal.args.toSlice(gpa);
    if (args.len != 3) {
        std.debug.panic("usage: {s} <inputs> <site>", .{args[0]});
    }
    var inputs = try std.Io.Dir.cwd().openDir(io, args[1], .{});
    defer inputs.close(io);
    const posts = try readPosts(gpa, io, inputs);
    defer gpa.free(posts);
}

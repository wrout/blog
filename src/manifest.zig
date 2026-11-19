pub const Cache = enum { none, immutable };

pub const File = struct {
    path: []const u8,
    mime: []const u8,
    cache: Cache,
};

pub const Redirect = struct {
    from: []const u8,
    to: []const u8,
};

pub const Manifest = struct {
    files: []const File,
    redirects: []const Redirect,
    not_found: []const u8,
};

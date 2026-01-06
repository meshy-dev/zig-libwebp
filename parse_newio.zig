//! Makefile.am parser for Zig master (uses std.Io API).
//! For Zig 0.15.1, see parse.zig.

const std = @import("std");

allocator: std.mem.Allocator,
io: std.Io,
upstream_path: std.Build.LazyPath,
b: *std.Build,

pub fn init(allocator: std.mem.Allocator, io: std.Io, upstream_path: std.Build.LazyPath, b: *std.Build) @This() {
    return .{ .allocator = allocator, .io = io, .upstream_path = upstream_path, .b = b };
}

pub fn parseMakefileAm(self: @This(), folder: []const u8, var_prefix: []const u8) ![]const []const u8 {
    const upstream_dir = self.upstream_path.getPath(self.b);
    const makefile_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/Makefile.am", .{ upstream_dir, folder });
    defer self.allocator.free(makefile_path);

    const content = try std.Io.Dir.cwd().readFileAlloc(self.io, makefile_path, self.allocator, .limited(std.math.maxInt(usize)));
    defer self.allocator.free(content);

    return parseContent(self.allocator, content, folder, var_prefix);
}

pub fn findSimdFiles(self: @This(), dir_path: []const u8, suffix: []const u8) ![]const []const u8 {
    const upstream_dir = self.upstream_path.getPath(self.b);
    const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ upstream_dir, dir_path });
    defer self.allocator.free(full_path);

    var result: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (result.items) |item| self.allocator.free(item);
        result.deinit(self.allocator);
    }

    var dir = std.Io.Dir.cwd().openDir(self.io, full_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return result.toOwnedSlice(self.allocator),
        else => return err,
    };
    defer dir.close(self.io);

    var iter = dir.iterate();
    while (try iter.next(self.io)) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, suffix)) {
            try result.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir_path, entry.name }));
        }
    }
    return result.toOwnedSlice(self.allocator);
}

fn parseContent(allocator: std.mem.Allocator, content: []const u8, folder: []const u8, var_prefix: []const u8) ![]const []const u8 {
    var var_map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = var_map.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |item| allocator.free(item);
            entry.value_ptr.deinit(allocator);
        }
        var_map.deinit();
    }

    // First pass: collect variable definitions
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.indexOf(u8, trimmed, "_SOURCES") == null) continue;

        const eq_pos = if (std.mem.indexOf(u8, trimmed, " += ")) |pos| pos + 4 else if (std.mem.indexOf(u8, trimmed, "=")) |pos| pos + 1 else continue;
        const var_name = std.mem.trim(u8, trimmed[0 .. eq_pos - 1], " \t");
        const files_str = std.mem.trim(u8, trimmed[eq_pos..], " \t");
        if (files_str.len == 0) continue;

        const idx = std.mem.lastIndexOf(u8, var_name, "_SOURCES") orelse continue;
        const base_var = var_name[0..idx];

        const gop = try var_map.getOrPut(base_var);
        if (!gop.found_existing) gop.value_ptr.* = .empty;

        var remaining = files_str;
        while (remaining.len > 0) {
            remaining = std.mem.trimStart(u8, remaining, " \t");
            if (remaining.len == 0) break;

            if (remaining.len >= 2 and remaining[0] == '$' and remaining[1] == '(') {
                const close = std.mem.indexOfScalar(u8, remaining[2..], ')') orelse break;
                try gop.value_ptr.append(allocator, try allocator.dupe(u8, remaining[0 .. 3 + close]));
                remaining = remaining[3 + close ..];
            } else {
                var end: usize = 0;
                while (end < remaining.len and remaining[end] != ' ') end += 1;
                const file = remaining[0..end];
                remaining = remaining[end..];
                if (std.mem.endsWith(u8, file, ".c")) {
                    try gop.value_ptr.append(allocator, try allocator.dupe(u8, file));
                }
            }
        }
    }

    // Second pass: resolve references
    var result: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    const resolve = struct {
        fn f(alloc: std.mem.Allocator, map: *const std.StringHashMap(std.ArrayList([]const u8)), key: []const u8, vis: *std.StringHashMap(void), res: *std.ArrayList([]const u8)) !void {
            const k = if (std.mem.endsWith(u8, key, "_SOURCES")) key[0 .. key.len - 8] else key;
            if (vis.contains(k)) return;
            try vis.put(k, {});
            if (map.get(k)) |files| {
                for (files.items) |item| {
                    if (item.len >= 3 and item[0] == '$' and item[1] == '(') {
                        const close = std.mem.indexOfScalar(u8, item[2..], ')') orelse continue;
                        try f(alloc, map, item[2 .. 2 + close], vis, res);
                    } else {
                        try res.append(alloc, try alloc.dupe(u8, item));
                    }
                }
            }
        }
    }.f;

    if (var_map.get(var_prefix)) |files| {
        for (files.items) |item| {
            if (item.len >= 3 and item[0] == '$' and item[1] == '(') {
                const close = std.mem.indexOfScalar(u8, item[2..], ')') orelse continue;
                visited.clearRetainingCapacity();
                try resolve(allocator, &var_map, item[2 .. 2 + close], &visited, &result);
            } else {
                try result.append(allocator, try allocator.dupe(u8, item));
            }
        }
    }

    // Prepend folder path
    for (result.items) |*file| {
        const original = file.*;
        file.* = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ folder, original });
        allocator.free(original);
    }

    return result.toOwnedSlice(allocator);
}

const std = @import("std");

/// MakefileScanner for Zig 0.15.1 (uses legacy fs.cwd() API)
/// Encapsulates the allocator and provides methods for parsing Makefile.am files
/// Note: The Io parameter is a stub for API compatibility with parse_newio.zig
pub const MakefileScanner = struct {
    allocator: std.mem.Allocator,
    upstream_path: std.Build.LazyPath,
    b: *std.Build,

    const Self = @This();

    /// Io is a stub type for API compatibility (not used in this version)
    pub const Io = void;

    pub fn init(
        allocator: std.mem.Allocator,
        _: Io, // Unused in legacy version, kept for API compatibility
        upstream_path: std.Build.LazyPath,
        b: *std.Build,
    ) Self {
        return .{
            .allocator = allocator,
            .upstream_path = upstream_path,
            .b = b,
        };
    }

    /// Parse Makefile.am to extract source file lists
    pub fn parseMakefileAm(
        self: Self,
        folder: []const u8,
        var_prefix: []const u8,
    ) ![]const []const u8 {
        // Construct path to Makefile.am
        const upstream_dir = self.upstream_path.getPath(self.b);
        const makefile_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/Makefile.am", .{ upstream_dir, folder });
        defer self.allocator.free(makefile_path);

        // Read file using std.fs.cwd() (Zig 0.15.1 API)
        const makefile_content = try std.fs.cwd().readFileAlloc(self.allocator, makefile_path, std.math.maxInt(usize));
        defer self.allocator.free(makefile_content);

        return parseMakefileContent(self.allocator, makefile_content, folder, var_prefix);
    }

    /// Find SIMD files in a directory
    pub fn findSimdFiles(
        self: Self,
        pattern_dir: []const u8,
        simd_extensions: []const []const u8,
    ) ![]const []const u8 {
        var result: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (result.items) |item| self.allocator.free(item);
            result.deinit(self.allocator);
        }

        const upstream_dir = self.upstream_path.getPath(self.b);
        const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ upstream_dir, pattern_dir });
        defer self.allocator.free(full_path);

        // Open directory using std.fs.cwd() API
        var dir = std.fs.cwd().openDir(full_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return try result.toOwnedSlice(self.allocator),
            else => return err,
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            const name = entry.name;

            // Check if it matches any SIMD extension
            for (simd_extensions) |ext| {
                if (std.mem.endsWith(u8, name, ext)) {
                    const full_file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ pattern_dir, name });
                    try result.append(self.allocator, full_file_path);
                    break;
                }
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }
};

/// Parse Makefile.am content and extract source files (shared parsing logic)
fn parseMakefileContent(
    allocator: std.mem.Allocator,
    makefile_content: []const u8,
    folder: []const u8,
    var_prefix: []const u8,
) ![]const []const u8 {
    // First pass: collect variable definitions
    var var_map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = var_map.iterator();
        while (it.next()) |entry| {
            for (entry.value_ptr.items) |item| allocator.free(item);
            entry.value_ptr.deinit(allocator);
        }
        var_map.deinit();
    }

    var lines = std.mem.splitScalar(u8, makefile_content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Match pattern: VAR_SOURCES = file1.c file2.c
        // or: VAR_SOURCES += file3.c
        if (std.mem.indexOf(u8, trimmed, "_SOURCES") == null) continue;

        var eq_pos: ?usize = null;
        if (std.mem.indexOf(u8, trimmed, " += ")) |pos| {
            eq_pos = pos + 4;
        } else if (std.mem.indexOf(u8, trimmed, "=")) |pos| {
            eq_pos = pos + 1;
        } else {
            continue;
        }

        const eq = eq_pos.?;
        const var_name = std.mem.trim(u8, trimmed[0 .. eq - 1], " \t");
        const files_str = std.mem.trim(u8, trimmed[eq..], " \t");

        if (files_str.len == 0) continue;

        // Extract variable name (before _SOURCES)
        if (std.mem.lastIndexOf(u8, var_name, "_SOURCES")) |idx| {
            const base_var = var_name[0..idx];

            // Get or create the variable list
            const gop = try var_map.getOrPut(base_var);
            if (!gop.found_existing) {
                gop.value_ptr.* = .empty;
            }

            // Parse files from the line - handle both direct files and variable references
            var remaining = files_str;
            while (remaining.len > 0) {
                // Use trimLeft (Zig 0.15.1)
                remaining = std.mem.trimLeft(u8, remaining, " \t");
                if (remaining.len == 0) break;

                // Check if it starts with $( - variable reference
                if (remaining.len >= 2 and remaining[0] == '$' and remaining[1] == '(') {
                    const close_paren = std.mem.indexOfScalar(u8, remaining[2..], ')') orelse break;
                    const var_ref = remaining[0 .. 2 + close_paren + 1];
                    try gop.value_ptr.append(allocator, try allocator.dupe(u8, var_ref));
                    remaining = remaining[2 + close_paren + 1 ..];
                } else {
                    // It's a file name - find the end (space or end of string)
                    var file_end: usize = 0;
                    while (file_end < remaining.len and remaining[file_end] != ' ') {
                        file_end += 1;
                    }
                    const file = remaining[0..file_end];
                    remaining = remaining[file_end..];

                    // Only include .c files
                    if (std.mem.endsWith(u8, file, ".c")) {
                        try gop.value_ptr.append(allocator, try allocator.dupe(u8, file));
                    }
                }
            }
        }
    }

    // Second pass: resolve variable references and extract requested variable
    var result_list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (result_list.items) |item| allocator.free(item);
        result_list.deinit(allocator);
    }

    // Helper function to resolve variable references recursively
    const resolveVar = struct {
        fn f(
            alloc: std.mem.Allocator,
            map: *const std.StringHashMap(std.ArrayList([]const u8)),
            var_name_to_resolve: []const u8,
            visited: *std.StringHashMap(void),
            result: *std.ArrayList([]const u8),
        ) !void {
            // Strip "_SOURCES" suffix if present to match map keys
            var var_key = var_name_to_resolve;
            if (std.mem.endsWith(u8, var_name_to_resolve, "_SOURCES")) {
                var_key = var_name_to_resolve[0 .. var_name_to_resolve.len - "_SOURCES".len];
            }

            if (visited.contains(var_key)) return; // Avoid cycles
            try visited.put(var_key, {});

            if (map.get(var_key)) |files| {
                for (files.items) |item| {
                    // Check if it's a variable reference like $(VAR)
                    if (item.len >= 3 and item[0] == '$' and item[1] == '(') {
                        const close_paren = std.mem.indexOfScalar(u8, item[2..], ')') orelse continue;
                        const ref_var_full = item[2 .. 2 + close_paren];
                        // Strip "_SOURCES" from the reference to match map keys
                        var ref_var = ref_var_full;
                        if (std.mem.endsWith(u8, ref_var_full, "_SOURCES")) {
                            ref_var = ref_var_full[0 .. ref_var_full.len - "_SOURCES".len];
                        }
                        try f(alloc, map, ref_var, visited, result);
                    } else {
                        // It's a real file
                        try result.append(alloc, try alloc.dupe(u8, item));
                    }
                }
            }
        }
    }.f;

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    // Extract files for the requested variable prefix
    // Try the exact match first
    var found = false;
    if (var_map.get(var_prefix)) |files| {
        found = true;
        for (files.items) |item| {
            if (item.len >= 3 and item[0] == '$' and item[1] == '(') {
                const close_paren = std.mem.indexOfScalar(u8, item[2..], ')') orelse continue;
                const ref_var_full = item[2 .. 2 + close_paren];
                visited.clearRetainingCapacity();
                try resolveVar(allocator, &var_map, ref_var_full, &visited, &result_list);
            } else {
                try result_list.append(allocator, try allocator.dupe(u8, item));
            }
        }
    }

    // If not found and doesn't start with "lib", try adding "libwebp" prefix
    if (!found and !std.mem.startsWith(u8, var_prefix, "lib")) {
        const prefixed = try std.fmt.allocPrint(allocator, "libwebp{s}_la", .{var_prefix});
        defer allocator.free(prefixed);
        if (var_map.get(prefixed)) |files| {
            for (files.items) |item| {
                if (item.len >= 3 and item[0] == '$' and item[1] == '(') {
                    const close_paren = std.mem.indexOfScalar(u8, item[2..], ')') orelse continue;
                    const ref_var_full = item[2 .. 2 + close_paren];
                    visited.clearRetainingCapacity();
                    try resolveVar(allocator, &var_map, ref_var_full, &visited, &result_list);
                } else {
                    try result_list.append(allocator, try allocator.dupe(u8, item));
                }
            }
        }
    }

    // Prepend folder path to each file
    for (result_list.items) |*file_ptr| {
        const original = file_ptr.*;
        file_ptr.* = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ folder, original });
        allocator.free(original);
    }

    return try result_list.toOwnedSlice(allocator);
}

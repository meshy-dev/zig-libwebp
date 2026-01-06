const std = @import("std");
const simd = @import("simd.zig");

const Parser = if (@hasDecl(std.fs, "cwd"))
    @import("parse.zig")
else
    @import("parse_newio.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const upstream = b.dependency("libwebp", .{});

    const common_cflags: []const []const u8 = &.{ "-fPIC", "-Wall", "-DHAVE_MALLOC_H" };
    const imageio_cflags: []const []const u8 = &.{ "-fPIC", "-Wall", "-DHAVE_MALLOC_H", "-DWEBP_HAVE_PNG" };

    const io = if (@hasDecl(std.fs, "cwd")) {} else b.graph.io;
    const parser = Parser.init(b.allocator, io, upstream.path(""), b);

    // Core libwebp library
    const webp_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    webp_mod.addIncludePath(upstream.path(""));
    webp_mod.addIncludePath(upstream.path("src"));

    // Parse Makefile.am files for source lists
    const sharpyuv_srcs = try parser.parseMakefileAm("sharpyuv", "libsharpyuv_la");
    const dec_srcs = try parser.parseMakefileAm("src/dec", "libwebpdecode_la");
    const dsp_srcs = try parser.parseMakefileAm("src/dsp", "libwebpdsp_la");
    const enc_srcs = try parser.parseMakefileAm("src/enc", "libwebpencode_la");
    const utils_srcs = try parser.parseMakefileAm("src/utils", "libwebputils_la");

    // Combine plain C sources
    var webp_srcs: std.ArrayList([]const u8) = .empty;
    try webp_srcs.appendSlice(b.allocator, sharpyuv_srcs);
    try webp_srcs.appendSlice(b.allocator, dec_srcs);
    try webp_srcs.appendSlice(b.allocator, dsp_srcs);
    try webp_srcs.appendSlice(b.allocator, enc_srcs);
    try webp_srcs.appendSlice(b.allocator, utils_srcs);

    webp_mod.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = webp_srcs.items,
        .flags = common_cflags,
    });

    // Add SIMD sources with variant-specific flags.
    // All variants for the architecture are included for runtime dispatch.
    for (simd.getVariants(target.result.cpu.arch)) |variant| {
        for (simd.source_dirs) |dir| {
            const files = try parser.findSimdFiles(dir, variant.fileSuffix());
            if (files.len == 0) continue;

            var flags: std.ArrayList([]const u8) = .empty;
            try flags.appendSlice(b.allocator, common_cflags);
            try flags.appendSlice(b.allocator, variant.cflags());

            webp_mod.addCSourceFiles(.{
                .root = upstream.path(""),
                .files = files,
                .flags = flags.items,
            });
        }
    }

    const webp = b.addLibrary(.{ .name = "webp", .linkage = .static, .root_module = webp_mod });
    webp.root_module.addIncludePath(upstream.path("src"));

    // webpdemux library
    const webpdemux_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    webpdemux_mod.addIncludePath(upstream.path(""));
    webpdemux_mod.addIncludePath(upstream.path("src"));
    const demux_srcs = try parser.parseMakefileAm("src/demux", "libwebpdemux_la");
    webpdemux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = demux_srcs, .flags = common_cflags });
    const webpdemux = b.addLibrary(.{ .name = "webpdemux", .linkage = .static, .root_module = webpdemux_mod });

    // webpmux library
    const webpmux_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    webpmux_mod.addIncludePath(upstream.path(""));
    webpmux_mod.addIncludePath(upstream.path("src"));
    const mux_srcs = try parser.parseMakefileAm("src/mux", "libwebpmux_la");
    webpmux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = mux_srcs, .flags = common_cflags });
    const webpmux = b.addLibrary(.{ .name = "webpmux", .linkage = .static, .root_module = webpmux_mod });

    // Example utilities
    const example_util_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    example_util_mod.addIncludePath(upstream.path(""));
    example_util_mod.addIncludePath(upstream.path("src"));
    example_util_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/example_util.c"}, .flags = common_cflags });
    example_util_mod.linkLibrary(webp);
    const example_util = b.addLibrary(.{ .name = "example_util", .linkage = .static, .root_module = example_util_mod });

    const imageio_util_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    imageio_util_mod.addIncludePath(upstream.path(""));
    imageio_util_mod.addIncludePath(upstream.path("src"));
    imageio_util_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"imageio/imageio_util.c"}, .flags = imageio_cflags });
    imageio_util_mod.linkLibrary(webp);
    const imageio_util = b.addLibrary(.{ .name = "imageio_util", .linkage = .static, .root_module = imageio_util_mod });

    const imagedec_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    imagedec_mod.addIncludePath(upstream.path(""));
    imagedec_mod.addIncludePath(upstream.path("src"));
    imagedec_mod.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{ "imageio/image_dec.c", "imageio/jpegdec.c", "imageio/metadata.c", "imageio/pngdec.c", "imageio/pnmdec.c", "imageio/tiffdec.c", "imageio/webpdec.c" },
        .flags = imageio_cflags,
    });
    imagedec_mod.linkLibrary(webpdemux);
    imagedec_mod.linkLibrary(webp);
    const imagedec = b.addLibrary(.{ .name = "imagedec", .linkage = .static, .root_module = imagedec_mod });

    const imageenc_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    imageenc_mod.addIncludePath(upstream.path(""));
    imageenc_mod.addIncludePath(upstream.path("src"));
    imageenc_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"imageio/image_enc.c"}, .flags = imageio_cflags });
    imageenc_mod.linkLibrary(webp);
    imageenc_mod.linkLibrary(imageio_util);
    const imageenc = b.addLibrary(.{ .name = "imageenc", .linkage = .static, .root_module = imageenc_mod });

    // Executables
    const cwebp_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    cwebp_mod.addIncludePath(upstream.path(""));
    cwebp_mod.addIncludePath(upstream.path("src"));
    cwebp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/cwebp.c"}, .flags = imageio_cflags });
    cwebp_mod.linkLibrary(example_util);
    cwebp_mod.linkLibrary(imagedec);
    cwebp_mod.linkLibrary(imageio_util);
    cwebp_mod.linkLibrary(webpdemux);
    cwebp_mod.linkLibrary(webp);
    const cwebp = b.addExecutable(.{ .name = "cwebp", .root_module = cwebp_mod });
    b.installArtifact(cwebp);

    const dwebp_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    dwebp_mod.addIncludePath(upstream.path(""));
    dwebp_mod.addIncludePath(upstream.path("src"));
    dwebp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/dwebp.c"}, .flags = imageio_cflags });
    dwebp_mod.linkLibrary(example_util);
    dwebp_mod.linkLibrary(imagedec);
    dwebp_mod.linkLibrary(imageenc);
    dwebp_mod.linkLibrary(imageio_util);
    dwebp_mod.linkLibrary(webpdemux);
    dwebp_mod.linkLibrary(webp);
    const dwebp = b.addExecutable(.{ .name = "dwebp", .root_module = dwebp_mod });
    b.installArtifact(dwebp);

    const webpmux_example_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    webpmux_example_mod.addIncludePath(upstream.path(""));
    webpmux_example_mod.addIncludePath(upstream.path("src"));
    webpmux_example_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/webpmux.c"}, .flags = imageio_cflags });
    webpmux_example_mod.linkLibrary(example_util);
    webpmux_example_mod.linkLibrary(imageio_util);
    webpmux_example_mod.linkLibrary(webpmux);
    webpmux_example_mod.linkLibrary(webp);
    const webpmux_example = b.addExecutable(.{ .name = "webpmux_example", .root_module = webpmux_example_mod });
    b.installArtifact(webpmux_example);

    const img2webp_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    img2webp_mod.addIncludePath(upstream.path(""));
    img2webp_mod.addIncludePath(upstream.path("src"));
    img2webp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/img2webp.c"}, .flags = imageio_cflags });
    img2webp_mod.linkLibrary(example_util);
    img2webp_mod.linkLibrary(imagedec);
    img2webp_mod.linkLibrary(imageio_util);
    img2webp_mod.linkLibrary(webpmux);
    img2webp_mod.linkLibrary(webpdemux);
    img2webp_mod.linkLibrary(webp);
    const img2webp = b.addExecutable(.{ .name = "img2webp", .root_module = img2webp_mod });
    b.installArtifact(img2webp);

    const webpinfo_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    webpinfo_mod.addIncludePath(upstream.path(""));
    webpinfo_mod.addIncludePath(upstream.path("src"));
    webpinfo_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{"examples/webpinfo.c"}, .flags = imageio_cflags });
    webpinfo_mod.linkLibrary(example_util);
    webpinfo_mod.linkLibrary(imageio_util);
    webpinfo_mod.linkLibrary(webp);
    const webpinfo = b.addExecutable(.{ .name = "webpinfo", .root_module = webpinfo_mod });
    b.installArtifact(webpinfo);

    // Link zlib and libpng
    const z_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    const png_dep = b.dependency("libpng", .{ .target = target, .optimize = optimize });

    for ([_]*std.Build.Module{ imagedec_mod, imageenc_mod, imageio_util_mod, cwebp_mod, dwebp_mod, webpmux_example_mod, img2webp_mod, webpinfo_mod }) |mod| {
        mod.linkLibrary(z_dep.artifact("z"));
        mod.linkLibrary(png_dep.artifact("png"));
        mod.addIncludePath(png_dep.path(""));
    }

    // Install libraries and headers
    b.installArtifact(webp);
    b.installArtifact(webpdemux);
    b.installArtifact(webpmux);
    webp.installHeadersDirectory(upstream.path("src/webp"), "webp", .{ .include_extensions = &.{".h"} });
}

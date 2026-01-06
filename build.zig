const std = @import("std");

// Import appropriate parsing module based on Zig version
// Zig 0.15.1 has std.fs.cwd(), Zig master uses new Io API
const parse = if (@hasDecl(std.fs, "cwd"))
    @import("parse.zig")
else
    @import("parse_newio.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("libwebp", .{});

    var common_flags: std.ArrayList([]const u8) = .empty;
    defer common_flags.deinit(b.allocator);
    try common_flags.appendSlice(b.allocator, &.{
        "-fPIC",
        "-Wall",
        "-DHAVE_MALLOC_H",
    });

    // Create scanner instance - handles version-specific I/O
    // For Zig 0.15.1: io parameter is ignored (void)
    // For Zig master: io parameter is b.graph.io
    const io = if (@hasDecl(std.fs, "cwd")) {} else b.graph.io;
    const scanner = parse.MakefileScanner.init(
        b.allocator,
        io,
        upstream.path(""),
        b,
    );

    // Core libwebp static library
    const webp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    webp_mod.addIncludePath(upstream.path(""));
    webp_mod.addIncludePath(upstream.path("src"));
    webp_mod.addIncludePath(b.path(""));

    // Parse Makefile.am files to extract source lists
    const sharpyuv_srcs = try scanner.parseMakefileAm("sharpyuv", "libsharpyuv_la");
    defer b.allocator.free(sharpyuv_srcs);

    const dec_srcs = try scanner.parseMakefileAm("src/dec", "libwebpdecode_la");
    defer b.allocator.free(dec_srcs);

    // Parse DSP sources - libwebpdsp_la includes COMMON and ENC sources
    const dsp_srcs = try scanner.parseMakefileAm("src/dsp", "libwebpdsp_la");
    defer b.allocator.free(dsp_srcs);

    const enc_srcs = try scanner.parseMakefileAm("src/enc", "libwebpencode_la");
    defer b.allocator.free(enc_srcs);

    // Parse utils sources - libwebputils_la includes COMMON and ENC sources
    const utils_srcs = try scanner.parseMakefileAm("src/utils", "libwebputils_la");
    defer b.allocator.free(utils_srcs);

    // Combine all sources
    var webp_srcs: std.ArrayList([]const u8) = .empty;
    defer webp_srcs.deinit(b.allocator);
    try webp_srcs.appendSlice(b.allocator, sharpyuv_srcs);
    try webp_srcs.appendSlice(b.allocator, dec_srcs);
    try webp_srcs.appendSlice(b.allocator, dsp_srcs);
    try webp_srcs.appendSlice(b.allocator, enc_srcs);
    try webp_srcs.appendSlice(b.allocator, utils_srcs);

    // Also include SIMD files via glob patterns (similar to CMake approach)
    // These are defined in separate library targets in Makefile.am but need to be included
    const simd_patterns = [_][]const u8{ "sharpyuv", "src/dsp" };
    const simd_extensions = [_][]const u8{ "_sse2.c", "_sse41.c", "_avx2.c", "_neon.c", "_mips32.c", "_mips_dsp_r2.c", "_msa.c" };

    for (simd_patterns) |pattern_dir| {
        const simd_files = try scanner.findSimdFiles(pattern_dir, &simd_extensions);
        defer b.allocator.free(simd_files);
        try webp_srcs.appendSlice(b.allocator, simd_files);
    }

    webp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = try webp_srcs.toOwnedSlice(b.allocator), .flags = common_flags.items });
    const webp = b.addLibrary(.{
        .name = "webp",
        .linkage = .static,
        .root_module = webp_mod,
    });
    // Expose webp headers for consumers (e.g., #include <webp/decode.h>)
    webp.root_module.addIncludePath(upstream.path("src"));

    // webpdemux static library
    const webpdemux_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    webpdemux_mod.addIncludePath(upstream.path(""));
    webpdemux_mod.addIncludePath(upstream.path("src"));
    const demux_srcs = try scanner.parseMakefileAm("src/demux", "libwebpdemux_la");
    defer b.allocator.free(demux_srcs);
    webpdemux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = demux_srcs, .flags = common_flags.items });
    const webpdemux = b.addLibrary(.{
        .name = "webpdemux",
        .linkage = .static,
        .root_module = webpdemux_mod,
    });

    // webpmux static library
    const webpmux_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    webpmux_mod.addIncludePath(upstream.path(""));
    webpmux_mod.addIncludePath(upstream.path("src"));
    const mux_srcs = try scanner.parseMakefileAm("src/mux", "libwebpmux_la");
    defer b.allocator.free(mux_srcs);
    webpmux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = mux_srcs, .flags = common_flags.items });
    const webpmux = b.addLibrary(.{
        .name = "webpmux",
        .linkage = .static,
        .root_module = webpmux_mod,
    });

    // Support libraries for examples
    const example_util_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    example_util_mod.addIncludePath(upstream.path(""));
    example_util_mod.addIncludePath(upstream.path("src"));
    example_util_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/example_util.c",
    }, .flags = common_flags.items });
    example_util_mod.linkLibrary(webp);
    const example_util = b.addLibrary(.{
        .name = "example_util",
        .linkage = .static,
        .root_module = example_util_mod,
    });

    var imageio_flags: std.ArrayList([]const u8) = .empty;
    defer imageio_flags.deinit(b.allocator);
    try imageio_flags.appendSlice(b.allocator, common_flags.items);
    try imageio_flags.appendSlice(b.allocator, &.{"-DWEBP_HAVE_PNG"});

    const imageio_util_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    imageio_util_mod.addIncludePath(upstream.path(""));
    imageio_util_mod.addIncludePath(upstream.path("src"));
    imageio_util_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/imageio_util.c",
    }, .flags = imageio_flags.items });
    imageio_util_mod.linkLibrary(webp);
    const imageio_util = b.addLibrary(.{
        .name = "imageio_util",
        .linkage = .static,
        .root_module = imageio_util_mod,
    });

    const imagedec_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    imagedec_mod.addIncludePath(upstream.path(""));
    imagedec_mod.addIncludePath(upstream.path("src"));
    imagedec_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/image_dec.c",
        "imageio/jpegdec.c",
        "imageio/metadata.c",
        "imageio/pngdec.c",
        "imageio/pnmdec.c",
        "imageio/tiffdec.c",
        "imageio/webpdec.c",
    }, .flags = imageio_flags.items });
    imagedec_mod.linkLibrary(webpdemux);
    imagedec_mod.linkLibrary(webp);
    const imagedec = b.addLibrary(.{
        .name = "imagedec",
        .linkage = .static,
        .root_module = imagedec_mod,
    });

    const imageenc_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    imageenc_mod.addIncludePath(upstream.path(""));
    imageenc_mod.addIncludePath(upstream.path("src"));
    imageenc_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/image_enc.c",
    }, .flags = imageio_flags.items });
    imageenc_mod.linkLibrary(webp);
    imageenc_mod.linkLibrary(imageio_util);
    const imageenc = b.addLibrary(.{
        .name = "imageenc",
        .linkage = .static,
        .root_module = imageenc_mod,
    });

    // Executables
    const cwebp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    cwebp_mod.addIncludePath(upstream.path(""));
    cwebp_mod.addIncludePath(upstream.path("src"));
    cwebp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/cwebp.c",
    }, .flags = imageio_flags.items });
    cwebp_mod.linkLibrary(example_util);
    cwebp_mod.linkLibrary(imagedec);
    cwebp_mod.linkLibrary(imageio_util);
    cwebp_mod.linkLibrary(webpdemux);
    cwebp_mod.linkLibrary(webp);
    const cwebp = b.addExecutable(.{
        .name = "cwebp",
        .root_module = cwebp_mod,
    });
    b.installArtifact(cwebp);

    const dwebp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dwebp_mod.addIncludePath(upstream.path(""));
    dwebp_mod.addIncludePath(upstream.path("src"));
    dwebp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/dwebp.c",
    }, .flags = imageio_flags.items });
    dwebp_mod.linkLibrary(example_util);
    dwebp_mod.linkLibrary(imagedec);
    dwebp_mod.linkLibrary(imageenc);
    dwebp_mod.linkLibrary(imageio_util);
    dwebp_mod.linkLibrary(webpdemux);
    dwebp_mod.linkLibrary(webp);
    const dwebp = b.addExecutable(.{
        .name = "dwebp",
        .root_module = dwebp_mod,
    });
    b.installArtifact(dwebp);

    const webpmux_example_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    webpmux_example_mod.addIncludePath(upstream.path(""));
    webpmux_example_mod.addIncludePath(upstream.path("src"));
    webpmux_example_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/webpmux.c",
    }, .flags = imageio_flags.items });
    webpmux_example_mod.linkLibrary(example_util);
    webpmux_example_mod.linkLibrary(imageio_util);
    webpmux_example_mod.linkLibrary(webpmux);
    webpmux_example_mod.linkLibrary(webp);
    const webpmux_example = b.addExecutable(.{
        .name = "webpmux_example",
        .root_module = webpmux_example_mod,
    });
    b.installArtifact(webpmux_example);

    const img2webp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    img2webp_mod.addIncludePath(upstream.path(""));
    img2webp_mod.addIncludePath(upstream.path("src"));
    img2webp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/img2webp.c",
    }, .flags = imageio_flags.items });
    img2webp_mod.linkLibrary(example_util);
    img2webp_mod.linkLibrary(imagedec);
    img2webp_mod.linkLibrary(imageio_util);
    img2webp_mod.linkLibrary(webpmux);
    img2webp_mod.linkLibrary(webpdemux);
    img2webp_mod.linkLibrary(webp);
    const img2webp = b.addExecutable(.{
        .name = "img2webp",
        .root_module = img2webp_mod,
    });
    b.installArtifact(img2webp);

    const webpinfo_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    webpinfo_mod.addIncludePath(upstream.path(""));
    webpinfo_mod.addIncludePath(upstream.path("src"));
    webpinfo_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/webpinfo.c",
    }, .flags = imageio_flags.items });
    webpinfo_mod.linkLibrary(example_util);
    webpinfo_mod.linkLibrary(imageio_util);
    webpinfo_mod.linkLibrary(webp);
    const webpinfo = b.addExecutable(.{
        .name = "webpinfo",
        .root_module = webpinfo_mod,
    });
    b.installArtifact(webpinfo);

    // Link against zlib and libpng for imageio where applicable.
    const z_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    const png_dep = b.dependency("libpng", .{ .target = target, .optimize = optimize });

    // imageio requires system libs when available: png, jpeg, tiff. We provide png via dependency.
    for ([_]*std.Build.Module{ imagedec_mod, imageenc_mod, imageio_util_mod, cwebp_mod, dwebp_mod, webpmux_example_mod, img2webp_mod, webpinfo_mod }) |mod| {
        mod.linkLibrary(z_dep.artifact("z"));
        mod.linkLibrary(png_dep.artifact("png"));
        mod.addIncludePath(png_dep.path(""));
    }

    // Install core libraries and headers.
    b.installArtifact(webp);
    b.installArtifact(webpdemux);
    b.installArtifact(webpmux);

    webp.installHeadersDirectory(upstream.path("src/webp"), "webp", .{ .include_extensions = &.{".h"} });
}

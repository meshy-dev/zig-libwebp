const std = @import("std");

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

    // Core libwebp static library
    const webp_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    webp_mod.addIncludePath(upstream.path(""));
    webp_mod.addIncludePath(upstream.path("src"));
    webp_mod.addIncludePath(b.path(""));

    webp_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = webp_srcs, .flags = common_flags.items });
    const webp = b.addLibrary(.{
        .name = "webp",
        .linkage = .static,
        .root_module = webp_mod,
    });

    // webpdemux static library
    const webpdemux_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    webpdemux_mod.addIncludePath(upstream.path(""));
    webpdemux_mod.addIncludePath(upstream.path("src"));
    webpdemux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "src/demux/anim_decode.c",
        "src/demux/demux.c",
    }, .flags = common_flags.items });
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
    webpmux_mod.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "src/mux/anim_encode.c",
        "src/mux/muxedit.c",
        "src/mux/muxinternal.c",
        "src/mux/muxread.c",
    }, .flags = common_flags.items });
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

    webp.installHeadersDirectory(upstream.path("src"), "webp", .{ .include_extensions = &.{".h"} });
}

const webp_srcs: []const []const u8 = &.{
    // sharpyuv
    "sharpyuv/sharpyuv.c",
    "sharpyuv/sharpyuv_cpu.c",
    "sharpyuv/sharpyuv_csp.c",
    "sharpyuv/sharpyuv_dsp.c",
    "sharpyuv/sharpyuv_gamma.c",
    "sharpyuv/sharpyuv_neon.c",
    "sharpyuv/sharpyuv_sse2.c",
    // dec
    "src/dec/alpha_dec.c",
    "src/dec/buffer_dec.c",
    "src/dec/frame_dec.c",
    "src/dec/idec_dec.c",
    "src/dec/io_dec.c",
    "src/dec/quant_dec.c",
    "src/dec/tree_dec.c",
    "src/dec/vp8_dec.c",
    "src/dec/vp8l_dec.c",
    "src/dec/webp_dec.c",
    // dsp decoder/encoder/common
    "src/dsp/alpha_processing.c",
    "src/dsp/alpha_processing_mips_dsp_r2.c",
    "src/dsp/alpha_processing_neon.c",
    "src/dsp/alpha_processing_sse2.c",
    "src/dsp/alpha_processing_sse41.c",
    "src/dsp/cpu.c",
    "src/dsp/dec.c",
    "src/dsp/dec_clip_tables.c",
    "src/dsp/dec_mips32.c",
    "src/dsp/dec_mips_dsp_r2.c",
    "src/dsp/dec_msa.c",
    "src/dsp/dec_neon.c",
    "src/dsp/dec_sse2.c",
    "src/dsp/dec_sse41.c",
    "src/dsp/filters.c",
    "src/dsp/filters_mips_dsp_r2.c",
    "src/dsp/filters_msa.c",
    "src/dsp/filters_neon.c",
    "src/dsp/filters_sse2.c",
    "src/dsp/lossless.c",
    "src/dsp/lossless_mips_dsp_r2.c",
    "src/dsp/lossless_msa.c",
    "src/dsp/lossless_neon.c",
    "src/dsp/lossless_sse2.c",
    "src/dsp/lossless_sse41.c",
    "src/dsp/lossless_avx2.c",
    "src/dsp/rescaler.c",
    "src/dsp/rescaler_mips32.c",
    "src/dsp/rescaler_mips_dsp_r2.c",
    "src/dsp/rescaler_msa.c",
    "src/dsp/rescaler_neon.c",
    "src/dsp/rescaler_sse2.c",
    "src/dsp/ssim.c",
    "src/dsp/ssim_sse2.c",
    "src/dsp/upsampling.c",
    "src/dsp/upsampling_mips_dsp_r2.c",
    "src/dsp/upsampling_msa.c",
    "src/dsp/upsampling_neon.c",
    "src/dsp/upsampling_sse2.c",
    "src/dsp/upsampling_sse41.c",
    "src/dsp/yuv.c",
    "src/dsp/yuv_mips32.c",
    "src/dsp/yuv_mips_dsp_r2.c",
    "src/dsp/yuv_neon.c",
    "src/dsp/yuv_sse2.c",
    "src/dsp/yuv_sse41.c",
    // utils
    "src/utils/bit_reader_utils.c",
    "src/utils/bit_writer_utils.c",
    "src/utils/color_cache_utils.c",
    "src/utils/huffman_encode_utils.c",
    "src/utils/filters_utils.c",
    "src/utils/huffman_utils.c",
    "src/utils/palette.c",
    "src/utils/quant_levels_dec_utils.c",
    "src/utils/quant_levels_utils.c",
    "src/utils/random_utils.c",
    "src/utils/rescaler_utils.c",
    "src/utils/thread_utils.c",
    "src/utils/utils.c",
    // dsp enc
    "src/dsp/cost.c",
    "src/dsp/cost_mips32.c",
    "src/dsp/cost_mips_dsp_r2.c",
    "src/dsp/cost_neon.c",
    "src/dsp/cost_sse2.c",
    "src/dsp/enc.c",
    "src/dsp/enc_mips32.c",
    "src/dsp/enc_mips_dsp_r2.c",
    "src/dsp/enc_msa.c",
    "src/dsp/enc_neon.c",
    "src/dsp/enc_sse2.c",
    "src/dsp/enc_sse41.c",
    "src/dsp/lossless_enc.c",
    "src/dsp/lossless_enc_mips32.c",
    "src/dsp/lossless_enc_mips_dsp_r2.c",
    "src/dsp/lossless_enc_msa.c",
    "src/dsp/lossless_enc_neon.c",
    "src/dsp/lossless_enc_sse2.c",
    "src/dsp/lossless_enc_sse41.c",
    "src/dsp/lossless_enc_avx2.c",
    // encoder
    "src/enc/alpha_enc.c",
    "src/enc/analysis_enc.c",
    "src/enc/backward_references_cost_enc.c",
    "src/enc/backward_references_enc.c",
    "src/enc/config_enc.c",
    "src/enc/cost_enc.c",
    "src/enc/filter_enc.c",
    "src/enc/frame_enc.c",
    "src/enc/histogram_enc.c",
    "src/enc/iterator_enc.c",
    "src/enc/near_lossless_enc.c",
    "src/enc/picture_csp_enc.c",
    "src/enc/picture_enc.c",
    "src/enc/picture_psnr_enc.c",
    "src/enc/picture_rescale_enc.c",
    "src/enc/picture_tools_enc.c",
    "src/enc/predictor_enc.c",
    "src/enc/quant_enc.c",
    "src/enc/syntax_enc.c",
    "src/enc/token_enc.c",
    "src/enc/tree_enc.c",
    "src/enc/vp8l_enc.c",
    "src/enc/webp_enc.c",
};

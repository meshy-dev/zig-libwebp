const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("libwebp", .{});

    // Core libwebp static library
    const webp = b.addLibrary(.{
        .name = "webp",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    webp.addIncludePath(upstream.path(""));
    webp.addIncludePath(upstream.path("src"));
    webp.addIncludePath(b.path(""));

    var common_flags: std.ArrayList([]const u8) = .empty;
    defer common_flags.deinit(b.allocator);
    try common_flags.appendSlice(b.allocator, &.{
        "-fPIC",
        "-Wall",
        "-DHAVE_MALLOC_H",
    });

    webp.addCSourceFiles(.{ .root = upstream.path(""), .files = webp_srcs, .flags = common_flags.items });

    // webpdemux static library
    const webpdemux = b.addLibrary(.{
        .name = "webpdemux",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    webpdemux.addIncludePath(upstream.path(""));
    webpdemux.addIncludePath(upstream.path("src"));
    webpdemux.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "src/demux/anim_decode.c",
        "src/demux/demux.c",
    }, .flags = common_flags.items });

    // webpmux static library
    const webpmux = b.addLibrary(.{
        .name = "webpmux",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    webpmux.addIncludePath(upstream.path(""));
    webpmux.addIncludePath(upstream.path("src"));
    webpmux.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "src/mux/anim_encode.c",
        "src/mux/muxedit.c",
        "src/mux/muxinternal.c",
        "src/mux/muxread.c",
    }, .flags = common_flags.items });

    // Support libraries for examples
    const example_util = b.addLibrary(.{
        .name = "example_util",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    example_util.addIncludePath(upstream.path(""));
    example_util.addIncludePath(upstream.path("src"));
    example_util.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/example_util.c",
    }, .flags = common_flags.items });
    example_util.linkLibrary(webp);

    const imageio_util = b.addLibrary(.{
        .name = "imageio_util",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    imageio_util.addIncludePath(upstream.path(""));
    imageio_util.addIncludePath(upstream.path("src"));
    var imageio_flags: std.ArrayList([]const u8) = .empty;
    defer imageio_flags.deinit(b.allocator);
    try imageio_flags.appendSlice(b.allocator, common_flags.items);
    try imageio_flags.appendSlice(b.allocator, &.{"-DWEBP_HAVE_PNG"});
    imageio_util.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/imageio_util.c",
    }, .flags = imageio_flags.items });
    imageio_util.linkLibrary(webp);

    const imagedec = b.addLibrary(.{
        .name = "imagedec",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    imagedec.addIncludePath(upstream.path(""));
    imagedec.addIncludePath(upstream.path("src"));
    imagedec.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/image_dec.c",
        "imageio/jpegdec.c",
        "imageio/metadata.c",
        "imageio/pngdec.c",
        "imageio/pnmdec.c",
        "imageio/tiffdec.c",
        "imageio/webpdec.c",
    }, .flags = imageio_flags.items });
    imagedec.linkLibrary(webpdemux);
    imagedec.linkLibrary(webp);

    const imageenc = b.addLibrary(.{
        .name = "imageenc",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    imageenc.addIncludePath(upstream.path(""));
    imageenc.addIncludePath(upstream.path("src"));
    imageenc.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "imageio/image_enc.c",
    }, .flags = imageio_flags.items });
    imageenc.linkLibrary(webp);
    imageenc.linkLibrary(imageio_util);

    // Executables
    const cwebp = b.addExecutable(.{
        .name = "cwebp",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    cwebp.root_module.addIncludePath(upstream.path(""));
    cwebp.root_module.addIncludePath(upstream.path("src"));
    cwebp.root_module.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/cwebp.c",
    }, .flags = imageio_flags.items });
    cwebp.root_module.linkLibrary(example_util);
    cwebp.root_module.linkLibrary(imagedec);
    cwebp.root_module.linkLibrary(imageio_util);
    cwebp.root_module.linkLibrary(webpdemux);
    cwebp.root_module.linkLibrary(webp);
    b.installArtifact(cwebp);

    const dwebp = b.addExecutable(.{
        .name = "dwebp",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    dwebp.root_module.addIncludePath(upstream.path(""));
    dwebp.root_module.addIncludePath(upstream.path("src"));
    dwebp.root_module.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/dwebp.c",
    }, .flags = imageio_flags.items });
    dwebp.root_module.linkLibrary(example_util);
    dwebp.root_module.linkLibrary(imagedec);
    dwebp.root_module.linkLibrary(imageenc);
    dwebp.root_module.linkLibrary(imageio_util);
    dwebp.root_module.linkLibrary(webpdemux);
    dwebp.root_module.linkLibrary(webp);
    b.installArtifact(dwebp);

    const webpmux_example = b.addExecutable(.{
        .name = "webpmux_example",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    webpmux_example.root_module.addIncludePath(upstream.path(""));
    webpmux_example.root_module.addIncludePath(upstream.path("src"));
    webpmux_example.root_module.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/webpmux.c",
    }, .flags = imageio_flags.items });
    webpmux_example.root_module.linkLibrary(example_util);
    webpmux_example.root_module.linkLibrary(imageio_util);
    webpmux_example.root_module.linkLibrary(webpmux);
    webpmux_example.root_module.linkLibrary(webp);
    b.installArtifact(webpmux_example);

    const img2webp = b.addExecutable(.{
        .name = "img2webp",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    img2webp.root_module.addIncludePath(upstream.path(""));
    img2webp.root_module.addIncludePath(upstream.path("src"));
    img2webp.root_module.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/img2webp.c",
    }, .flags = imageio_flags.items });
    img2webp.root_module.linkLibrary(example_util);
    img2webp.root_module.linkLibrary(imagedec);
    img2webp.root_module.linkLibrary(imageio_util);
    img2webp.root_module.linkLibrary(webpmux);
    img2webp.root_module.linkLibrary(webpdemux);
    img2webp.root_module.linkLibrary(webp);
    b.installArtifact(img2webp);

    const webpinfo = b.addExecutable(.{
        .name = "webpinfo",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    webpinfo.root_module.addIncludePath(upstream.path(""));
    webpinfo.root_module.addIncludePath(upstream.path("src"));
    webpinfo.root_module.addCSourceFiles(.{ .root = upstream.path(""), .files = &.{
        "examples/webpinfo.c",
    }, .flags = imageio_flags.items });
    webpinfo.root_module.linkLibrary(example_util);
    webpinfo.root_module.linkLibrary(imageio_util);
    webpinfo.root_module.linkLibrary(webp);
    b.installArtifact(webpinfo);

    // Link against zlib and libpng for imageio where applicable.
    const z_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    const png_dep = b.dependency("libpng", .{ .target = target, .optimize = optimize });

    // imageio requires system libs when available: png, jpeg, tiff. We provide png via dependency.
    for ([_]*std.Build.Step.Compile{ imagedec, imageenc, imageio_util, cwebp, dwebp, webpmux_example, img2webp, webpinfo }) |comp| {
        comp.linkLibrary(z_dep.artifact("z"));
        comp.linkLibrary(png_dep.artifact("png"));
        comp.addIncludePath(png_dep.path(""));
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

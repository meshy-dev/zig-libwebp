const std = @import("std");

/// SIMD variant definitions matching upstream WebP library structure.
/// Each variant corresponds to a separate static library in the upstream build
/// (e.g., libwebpdsp_sse2.la, libwebpdsp_neon.la, etc.)
pub const Variant = enum {
    sse2,
    sse41,
    avx2,
    neon,
    msa,
    mips32,
    mips_dsp_r2,

    pub fn fileSuffix(self: Variant) []const u8 {
        return switch (self) {
            .sse2 => "_sse2.c",
            .sse41 => "_sse41.c",
            .avx2 => "_avx2.c",
            .neon => "_neon.c",
            .msa => "_msa.c",
            .mips32 => "_mips32.c",
            .mips_dsp_r2 => "_mips_dsp_r2.c",
        };
    }

    pub fn cflags(self: Variant) []const []const u8 {
        return switch (self) {
            .sse2 => &.{ "-msse2", "-DWEBP_HAVE_SSE2" },
            .sse41 => &.{ "-msse4.1", "-DWEBP_HAVE_SSE41" },
            .avx2 => &.{ "-mavx2", "-DWEBP_HAVE_AVX2" },
            .neon => &.{"-DWEBP_HAVE_NEON"},
            .msa => &.{ "-mmsa", "-DWEBP_HAVE_MSA" },
            .mips32 => &.{},
            .mips_dsp_r2 => &.{ "-mdspr2", "-DWEBP_HAVE_MIPS_DSP_R2" },
        };
    }
};

/// Directories containing SIMD source files.
pub const source_dirs = [_][]const u8{ "sharpyuv", "src/dsp" };

/// Returns applicable SIMD variants for a given CPU architecture.
pub fn getVariants(arch: std.Target.Cpu.Arch) []const Variant {
    return switch (arch) {
        .x86, .x86_64 => &.{ .sse2, .sse41, .avx2 },
        .arm, .armeb, .aarch64, .aarch64_be => &.{.neon},
        .mips, .mipsel => &.{ .mips32, .mips_dsp_r2, .msa },
        .mips64, .mips64el => &.{.msa},
        else => &.{},
    };
}

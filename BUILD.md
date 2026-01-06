# WebP Zig Build System - Porting Documentation

This document details how the Zig build system for libwebp translates the upstream autotools/CMake build, handles SIMD runtime dispatch, and provides pointers to relevant upstream source code for future maintenance.

## Table of Contents

1. [Overview](#overview)
2. [Makefile.am Parsing](#makefileam-parsing)
3. [SIMD Runtime Dispatch](#simd-runtime-dispatch)
4. [Cross-Version Zig Compatibility](#cross-version-zig-compatibility)
5. [Maintenance Checklist](#maintenance-checklist)

---

## Overview

The Zig build system replicates the upstream autotools build by:

1. **Parsing `Makefile.am` files** to extract source file lists dynamically
2. **Compiling SIMD variants** with appropriate per-variant compiler flags
3. **Linking all variants** into a single library that performs runtime CPU dispatch

This approach ensures the Zig build stays synchronized with upstream source changes without manual file list maintenance.

### Supported Zig Versions

| Version | Status | Notes |
|---------|--------|-------|
| Zig 0.15.1 | ✅ Supported | Stable release |
| Zig master | ✅ Supported | Tested against `0.16.0-dev.1976+8e091047b` |

---

## Makefile.am Parsing

### How It Works

The upstream build defines source files in `Makefile.am` files using autotools conventions. Our parser (`parse.zig` / `parse_newio.zig`) extracts these definitions by:

1. Reading the `Makefile.am` file
2. Matching lines containing `_SOURCES`
3. Resolving variable references like `$(COMMON_SOURCES)`
4. Returning a list of `.c` files with their folder prefix

### Upstream Reference: Makefile.am Structure

**File**: `src/dsp/Makefile.am` (example)
```makefile
libwebpdsp_la_SOURCES = $(COMMON_SOURCES) $(ENC_SOURCES)
COMMON_SOURCES = cpu.c dsp.h lossless.c lossless.h ...
ENC_SOURCES = cost.c enc.c lossless_enc.c ...
```

**File**: `CMakeLists.txt` — CMake's equivalent parsing logic:
```cmake
function(parse_makefile_am folder var_name)
  file(READ ${folder}/Makefile.am content)
  string(REGEX MATCHALL "${var_name}_SOURCES[ ]*\\+?=[ ]+[^\n]+" ...
```

### Component Makefile Locations

| Component | Upstream File | Variable Prefix | Zig Usage |
|-----------|---------------|-----------------|-----------|
| SharpYUV | `sharpyuv/Makefile.am` | `libsharpyuv_la` | `scanner.parseMakefileAm("sharpyuv", "libsharpyuv_la")` |
| Decoder | `src/dec/Makefile.am` | `libwebpdecode_la` | `scanner.parseMakefileAm("src/dec", "libwebpdecode_la")` |
| DSP | `src/dsp/Makefile.am` | `libwebpdsp_la` | `scanner.parseMakefileAm("src/dsp", "libwebpdsp_la")` |
| Encoder | `src/enc/Makefile.am` | `libwebpencode_la` | `scanner.parseMakefileAm("src/enc", "libwebpencode_la")` |
| Utils | `src/utils/Makefile.am` | `libwebputils_la` | `scanner.parseMakefileAm("src/utils", "libwebputils_la")` |
| Demux | `src/demux/Makefile.am` | `libwebpdemux_la` | `scanner.parseMakefileAm("src/demux", "libwebpdemux_la")` |
| Mux | `src/mux/Makefile.am` | `libwebpmux_la` | `scanner.parseMakefileAm("src/mux", "libwebpmux_la")` |

---

## SIMD Runtime Dispatch

WebP uses **runtime CPU dispatch** to select optimal SIMD implementations. This section explains the mechanism and why all SIMD variants must be compiled.

### Dispatch Architecture

```
                    ┌─────────────────────────────────────┐
                    │     VP8DspInit() / VP8LDspInit()    │
                    │         (called once at startup)    │
                    └─────────────────┬───────────────────┘
                                      │
                    ┌─────────────────┴───────────────────┐
                    │         VP8GetCPUInfo(kSSE2)        │
                    │         VP8GetCPUInfo(kSSE4_1)      │
                    │         VP8GetCPUInfo(kAVX2)        │
                    └─────────────────┬───────────────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          ▼                           ▼                           ▼
   VP8DspInitSSE2()          VP8DspInitSSE41()          VP8LDspInitAVX2()
   (assigns function          (overwrites with           (overwrites with
    pointers)                  better impl)               best impl)
```

### Upstream Reference: CPU Detection

**File**: `src/dsp/cpu.c` — CPU feature detection implementation
```c
VP8CPUInfo VP8GetCPUInfo = NULL;  // Function pointer set at runtime

// x86: Uses CPUID instruction
// ARM: Checks /proc/cpuinfo or hwcap  
// MIPS: Checks /proc/cpuinfo
```

**File**: `src/dsp/cpu.h` — Feature constants
```c
typedef enum {
  kSSE2,
  kSSE3,
  kSlowSSSE3,
  kSSE4_1,
  kAVX,
  kAVX2,
  kNEON,
  // ...
} CPUFeature;
```

### Why All SIMD Variants Must Be Compiled

The dispatch code in plain C files **unconditionally references** all SIMD init functions when the corresponding `WEBP_HAVE_*` macro is defined.

**Upstream Reference**: `src/dsp/dec.c` lines 821-827
```c
#if defined(WEBP_HAVE_SSE2)
    if (VP8GetCPUInfo(kSSE2)) {
      VP8DspInitSSE2();           // ← Always referenced
#if defined(WEBP_HAVE_SSE41)
      if (VP8GetCPUInfo(kSSE4_1)) {
        VP8DspInitSSE41();        // ← Nested inside SSE2 block
```

This means:
- Even with `-Dcpu=x86_64_v3` (AVX2 baseline), SSE2 init is still referenced
- The linker requires all init functions to be present
- **All SIMD variants for the architecture must be compiled**

### SIMD Variant Definitions

Defined in `simd.zig` as `simd.Variant`, mirroring upstream structure.

**Upstream Reference**: `src/dsp/Makefile.am` — SIMD library definitions
```makefile
libwebpdsp_sse2_la_SOURCES = cost_sse2.c enc_sse2.c ...
libwebpdsp_sse2_la_CFLAGS = $(AM_CFLAGS) $(SSE2_FLAGS)
libwebpdsp_sse41_la_SOURCES = enc_sse41.c lossless_enc_sse41.c ...
libwebpdsp_sse41_la_CFLAGS = $(AM_CFLAGS) $(SSE41_FLAGS)
```

**Upstream Reference**: `cmake/cpu.cmake` — Flag definitions
```cmake
set(SSE2_FLAGS "-msse2")
set(SSE41_FLAGS "-msse4.1")
set(AVX2_FLAGS "-mavx2")
```

| Variant | File Suffix | Compiler Flags | Define Macro |
|---------|-------------|----------------|--------------|
| SSE2 | `_sse2.c` | `-msse2` | `WEBP_HAVE_SSE2` |
| SSE4.1 | `_sse41.c` | `-msse4.1` | `WEBP_HAVE_SSE41` |
| AVX2 | `_avx2.c` | `-mavx2` | `WEBP_HAVE_AVX2` |
| NEON | `_neon.c` | (implicit on aarch64) | `WEBP_HAVE_NEON` |
| MSA | `_msa.c` | `-mmsa` | `WEBP_HAVE_MSA` |
| MIPS32 | `_mips32.c` | (implicit) | — |
| MIPS DSP R2 | `_mips_dsp_r2.c` | `-mdspr2` | `WEBP_HAVE_MIPS_DSP_R2` |

### DSP Initialization Entry Points

**Upstream Reference**: Each DSP module has an init function that sets up dispatch.

| Upstream File | Init Function | Purpose |
|---------------|---------------|---------|
| `src/dsp/dec.c` | `VP8DspInit()` | Decoder DSP dispatch |
| `src/dsp/enc.c` | `VP8EncDspInit()` | Encoder DSP dispatch |
| `src/dsp/lossless.c` | `VP8LDspInit()` | Lossless decoder dispatch |
| `src/dsp/lossless_enc.c` | `VP8LEncDspInit()` | Lossless encoder dispatch |
| `src/dsp/upsampling.c` | `WebPInitUpsamplers()` | Upsampling dispatch |
| `src/dsp/yuv.c` | `WebPInitSamplers()` | YUV conversion dispatch |
| `src/dsp/filters.c` | `VP8FiltersInit()` | Filter dispatch |
| `src/dsp/rescaler.c` | `WebPRescalerDspInit()` | Rescaler dispatch |
| `src/dsp/alpha_processing.c` | `WebPInitAlphaProcessing()` | Alpha dispatch |
| `src/dsp/cost.c` | `VP8EncDspCostInit()` | Encoder cost dispatch |
| `src/dsp/ssim.c` | `VP8SSIMDspInit()` | SSIM dispatch |
| `sharpyuv/sharpyuv_dsp.c` | `SharpYuvInitDsp()` | SharpYUV dispatch |

### Zig Build Implementation

```zig
// From build.zig — compile each SIMD variant with appropriate flags
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
            .flags = flags.items,  // e.g., ["-msse4.1", "-DWEBP_HAVE_SSE41"]
        });
    }
}
```

### Build Options

| Option | Description |
|--------|-------------|
| `-Dtarget=<triple>` | Cross-compilation target (e.g., `aarch64-linux`) |
| `-Dcpu=<cpu>` | Target CPU baseline (e.g., `x86_64_v3`) |
| `-Doptimize=<mode>` | Optimization level (`Debug`, `ReleaseFast`, etc.) |

**Note**: The `-Dcpu` option affects baseline code optimization but does NOT affect SIMD variant availability. All variants for the architecture are always included for runtime dispatch.

---

## Cross-Version Zig Compatibility

The build supports both Zig 0.15.1 and Zig master through conditional imports based on API availability.

### Detection Mechanism

```zig
// build.zig — detect Zig version by checking for removed API
const parse = if (@hasDecl(std.fs, "cwd"))
    @import("parse.zig")      // Zig 0.15.1: has std.fs.cwd()
else
    @import("parse_newio.zig"); // Zig master: uses std.Io API
```

### API Differences

**Zig 0.15.1** (`parse.zig`):
```zig
// File reading
const content = try std.fs.cwd().readFileAlloc(allocator, path, max_size);

// Directory iteration
var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
var iter = dir.iterate();
while (try iter.next()) |entry| { ... }
```

**Zig master 0.16.0-dev.1976+8e091047b** (`parse_newio.zig`):
```zig
// File reading — requires Io handle
const content = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max));

// Directory iteration — Io handle passed to each operation
var dir = try Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
var iter = dir.iterate();
while (try iter.next(io)) |entry| { ... }
```

### Scanner Interface

Both modules are file-level structs (Zig files are implicit structs) with identical interfaces:

```zig
// parse.zig / parse_newio.zig - the file IS the struct
allocator: std.mem.Allocator,
io: std.Io,  // or Io = void for 0.15.1
upstream_path: std.Build.LazyPath,
b: *std.Build,

pub fn init(allocator: Allocator, io: Io, upstream_path: LazyPath, b: *Build) @This();
pub fn parseMakefileAm(self: @This(), folder: []const u8, var_prefix: []const u8) ![]const []const u8;
pub fn findSimdFiles(self: @This(), dir_path: []const u8, suffix: []const u8) ![]const []const u8;
```

Usage in `build.zig`:
```zig
const Parser = if (@hasDecl(std.fs, "cwd")) @import("parse.zig") else @import("parse_newio.zig");
const parser = Parser.init(b.allocator, io, upstream.path(""), b);
```

For Zig 0.15.1, the `Io` type is a stub (`void`) that's ignored.

---

## Maintenance Checklist

### Updating for New Upstream Releases

1. **Check for new source files**: Run build and verify no missing symbols
2. **Check for new SIMD variants**: Look for new `*_<simd>.c` file patterns in `src/dsp/`
3. **Check Makefile.am changes**: Verify variable names haven't changed
4. **Test architectures**: x86_64, aarch64, and MIPS if possible
5. **Test optimization modes**: `Debug`, `ReleaseFast`, `ReleaseSafe`

### Adding a New SIMD Variant

1. Add to `Variant` enum in `simd.zig`:
   ```zig
   pub const Variant = enum {
       sse2, sse41, avx2, avx512,  // ← add new variant
       // ...
   };
   ```

2. Implement the two method cases:
   ```zig
   pub fn fileSuffix(self: Variant) []const u8 {
       return switch (self) {
           .avx512 => "_avx512.c",  // ← add case
           // ...
       };
   }
   
   pub fn cflags(self: Variant) []const []const u8 {
       return switch (self) {
           .avx512 => &.{ "-mavx512f", "-mavx512bw", "-DWEBP_HAVE_AVX512" },  // ← add case
           // ...
       };
   }
   ```

3. Update `getVariants()`:
   ```zig
   pub fn getVariants(arch: std.Target.Cpu.Arch) []const Variant {
       return switch (arch) {
           .x86, .x86_64 => &.{ .sse2, .sse41, .avx2, .avx512 },  // ← add
           // ...
       };
   }
   ```

4. The build will automatically pick up files matching the new suffix pattern.

### Updating for New Zig Versions

If Zig's I/O APIs change again:

1. Check if `std.fs.cwd()` still exists (version detection mechanism)
2. If APIs changed, create a new parser module or update `parse_newio.zig`
3. Update the version detection in `build.zig` if needed
4. Update the "Supported Zig Versions" table in this document

---

## References

- **libwebp repository**: https://chromium.googlesource.com/webm/libwebp
- **WebP documentation**: https://developers.google.com/speed/webp
- **Zig build system**: https://ziglang.org/documentation/master/#Build-System

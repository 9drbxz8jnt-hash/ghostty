//! A zig builder step that runs "libtool" against a list of libraries
//! in order to create a single combined static library.
//!
//! Implementation note (Apple cctools 1266.8 workaround):
//! Apple's `libtool -static -o out.a in1.a in2.a ...` silently drops
//! members from later archives when their basenames collide with members
//! already present from earlier archives. Concretely, when merging
//! `libghostty.a` and the dependency archives that ship with Ghostty,
//! every imgui object file can be dropped from the merged archive, leaving
//! the macOS app link step with undefined `_ImGui_*` symbols.
//!
//! libtool does NOT dedup individual `.o` inputs by basename, only
//! archive-of-archive members. So we pre-extract each input `.a` into a
//! unique scratch directory and feed libtool the resulting `.o` files
//! directly. Non-`.a` inputs are passed through unchanged.
const LibtoolStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    /// The name of this step.
    name: []const u8,

    /// The filename (not the path) of the file to create. This will
    /// be placed in a unique hashed directory. Use out_path to access.
    out_name: []const u8,

    /// Library files (.a) to combine.
    sources: []LazyPath,
};

/// The step to depend on.
step: *Step,

/// The output file from the libtool run.
output: LazyPath,

// Wrapper script run via `/bin/sh -c`. Positional args:
//   $0 = script tag
//   $1 = output archive path
//   $2.. = input files (.a archives or raw .o objects)
const wrapper_script =
    \\set -eu
    \\output_path="$1"; shift
    \\orig_pwd="$PWD"
    \\abspath() {
    \\    case "$1" in
    \\        /*) printf '%s\n' "$1" ;;
    \\        *)  printf '%s\n' "$orig_pwd/$1" ;;
    \\    esac
    \\}
    \\scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/ghostty-libtool.XXXXXXXX")"
    \\trap 'rm -rf "$scratch_root"' EXIT
    \\i=0
    \\for input in "$@"; do
    \\    i=$((i + 1))
    \\    dir="$scratch_root/in$i"
    \\    mkdir -p "$dir"
    \\    abs_input="$(abspath "$input")"
    \\    case "$abs_input" in
    \\        *.a)
    \\            (cd "$dir" && ar -x "$abs_input" && chmod u+r ./*)
    \\            ;;
    \\        *)
    \\            cp "$abs_input" "$dir/"
    \\            ;;
    \\    esac
    \\done
    \\find "$scratch_root" -type f \( -name '*.o' -o -name '*.obj' \) -print0 \
    \\    | xargs -0 libtool -static -o "$output_path"
;

/// Run libtool against a list of library files to combine into a single
/// static library.
pub fn create(b: *std.Build, opts: Options) *LibtoolStep {
    const self = b.allocator.create(LibtoolStep) catch @panic("OOM");

    const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
    run_step.addArgs(&.{ "/bin/sh", "-c", wrapper_script, "ghostty-libtool" });
    const output = run_step.addOutputFileArg(opts.out_name);
    for (opts.sources, 0..) |source, i| {
        run_step.addFileArg(normalizeArchive(
            b,
            opts.name,
            opts.out_name,
            i,
            source,
        ));
    }

    self.* = .{
        .step = &run_step.step,
        .output = output,
    };

    return self;
}

fn normalizeArchive(
    b: *std.Build,
    step_name: []const u8,
    out_name: []const u8,
    index: usize,
    source: LazyPath,
) LazyPath {
    // Newer Xcode libtool can drop 64-bit archive members if the input
    // archive layout doesn't match what it expects. ranlib rewrites the
    // archive without flattening members through the filesystem, so we
    // normalize each source archive first. This is a Zig/toolchain
    // interoperability workaround, not a Ghostty archive format change.
    const run_step = RunStep.create(
        b,
        b.fmt("ranlib {s} #{d}", .{ step_name, index }),
    );
    run_step.addArgs(&.{
        "/bin/sh",
        "-c",
        "/bin/cp \"$1\" \"$2\" && /usr/bin/ranlib \"$2\"",
        "_",
    });
    run_step.addFileArg(source);
    return run_step.addOutputFileArg(b.fmt("{d}-{s}", .{ index, out_name }));
}

const std = @import("std");
const render = @import("render.zig");

const Allocator = std.mem.Allocator;
const Cell = render.RenderState.Cell;

pub const Projection = struct {
    cells: std.MultiArrayList(Cell),
    visual_to_logical: []usize,
    logical_to_visual: []usize,

    pub fn deinit(self: *Projection, allocator: Allocator) void {
        self.cells.deinit(allocator);
        allocator.free(self.visual_to_logical);
        allocator.free(self.logical_to_visual);
        self.* = undefined;
    }
};

pub const BaseDirection = enum {
    ltr,
    rtl,
};

pub const Options = struct {
    base_direction: ?BaseDirection = null,
    align_end: bool = false,
};

const Run = struct {
    start: usize,
    end: usize,
    rtl: bool,
};

pub fn projectCells(
    allocator: Allocator,
    cells: std.MultiArrayList(Cell).Slice,
    width: usize,
) Allocator.Error!?Projection {
    return projectCellsWithOptions(allocator, cells, width, .{});
}

pub fn projectCellsWithOptions(
    allocator: Allocator,
    cells: std.MultiArrayList(Cell).Slice,
    width: usize,
    options: Options,
) Allocator.Error!?Projection {
    const cells_len = @min(cells.len, width);
    if (cells_len == 0) return null;

    const raw = cells.items(.raw);
    const visible_end = visibleEnd(raw[0..cells_len]);
    if (visible_end == 0) return null;

    const base_direction = options.base_direction orelse
        detectBaseDirectionFromRaw(raw[0..visible_end]) orelse return null;
    const has_rtl = hasStrongRtl(raw[0..visible_end]);
    if (!has_rtl and !(options.align_end and base_direction == .rtl)) return null;

    var runs: std.ArrayList(Run) = .empty;
    defer runs.deinit(allocator);

    var i: usize = 0;
    while (i < visible_end) {
        const rtl = isRtlCandidate(raw[i].codepoint());
        const start = i;
        i += 1;
        while (i < visible_end and isRtlCandidate(raw[i].codepoint()) == rtl) {
            i += 1;
        }
        try runs.append(allocator, .{
            .start = start,
            .end = i,
            .rtl = rtl,
        });
    }

    var out: std.MultiArrayList(Cell) = .empty;
    errdefer out.deinit(allocator);
    try out.resize(allocator, cells_len);
    var out_slice = out.slice();

    const visual_to_logical = try allocator.alloc(usize, cells_len);
    errdefer allocator.free(visual_to_logical);
    const logical_to_visual = try allocator.alloc(usize, cells_len);
    errdefer allocator.free(logical_to_visual);
    for (0..cells_len) |idx| {
        visual_to_logical[idx] = idx;
        logical_to_visual[idx] = idx;
    }

    var visual_x: usize = if (options.align_end) cells_len - visible_end else 0;
    if (options.align_end) {
        for (visible_end..cells_len, 0..) |source_x, dest_x| {
            copyCell(cells, &out_slice, dest_x, source_x);
            visual_to_logical[dest_x] = source_x;
            logical_to_visual[source_x] = dest_x;
        }
    }

    if (base_direction == .rtl) {
        var run_i = runs.items.len;
        while (run_i > 0) {
            run_i -= 1;
            appendRun(cells, &out_slice, visual_to_logical, logical_to_visual, runs.items[run_i], &visual_x);
        }
    } else {
        for (runs.items) |run| {
            appendRun(cells, &out_slice, visual_to_logical, logical_to_visual, run, &visual_x);
        }
    }

    if (!options.align_end) {
        for (visible_end..cells_len) |source_x| {
            copyCell(cells, &out_slice, source_x, source_x);
            visual_to_logical[source_x] = source_x;
            logical_to_visual[source_x] = source_x;
        }
    }

    return .{
        .cells = out,
        .visual_to_logical = visual_to_logical,
        .logical_to_visual = logical_to_visual,
    };
}

pub fn detectBaseDirection(cells: std.MultiArrayList(Cell).Slice, width: usize) ?BaseDirection {
    const cells_len = @min(cells.len, width);
    if (cells_len == 0) return null;

    const raw = cells.items(.raw);
    const visible_end = visibleEnd(raw[0..cells_len]);
    if (visible_end == 0) return null;

    return detectBaseDirectionFromRaw(raw[0..visible_end]);
}

pub fn isStrongRtl(cp: u21) bool {
    return (cp >= 0x0590 and cp <= 0x08FF) or
        (cp >= 0xFB1D and cp <= 0xFDFF) or
        (cp >= 0xFE70 and cp <= 0xFEFF);
}

pub fn isStrongLtr(cp: u21) bool {
    return (cp >= 'A' and cp <= 'Z') or
        (cp >= 'a' and cp <= 'z');
}

pub fn isRtlCandidate(cp: u21) bool {
    return isStrongRtl(cp);
}

fn detectBaseDirectionFromRaw(cells: []const @import("page.zig").Cell) ?BaseDirection {
    for (cells) |cell| {
        const cp = cell.codepoint();
        if (isStrongRtl(cp)) return .rtl;
        if (isStrongLtr(cp)) return .ltr;
    }
    return null;
}

fn hasStrongRtl(cells: []const @import("page.zig").Cell) bool {
    for (cells) |cell| {
        if (isStrongRtl(cell.codepoint())) return true;
    }
    return false;
}

fn visibleEnd(cells: []const @import("page.zig").Cell) usize {
    var i = cells.len;
    while (i > 0) {
        i -= 1;
        if (!cells[i].isEmpty()) return i + 1;
    }
    return 0;
}

fn appendRun(
    source: std.MultiArrayList(Cell).Slice,
    out: *std.MultiArrayList(Cell).Slice,
    visual_to_logical: []usize,
    logical_to_visual: []usize,
    run: Run,
    visual_x: *usize,
) void {
    if (run.rtl) {
        var i = run.end;
        while (i > run.start) {
            i -= 1;
            appendCell(source, out, visual_to_logical, logical_to_visual, i, visual_x);
        }
    } else {
        for (run.start..run.end) |i| {
            appendCell(source, out, visual_to_logical, logical_to_visual, i, visual_x);
        }
    }
}

fn appendCell(
    source: std.MultiArrayList(Cell).Slice,
    out: *std.MultiArrayList(Cell).Slice,
    visual_to_logical: []usize,
    logical_to_visual: []usize,
    source_x: usize,
    visual_x: *usize,
) void {
    copyCell(source, out, visual_x.*, source_x);
    visual_to_logical[visual_x.*] = source_x;
    logical_to_visual[source_x] = visual_x.*;
    visual_x.* += 1;
}

fn copyCell(
    source: std.MultiArrayList(Cell).Slice,
    out: *std.MultiArrayList(Cell).Slice,
    dest_x: usize,
    source_x: usize,
) void {
    const raw = source.items(.raw)[source_x];
    out.set(dest_x, .{
        .raw = raw,
        .grapheme = if (raw.hasGrapheme()) source.items(.grapheme)[source_x] else undefined,
        .style = if (raw.hasStyling()) source.items(.style)[source_x] else undefined,
    });
}

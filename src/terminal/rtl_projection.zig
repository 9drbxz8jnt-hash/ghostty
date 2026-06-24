const std = @import("std");
const render = @import("render.zig");
const uucode = @import("uucode");

const Allocator = std.mem.Allocator;
const Cell = render.RenderState.Cell;
const PageCell = @import("page.zig").Cell;

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

const BidiType = enum {
    l,
    r,
    al,
    en,
    an,
    es,
    et,
    cs,
    nsm,
    neutral,
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

    const visual_order = try buildVisualOrder(allocator, raw[0..visible_end], base_direction);
    defer allocator.free(visual_order);

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

    for (visual_order) |source_x| {
        appendCell(cells, &out_slice, visual_to_logical, logical_to_visual, source_x, &visual_x);
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
    return switch (bidiType(cp)) {
        .r, .al => true,
        else => false,
    };
}

pub fn isStrongLtr(cp: u21) bool {
    return bidiType(cp) == .l;
}

pub fn isRtlCandidate(cp: u21) bool {
    return isStrongRtl(cp);
}

fn detectBaseDirectionFromRaw(cells: []const PageCell) ?BaseDirection {
    if (startsWithListMarker(cells) and hasStrongRtl(cells)) return .rtl;

    for (cells) |cell| {
        switch (bidiType(cell.codepoint())) {
            .r, .al => return .rtl,
            .l => return .ltr,
            else => {},
        }
    }
    return null;
}

fn startsWithListMarker(cells: []const PageCell) bool {
    var i: usize = 0;
    while (i < cells.len and cells[i].codepoint() == ' ') i += 1;
    if (i >= cells.len) return false;

    const first = cells[i].codepoint();
    switch (first) {
        '-', '*', '+', 0x2022 => {
            const after_marker = i + 1;
            return after_marker >= cells.len or cells[after_marker].codepoint() == ' ';
        },
        '0'...'9' => {
            i += 1;
            while (i < cells.len) : (i += 1) {
                switch (cells[i].codepoint()) {
                    '0'...'9' => {},
                    '.', ')' => {
                        const after_marker = i + 1;
                        return after_marker >= cells.len or cells[after_marker].codepoint() == ' ';
                    },
                    else => return false,
                }
            }
            return false;
        },
        else => return false,
    }
}

fn hasStrongRtl(cells: []const PageCell) bool {
    for (cells) |cell| {
        if (isStrongRtl(cell.codepoint())) return true;
    }
    return false;
}

fn visibleEnd(cells: []const PageCell) usize {
    var i = cells.len;
    while (i > 0) {
        i -= 1;
        if (!cells[i].isEmpty()) return i + 1;
    }
    return 0;
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

fn buildVisualOrder(
    allocator: Allocator,
    cells: []const PageCell,
    base_direction: BaseDirection,
) Allocator.Error![]usize {
    const types = try resolveTypes(allocator, cells, base_direction);
    defer allocator.free(types);

    const levels = try allocator.alloc(u8, cells.len);
    defer allocator.free(levels);
    for (types, levels) |typ, *level| {
        level.* = switch (base_direction) {
            .ltr => switch (typ) {
                .l => 0,
                .r => 1,
                .en, .an => 2,
                else => 0,
            },
            .rtl => switch (typ) {
                .r => 1,
                .l, .en, .an => 2,
                else => 1,
            },
        };
    }

    const order = try allocator.alloc(usize, cells.len);
    for (order, 0..) |*idx, i| idx.* = i;

    var max_level: u8 = 0;
    var min_odd_level: ?u8 = null;
    for (levels) |level| {
        max_level = @max(max_level, level);
        if (level % 2 == 1) {
            min_odd_level = if (min_odd_level) |min_level|
                @min(min_level, level)
            else
                level;
        }
    }

    const lowest_odd = min_odd_level orelse return order;
    var level = max_level + 1;
    while (level > lowest_odd) {
        level -= 1;
        reverseRunsAtLevel(order, levels, level);
    }

    return order;
}

fn resolveTypes(
    allocator: Allocator,
    cells: []const PageCell,
    base_direction: BaseDirection,
) Allocator.Error![]BidiType {
    const types = try allocator.alloc(BidiType, cells.len);
    errdefer allocator.free(types);

    for (cells, types) |cell, *typ| typ.* = bidiType(cell.codepoint());

    const base_type: BidiType = switch (base_direction) {
        .ltr => .l,
        .rtl => .r,
    };

    // W1: nonspacing marks inherit the previous type, or the paragraph base.
    for (types, 0..) |typ, i| {
        if (typ == .nsm) types[i] = if (i == 0) base_type else types[i - 1];
    }

    // W2: European numbers after Arabic letters become Arabic numbers.
    for (types, 0..) |typ, i| {
        if (typ != .en) continue;
        var j = i;
        while (j > 0) {
            j -= 1;
            switch (types[j]) {
                .al => {
                    types[i] = .an;
                    break;
                },
                .l, .r => break,
                else => {},
            }
        }
    }

    // W3: Arabic letters resolve to the RTL strong type.
    for (types) |*typ| {
        if (typ.* == .al) typ.* = .r;
    }

    // W4: number separators between like numbers become part of the number.
    if (types.len >= 3) {
        for (1..types.len - 1) |i| {
            switch (types[i]) {
                .es => if (types[i - 1] == .en and types[i + 1] == .en) {
                    types[i] = .en;
                },
                .cs => {
                    if (types[i - 1] == .en and types[i + 1] == .en) {
                        types[i] = .en;
                    } else if (types[i - 1] == .an and types[i + 1] == .an) {
                        types[i] = .an;
                    }
                },
                else => {},
            }
        }
    }

    // W5: European terminators adjacent to European numbers join the number.
    var i: usize = 0;
    while (i < types.len) {
        if (types[i] != .et) {
            i += 1;
            continue;
        }

        const start = i;
        while (i < types.len and types[i] == .et) i += 1;

        const prev_is_en = start > 0 and types[start - 1] == .en;
        const next_is_en = i < types.len and types[i] == .en;
        if (prev_is_en or next_is_en) {
            for (types[start..i]) |*typ| typ.* = .en;
        }
    }

    // W6: leftover separators and terminators are neutral.
    for (types) |*typ| {
        switch (typ.*) {
            .es, .et, .cs => typ.* = .neutral,
            else => {},
        }
    }

    // W7: European numbers after LTR strong text become LTR.
    for (types, 0..) |typ, idx| {
        if (typ != .en) continue;
        var j = idx;
        while (j > 0) {
            j -= 1;
            switch (types[j]) {
                .l => {
                    types[idx] = .l;
                    break;
                },
                .r => break,
                else => {},
            }
        }
    }

    resolveNeutrals(types, base_direction);
    return types;
}

fn resolveNeutrals(types: []BidiType, base_direction: BaseDirection) void {
    var i: usize = 0;
    while (i < types.len) {
        if (!isNeutral(types[i])) {
            i += 1;
            continue;
        }

        const start = i;
        while (i < types.len and isNeutral(types[i])) i += 1;

        const left = directionBefore(types, start);
        const right = directionAfter(types, i);
        const resolved = if (left != null and right != null and left.? == right.?)
            left.?
        else
            base_direction;
        const resolved_type: BidiType = switch (resolved) {
            .ltr => .l,
            .rtl => .r,
        };
        for (types[start..i]) |*typ| typ.* = resolved_type;
    }
}

fn reverseRunsAtLevel(order: []usize, levels: []const u8, level: u8) void {
    var i: usize = 0;
    while (i < order.len) {
        if (levels[order[i]] < level) {
            i += 1;
            continue;
        }

        const start = i;
        while (i < order.len and levels[order[i]] >= level) i += 1;
        std.mem.reverse(usize, order[start..i]);
    }
}

fn directionBefore(types: []const BidiType, index: usize) ?BaseDirection {
    var i = index;
    while (i > 0) {
        i -= 1;
        if (strongishDirection(types[i])) |direction| return direction;
    }
    return null;
}

fn directionAfter(types: []const BidiType, index: usize) ?BaseDirection {
    var i = index;
    while (i < types.len) : (i += 1) {
        if (strongishDirection(types[i])) |direction| return direction;
    }
    return null;
}

fn strongishDirection(typ: BidiType) ?BaseDirection {
    return switch (typ) {
        .l => .ltr,
        .r, .en, .an => .rtl,
        else => null,
    };
}

fn isNeutral(typ: BidiType) bool {
    return switch (typ) {
        .neutral => true,
        else => false,
    };
}

fn bidiType(cp: u21) BidiType {
    return switch (uucode.get(.bidi_class, cp)) {
        .left_to_right => .l,
        .right_to_left => .r,
        .right_to_left_arabic => .al,
        .european_number => .en,
        .arabic_number => .an,
        .european_number_separator => .es,
        .european_number_terminator => .et,
        .common_number_separator => .cs,
        .nonspacing_mark => .nsm,
        else => .neutral,
    };
}

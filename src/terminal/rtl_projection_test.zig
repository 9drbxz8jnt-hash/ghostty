const std = @import("std");
const page = @import("page.zig");
const render = @import("render.zig");
const rtl_projection = @import("rtl_projection.zig");

const testing = std.testing;
const Cell = render.RenderState.Cell;

fn makeCells(allocator: std.mem.Allocator, codepoints: []const u21, width: usize) !std.MultiArrayList(Cell) {
    var cells: std.MultiArrayList(Cell) = .empty;
    errdefer cells.deinit(allocator);
    try cells.resize(allocator, width);

    var slice = cells.slice();
    for (0..width) |i| {
        slice.items(.raw)[i] = if (i < codepoints.len) page.Cell.init(codepoints[i]) else .{};
        slice.items(.grapheme)[i] = undefined;
        slice.items(.style)[i] = undefined;
    }

    return cells;
}

fn expectCodepoints(actual: []const page.Cell, expected: []const u21) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| {
        try testing.expectEqual(want, got.codepoint());
    }
}

test "rtl projection keeps embedded ltr token order" {
    const logical = [_]u21{
        0x0645, 0x0647, 0x0627, 0x0631, 0x0629,
        ' ',    's',    'y',    's',    't',
        'e',    'm',    'a',    't',    'i',
        'c',    '-',    'd',    'e',    'b',
        'u',    'g',    'g',    'i',    'n',
        'g',    ' ',    0x062A, 0x0639, 0x0645,
        0x0644,
    };
    const expected = [_]u21{
        0x0644, 0x0645, 0x0639, 0x062A,
        ' ',    's',    'y',    's',
        't',    'e',    'm',    'a',
        't',    'i',    'c',    '-',
        'd',    'e',    'b',    'u',
        'g',    'g',    'i',    'n',
        'g',    ' ',    0x0629, 0x0631,
        0x0627, 0x0647, 0x0645,
    };

    var cells = try makeCells(testing.allocator, &logical, logical.len);
    defer cells.deinit(testing.allocator);

    var projection = (try rtl_projection.projectCells(testing.allocator, cells.slice(), logical.len)).?;
    defer projection.deinit(testing.allocator);

    try expectCodepoints(projection.cells.slice().items(.raw), &expected);
}

test "rtl projection returns null for ascii rows" {
    const logical = [_]u21{ 'e', 'c', 'h', 'o', ' ', '-', '-', 'h', 'e', 'l', 'p' };

    var cells = try makeCells(testing.allocator, &logical, logical.len);
    defer cells.deinit(testing.allocator);

    try testing.expectEqual(
        @as(?rtl_projection.Projection, null),
        try rtl_projection.projectCells(testing.allocator, cells.slice(), logical.len),
    );
}

test "rtl projection reverses arabic only rows" {
    const logical = [_]u21{ 0x0645, 0x0631, 0x062D, 0x0628, 0x0627 };
    const expected = [_]u21{ 0x0627, 0x0628, 0x062D, 0x0631, 0x0645 };

    var cells = try makeCells(testing.allocator, &logical, logical.len);
    defer cells.deinit(testing.allocator);

    var projection = (try rtl_projection.projectCells(testing.allocator, cells.slice(), logical.len)).?;
    defer projection.deinit(testing.allocator);

    try expectCodepoints(projection.cells.slice().items(.raw), &expected);
}

test "rtl projection preserves trailing empty cells" {
    const logical = [_]u21{ 0x0645, 0x0631, 0x062D, 0x0628, 0x0627 };
    const expected = [_]u21{ 0x0627, 0x0628, 0x062D, 0x0631, 0x0645, 0, 0, 0 };

    var cells = try makeCells(testing.allocator, &logical, expected.len);
    defer cells.deinit(testing.allocator);

    var projection = (try rtl_projection.projectCells(testing.allocator, cells.slice(), expected.len)).?;
    defer projection.deinit(testing.allocator);

    try expectCodepoints(projection.cells.slice().items(.raw), &expected);
}

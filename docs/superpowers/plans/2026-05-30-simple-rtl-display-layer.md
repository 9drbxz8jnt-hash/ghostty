# Simple RTL Display Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a minimal display-only RTL projection on fresh Ghostty `v1.3.1` without porting the old full BiDi engine.

**Architecture:** Keep terminal storage logical. Add a small projection helper that only affects the cells handed to the renderer. Rows with no strong RTL codepoint keep the existing fast path. Rows with Arabic/Hebrew text are projected into visual order while preserving ASCII/LTR tokens such as commands, paths, and flags.

**Tech Stack:** Zig 0.15.2, Ghostty renderer `src/renderer/generic.zig`, terminal render cells `src/terminal/render.zig`, targeted `zig build test -Dtest-filter=... -Demit-macos-app=false`.

---

### Task 1: Add Projection Tests

**Files:**
- Create: `src/terminal/rtl_projection_test.zig`
- Modify: `src/terminal/main.zig`

- [ ] **Step 1: Add a failing test for mixed Arabic and English**

Create `src/terminal/rtl_projection_test.zig` with tests that build `terminal.RenderState.Cell` rows from codepoints and expect this visual order:

```zig
test "rtl projection keeps embedded ltr token order" {
    const testing = std.testing;
    const rtl_projection = @import("rtl_projection.zig");
    const page = @import("page.zig");

    const logical = [_]u21{
        0x0645, 0x0647, 0x0627, 0x0631, 0x0629,
        ' ', 's', 'y', 's', 't', 'e', 'm', 'a', 't', 'i', 'c',
        '-', 'd', 'e', 'b', 'u', 'g', 'g', 'i', 'n', 'g',
        ' ', 0x062A, 0x0639, 0x0645, 0x0644,
    };
    const expected = [_]u21{
        0x0644, 0x0645, 0x0639, 0x062A,
        ' ', 's', 'y', 's', 't', 'e', 'm', 'a', 't', 'i', 'c',
        '-', 'd', 'e', 'b', 'u', 'g', 'g', 'i', 'n', 'g',
        ' ', 0x0629, 0x0631, 0x0627, 0x0647, 0x0645,
    };

    var cells: std.MultiArrayList(@import("render.zig").RenderState.Cell) = .empty;
    defer cells.deinit(testing.allocator);
    try cells.resize(testing.allocator, logical.len);

    var slice = cells.slice();
    for (logical, 0..) |cp, i| {
        slice.items(.raw)[i] = page.Cell.init(cp);
        slice.items(.grapheme)[i] = undefined;
        slice.items(.style)[i] = undefined;
    }

    var projection = (try rtl_projection.projectCells(testing.allocator, cells.slice(), logical.len)).?;
    defer projection.deinit(testing.allocator);

    const visual_raw = projection.cells.slice().items(.raw);
    for (expected, visual_raw[0..expected.len]) |want, got| {
        try testing.expectEqual(want, got.codepoint());
    }
}
```

- [ ] **Step 2: Add fast-path tests**

In the same file, add tests for:
- pure ASCII returns `null`
- Arabic-only returns reversed visual cells
- trailing empty cells preserve the row width

- [ ] **Step 3: Wire tests into terminal test graph**

Modify `src/terminal/main.zig` test block:

```zig
_ = @import("rtl_projection_test.zig");
```

- [ ] **Step 4: Verify RED**

Run:

```bash
zig build test -Dtest-filter="rtl projection" -Demit-macos-app=false
```

Expected: FAIL because `src/terminal/rtl_projection.zig` does not exist yet.

### Task 2: Implement Minimal Projection Helper

**Files:**
- Create: `src/terminal/rtl_projection.zig`

- [ ] **Step 1: Add `Projection` result type**

Implement:

```zig
pub const Projection = struct {
    cells: std.MultiArrayList(terminal.RenderState.Cell),
    visual_to_logical: []usize,
    logical_to_visual: []usize,

    pub fn deinit(self: *Projection, allocator: Allocator) void {
        self.cells.deinit(allocator);
        allocator.free(self.visual_to_logical);
        allocator.free(self.logical_to_visual);
        self.* = undefined;
    }
};
```

- [ ] **Step 2: Add codepoint classification**

Implement `isStrongRtl`, `isStrongLtr`, and `isRtlCandidate`. Keep the ranges conservative:

```zig
pub fn isStrongRtl(cp: u21) bool {
    return (cp >= 0x0590 and cp <= 0x08FF) or
        (cp >= 0xFB1D and cp <= 0xFDFF) or
        (cp >= 0xFE70 and cp <= 0xFEFF);
}
```

Use ASCII letters and digits as strong LTR. Treat spaces and punctuation as neutral.

- [ ] **Step 3: Add `projectCells`**

Implement:

```zig
pub fn projectCells(
    allocator: Allocator,
    cells: std.MultiArrayList(terminal.RenderState.Cell).Slice,
    width: usize,
) Allocator.Error!?Projection
```

Behavior:
- Trim only trailing empty cells for direction analysis.
- Return `null` if no strong RTL codepoint exists.
- Build visual runs from the visible text.
- Reverse RTL runs.
- Keep LTR runs in original order.
- Reverse run order for RTL rows.
- Copy untouched empty cells after projected visible content.
- Fill `visual_to_logical` and `logical_to_visual`.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
zig build test -Dtest-filter="rtl projection" -Demit-macos-app=false
```

Expected: PASS.

### Task 3: Wire Projection Into Renderer

**Files:**
- Modify: `src/terminal/main.zig`
- Modify: `src/renderer/generic.zig`

- [ ] **Step 1: Export helper**

In `src/terminal/main.zig`, add:

```zig
pub const rtl_projection = @import("rtl_projection.zig");
```

- [ ] **Step 2: Apply projection in `rebuildRow`**

In `src/renderer/generic.zig`, inside `rebuildRow`, after `cells_len` is calculated:

```zig
var rtl_projection: ?terminal.rtl_projection.Projection = null;
defer if (rtl_projection) |*projection| projection.deinit(self.alloc);

if (try terminal.rtl_projection.projectCells(self.alloc, cells_slice, cells_len)) |projection| {
    rtl_projection = projection;
    cells_slice = rtl_projection.?.cells.slice();
}
```

Use `rtl_projection.visual_to_logical[x]` when checking selection, highlights, and links so styles stay attached to the logical source cell while glyphs render at the visual x position.

- [ ] **Step 3: Map cursor shaping break**

When `cursor_x` is on the projected row, map it through `logical_to_visual` before passing it to `runIterator`. This preserves the shaping break around the cursor.

- [ ] **Step 4: Add a renderer-level regression test**

Add a small test at the bottom of `src/renderer/generic.zig` or a dedicated renderer test file that calls the projection path indirectly enough to prove the visual cell order used by the renderer matches the terminal helper.

- [ ] **Step 5: Verify renderer path**

Run:

```bash
zig build test -Dtest-filter="rtl projection" -Demit-macos-app=false
zig build test -Dtest-filter="renderer" -Demit-macos-app=false
```

Expected: PASS.

### Task 4: Build and Manual Smoke

**Files:**
- No source files unless build scripts prove a real issue.

- [ ] **Step 1: Build without macOS app bundle first**

Run:

```bash
zig build -Demit-macos-app=false
```

Expected: PASS.

- [ ] **Step 2: Build macOS app**

Run:

```bash
zig build
```

Expected: `zig-out/Ghostty.app` exists.

- [ ] **Step 3: Launch local app binary**

Run:

```bash
zig-out/Ghostty.app/Contents/MacOS/ghostty --version
```

Expected: version reports the fresh local build.

- [ ] **Step 4: Manual visual check**

Open the built app and paste:

```text
مهارة systematic-debugging تعمل
echo "مرحبا world"
~/Project/ghostty-fresh-rtl-v1.3.1
```

Expected: Arabic reads naturally, English/code/path tokens remain LTR.

### Task 5: Document Scope and Limits

**Files:**
- Create: `docs/RTL.md`

- [ ] **Step 1: Document what changed**

Write:
- This is a display-only RTL layer.
- Terminal buffer/copy storage stays logical.
- Full Unicode BiDi conformance is not claimed.
- Cursor/selection behavior is intentionally conservative unless verified.

- [ ] **Step 2: Final verification**

Run:

```bash
git status --short --branch
zig build test -Dtest-filter="rtl projection" -Demit-macos-app=false
zig build -Demit-macos-app=false
```

Expected: tests/build pass and git diff only contains the RTL display-layer files.

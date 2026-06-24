# Ghostty RTL Project Ledger

Last updated: 2026-06-25 01:16:30 +0300

## Current State

- Repo: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1`
- Branch: `bidi/simple-rtl-v1.3.1`
- Base simple RTL commit: `eef69f5d3d67945de6e248f369be70340963a7fe`
- Latest verified RTL source fix commit: `9383f4161`
- Current repo build output: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1/zig-out/Ghostty.app`
- The repo build artifact is generated and its version suffix follows the git `HEAD` at build time.
- Desktop test copy: `/Users/aboghali/Desktop/Ghostty-SimpleRTL-Test.app`
- Desktop test copy bundle id: `com.mitchellh.ghostty.simple-rtl-test`
- Desktop test copy version checked: `Ghostty 1.3.1-bidi-simple-rtl-v1.3.1+9383f4161`, `channel: tip`
- Desktop test copy signing: ad-hoc, verified with `codesign --verify --deep --strict`.
- Previous Desktop test copy backup: `/Users/aboghali/Desktop/Ghostty-SimpleRTL-Test.app.backup-20260625-011509`

## Golden Artifact

- Running app path observed: `/Applications/Ghostty.app`
- Matching local Desktop copy: `/Users/aboghali/Desktop/Ghostty.app`
- Verified backup copy: `/Users/aboghali/Desktop/Ghostty-1.3.1-bidi-dev-5b5adf88f-stable.app`
- Golden version: `Ghostty 1.3.1-bidi-dev+5b5adf88f`, `channel: tip`
- Golden binary hash: `7a497ba46e051fa3307f4abbbbdcf2a64afcaacffa7584d903bfda9ae1965d59`
- Important finding: the golden app is not built from the current repo commit. The embedded source id `5b5adf88f` is not present in the current local repo or current `origin` refs.

## Other App Copies

- `/Users/aboghali/Library/Mobile Documents/com~apple~CloudDocs/Desktop/Ghostty.app` has a different binary hash and fails `+version` because `Sparkle.framework` code signing does not match.
- Treat the iCloud Desktop copy as untrusted for launch/debugging until repaired or replaced.

## Decision

- Preserve `/Applications/Ghostty.app` as the stable reference.
- Create a named backup copy before any source or app replacement work.
- Do not overwrite, relaunch, or replace the running app without explicit approval from Moe.
- Future fixes should be rebuilt from source and visually compared against the golden artifact instead of assuming this repo is the original source.
- Use the separate Desktop test copy for manual checks before any golden-app replacement.

## Next Steps

- Phase A source fix: numbered RTL list markers now treat digits as weak for base-direction detection in `src/terminal/rtl_projection.zig`.
- Added regression coverage for numbered and hyphen RTL list markers in `src/terminal/rtl_projection_test.zig`.
- Verified with targeted `zig build test -Dtest-filter='rtl projection' -Demit-macos-app=false`, full `zig build test -Demit-macos-app=false`, and a release build command.
- Phase B source fix: wrapped continuation rows now inherit base direction from the first visible row in the same soft-wrapped logical line, and RTL continuations align visible text to the RTL edge.
- The inherited projection options are passed through both row rendering and cursor x-mapping in `src/renderer/generic.zig`.
- Added regression coverage for RTL-base wrapped continuations that begin with English and for LTR-only continuation rows aligned to the RTL edge.
- Verified Phase B with `zig build test -Dtest-filter='wrapped continuation' -Demit-macos-app=false`, `zig build test -Dtest-filter='rtl projection' -Demit-macos-app=false`, and full `zig build test -Demit-macos-app=false`.
- A fresh plan-consultant run for Phase B hung and was stopped; execution followed the earlier consultant guidance that already required renderer-level base-direction inheritance and matching cursor/render projection.
- Refreshed `/Users/aboghali/Desktop/Ghostty-SimpleRTL-Test.app` from the Phase B build and re-signed it with the separate test bundle id.
- Keep `default.profraw` out of commits unless profiling data is intentionally needed.
- Phase C investigation: Moe's latest screenshots show mixed Arabic/English sentence order still breaks inside a single visual row, especially around punctuation, paths, list markers, and repeated English tokens.
- Root cause found: `src/terminal/rtl_projection.zig` still groups cells as only RTL vs non-RTL runs. This preserves simple English tokens but mishandles Unicode weak/neutral characters.
- Local reference check: `fribidi --rtl --novisual --ltov --vtol --levels` maps differ from the current heuristic for Moe-style examples.
- Existing dependency note: `uucode` is already available to Ghostty modules and exposes `get(.bidi_class, cp)`, so a stronger display-layer projection can use real Unicode Bidi_Class data without adding a new package.
- Consultant gate: two 2026-06-25 plan-consultant attempts for the Bidi_Class/level-based Phase C plan hung before a final verdict. Audit folders: `/Users/aboghali/.codex/external-worker-runs/2026-06-25-004531-anthropic-plan-consultant` and `/Users/aboghali/.codex/external-worker-runs/2026-06-25-004820-anthropic-plan-consultant`.
- Moe explicitly approved continuing without consultant after the repeated consultant hangs.
- Phase C source fix commit: `9383f4161 fix: resolve mixed RTL rows with bidi classes`.
- Phase C replaced RTL/non-RTL run reversal with a display-only Bidi_Class-based projection: weak/neutral resolution, simple level reordering, and a narrow list-marker RTL base heuristic.
- `src/build/uucode_config.zig` now includes `bidi_class` in the generated uucode table so `rtl_projection.zig` can use `uucode.get(.bidi_class, cp)` without a new dependency.
- Added regression coverage for repeated English tokens inside Arabic text, path suffixes, numbered mixed lists, neutral punctuation, and updated marker/wrapped-row expectations to match the same Bidi_Class ordering.
- Verified Phase C with `zig build test -Dtest-filter='rtl projection' -Demit-macos-app=false`, `zig build test -Dtest-filter='wrapped continuation' -Demit-macos-app=false`, full `zig build test -Demit-macos-app=false`, and `zig build -Doptimize=ReleaseFast -Dxcframework-target=native`.
- Refreshed `/Users/aboghali/Desktop/Ghostty-SimpleRTL-Test.app`, set bundle id `com.mitchellh.ghostty.simple-rtl-test`, ad-hoc signed it, and verified `codesign --verify --deep --strict`.
- Desktop test copy `+version` now reports `Ghostty 1.3.1-bidi-simple-rtl-v1.3.1+9383f4161`.
- Running Ghostty processes were not quit or restarted; any already-open window may still be running its previously loaded binary until Moe opens the refreshed Desktop app.

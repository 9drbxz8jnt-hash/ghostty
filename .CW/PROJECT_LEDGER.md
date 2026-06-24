# Ghostty RTL Project Ledger

Last updated: 2026-06-24 23:55:06 +0300

## Current State

- Repo: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1`
- Branch: `bidi/simple-rtl-v1.3.1`
- Base simple RTL commit: `eef69f5d3d67945de6e248f369be70340963a7fe`
- Latest verified RTL source fix commit: `737bf3b7f`
- Current repo build output: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1/zig-out/Ghostty.app`
- The repo build artifact is generated and its version suffix follows the git `HEAD` at build time.

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

## Next Steps

- Phase A source fix: numbered RTL list markers now treat digits as weak for base-direction detection in `src/terminal/rtl_projection.zig`.
- Added regression coverage for numbered and hyphen RTL list markers in `src/terminal/rtl_projection_test.zig`.
- Verified with targeted `zig build test -Dtest-filter='rtl projection' -Demit-macos-app=false`, full `zig build test -Demit-macos-app=false`, and a release build command.
- The wrapped-continuation English-token bug is still a separate phase because `projectCells` receives one row at a time and does not know the wrapped logical line base direction.
- Keep `default.profraw` out of commits unless profiling data is intentionally needed.

# Ghostty RTL Project Ledger

Last updated: 2026-06-24 23:44:00 +0300

## Current State

- Repo: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1`
- Branch: `bidi/simple-rtl-v1.3.1`
- Current repo commit: `eef69f5d3d67945de6e248f369be70340963a7fe`
- Current repo build output: `/Users/aboghali/Project/ghostty-fresh-rtl-v1.3.1/zig-out/Ghostty.app`
- Repo build version: `Ghostty 1.3.1`, `channel: stable`

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

- Decide whether to rebuild BiDi behavior in source or keep looking for the missing source only as a secondary effort.
- Keep `default.profraw` out of commits unless profiling data is intentionally needed.

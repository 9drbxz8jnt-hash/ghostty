# RTL Display Layer

This fork adds a small display-only RTL projection layer for Ghostty.

## Scope

- Terminal storage stays logical.
- ASCII-only rows keep Ghostty's existing fast path.
- Rows with Arabic or Hebrew codepoints are projected only before rendering.
- Embedded LTR tokens, such as commands, flags, paths, and English words, keep their left-to-right order.

## Non-Goals

- This is not a full Unicode Bidirectional Algorithm implementation.
- This does not claim full conformance for every mixed-script edge case.
- Copy/paste storage is not rewritten by this layer.

## Notes

The projection is intentionally conservative. It exists to make common Arabic/Hebrew plus English terminal output readable without bringing back the older full BiDi pipeline.

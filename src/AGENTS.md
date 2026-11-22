## Jai

The compiler is `jaic`, not `jai`.

### Build and verify
- `jaic -check examples.jai` (also with `-no_dce`)
- `jaic -exe examples.exe examples.jai`
- Run both after changes and fix errors before finishing.

### References
- Standard library: `docs/jai-stdlib/`
- Compiler examples: `docs/jai-examples/`
- Local reference: `docs/encyclopedia-of-jai-examples/documents/`. Read the relevant chapter before using unfamiliar syntax or APIs. Use the topic files, not the whole `combined_output.md`.
- Installed compiler: `<path>` (`how_to/`, `modules/`)

### Rules
- The community examples are not a versioned spec. Verify uncertain syntax, signatures, allocator behavior and compiler options against the installed compiler's `modules/` and `how_to/`, and compile a minimal example when needed.
- Do not invent APIs or copy outdated examples blindly.
- 
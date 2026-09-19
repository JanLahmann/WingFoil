# Vendored FitFileParser 1.5.2 (MIT, roznet/FitFileParser, commit afcdf16 "updated to 21.115")

Copied into the repo on 20 September 2026 with one change: the generated
`rzfit_swift_string_for_type` (and its reverse) narrowed a `FIT_UINT32` into
`FIT_ENUM` / `FIT_UINT8` / `FIT_UINT16` with the trapping initializer, so a structurally
valid FIT carrying a value outside the narrower type crashed the app inside `FitFile.init`
before any code of ours ran (found by the mutation fuzz, docs/testing.md). Every such
conversion is `truncatingIfNeeded:` here. Upstream pull request: Jan's call.

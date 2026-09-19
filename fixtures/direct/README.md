# Direct-transfer fixtures

- `example.cjr` — the 64 bytes of the worked example in docs/transfer-format.md §2.3: the
  16-byte `CJR1` stream header, one keyframe and two deltas, three fixes a second apart at
  Lake Garda. Not a recording, and not derived from one. It is the pin four implementations
  are held against — `lab/tools/cjr_ref.py --check`, the kit's `DirectStreamTests`, the
  watch's `WingfoilTests`, and the document itself — so a decoder in any language can be
  pointed at a file instead of at a hex string. Regenerate it with
  `python3 lab/tools/cjr_ref.py` if the format ever moves.

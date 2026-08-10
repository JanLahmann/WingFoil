import Foundation

/// Guards the FIT byte stream against a buffer overflow in FitFileParser's vendored
/// Garmin C decoder before that decoder ever sees it.
///
/// ## Why this exists
/// `FIT_CONVERT_STATE` (fit_convert.h) reassembles every data message into a fixed
/// **254-byte** scratch buffer (`union { … FIT_UINT8 mesg[FIT_MESG_SIZE]; } u`), and the
/// struct member immediately after that union is `convert_table[16]` — the decoded field
/// layout for all 16 local message types. Neither `Fit_InitRawMesg()` nor the
/// `FIT_CONVERT_DECODE_FIELD_DATA` writer bounds-checks against `FIT_MESG_SIZE`: the
/// per-field write is `state->u.mesg[field.offset_local + field_offset] = datum` with
/// `offset_local` running to the full declared message size.
///
/// So a *definition message* whose native fields sum to more than 254 bytes makes the
/// decoder scribble past `u.mesg` straight into `convert_table`. Two consequences, both
/// observed on `fixtures/sessions/ciq/*.fit` (written by our own Connect IQ app, which
/// logs `accelerometer_data` — a **356-byte** definition, 102 bytes past the end):
///
/// 1. **Silent corruption.** The clobbered `convert_table` entries carry bogus field
///    offsets/sizes, so subsequently decoded `record` messages are read from the wrong
///    bytes. Most lose their `timestamp` and are dropped outright (4154 records → 269),
///    which is why distance/flight numbers diverged wildly from the Python reference.
/// 2. **Segfault.** The corrupted entries also carry garbage `num_fields`/`size` values,
///    so the *next* `Fit_InitRawMesg()` for that local type memcpy-walks tens of KB past
///    the stack-allocated state. Crash timing depends on stack layout, hence intermittent.
///
/// The same file also trips the second limit: Garmin's `device_settings` declares **114**
/// field definitions where `FIT_MESG_CONVERT.fields[91]` has room for 91.
///
/// ## What this does
/// A minimal FIT record-layer rewrite: definitions that the C decoder provably cannot
/// represent are dropped, together with the data messages that reference them, and the
/// header `data_size` plus the trailing CRC-16 are recomputed. Everything else is copied
/// through byte-for-byte. Files without an oversize definition — every non-CIQ fixture —
/// are returned untouched, so this can never perturb an already-correct parse.
///
/// Fail-soft: any structural surprise aborts the rewrite and returns the original bytes.
enum FitStreamSanitizer {

    /// `FIT_MESG_SIZE` — capacity of `FIT_CONVERT_STATE.u.mesg`.
    static let maxNativeMessageBytes = 254
    /// `FIT_MESG_CONVERT.fields[91]` — capacity of the per-local-type field table.
    static let maxNativeFieldDefs = 91

    struct Result {
        var data: Data
        /// Global message numbers whose definitions had to be dropped, each mapped to the
        /// number of *data* messages that went with them (empty ⇒ stream untouched).
        var droppedMessageTypes: [UInt16: Int] = [:]
    }

    static func sanitize(_ data: Data) -> Result {
        let bytes = [UInt8](data)
        guard let layout = FitStreamWalker.layout(of: bytes) else { return Result(data: data) }
        var dropping = [Bool](repeating: false, count: 16)
        var dropped: [UInt16: Int] = [:]
        /// Half-open byte ranges of the data section to keep, coalesced.
        var keep: [Range<Int>] = []
        var runStart = layout.headerSize

        func drop(_ range: Range<Int>) {
            if range.lowerBound > runStart { keep.append(runStart..<range.lowerBound) }
            runStart = range.upperBound
        }

        guard FitStreamWalker.walk(bytes, { event in
            switch event {
            case let .definition(local, def, range):
                dropping[local] = def.nativeBytes > maxNativeMessageBytes
                    || def.fields.count > maxNativeFieldDefs
                if dropping[local] {
                    dropped[def.globalNum] = dropped[def.globalNum] ?? 0   // register the type
                    drop(range)
                }
            case let .data(local, def, range, _):
                if dropping[local] {
                    dropped[def.globalNum, default: 0] += 1
                    drop(range)
                }
            }
        }) != nil else { return Result(data: data) }

        guard !dropped.isEmpty else { return Result(data: data) }
        if layout.dataEnd > runStart { keep.append(runStart..<layout.dataEnd) }

        // Rebuild: original header with a patched data_size, the kept records, fresh CRC.
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        out.append(contentsOf: bytes[0..<layout.headerSize])
        let newDataSize = keep.reduce(0) { $0 + $1.count }
        out[4] = UInt8(newDataSize & 0xFF)
        out[5] = UInt8((newDataSize >> 8) & 0xFF)
        out[6] = UInt8((newDataSize >> 16) & 0xFF)
        out[7] = UInt8((newDataSize >> 24) & 0xFF)
        if layout.headerSize == 14, bytes[12] != 0 || bytes[13] != 0 {
            let headerCRC = FitStreamWalker.crc16(out[0..<12])  // only if the source had one
            out[12] = UInt8(headerCRC & 0xFF)
            out[13] = UInt8(headerCRC >> 8)
        }
        for range in keep { out.append(contentsOf: bytes[range]) }

        // FitConvert accumulates its CRC from byte 0 and requires it to fold to zero after
        // the trailing 2 bytes, i.e. the file CRC spans header + data records.
        let fileCRC = FitStreamWalker.crc16(out[0...])
        out.append(UInt8(fileCRC & 0xFF))
        out.append(UInt8(fileCRC >> 8))

        // Preserve anything chained after the original CRC verbatim.
        if layout.dataEnd + 2 < bytes.count {
            out.append(contentsOf: bytes[(layout.dataEnd + 2)...])
        }

        return Result(data: Data(out), droppedMessageTypes: dropped)
    }
}

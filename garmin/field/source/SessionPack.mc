import Toybox.Lang;

// The compact SESSION developer-field schema for the data-field variant, in one table.
//
// TWO platform limits shape it, both measured on the device (not guessed — a probe build
// created developer fields one at a time on fenix847mm until the runtime refused):
//
//   * **32 bytes of developer data per message type** — the documented data-field budget
//     (docs/plan.md §2; the device app gets 256 B and spends ~57 B on its session message).
//     Confirmed: 8 x uint32 session fields (32 B) are accepted, the 9th is refused.
//   * **16 developer fields per message type** — undocumented, and it bites first for any
//     schema built from small fields. Confirmed: 16 x uint8 session fields (16 B) are
//     accepted and the 17th is refused; likewise 5 x uint32 + 11 x uint8 (31 B, 16 fields).
//     Over either limit the runtime does not throw a catchable exception — it kills the app
//     with "Out Of Memory Error: New Field out of memory for FIT data", or, from inside a
//     loop, the less helpful "System Error: Failed invoking <symbol>".
//
// So the schema is 15 fields / 30 bytes: one field and two bytes of headroom. The unit
// tests assert both limits, so the next field added to this table fails a test instead of
// bricking the app on the water.
//
// Field IDs are the docs/fit-schema.md contract and are shared with the device app wherever
// the meaning is identical (21/22/23/24/26/27/32/33/34/39/43 — same number, same meaning,
// same type). 50-59 is the new field-variant band; 50 and 54 are bit-packed precisely
// because the 16-field limit is scarcer than the byte budget.
//
// 0.9.6 spends one of the two spare slots on `clean_jibes`(51). It is a NEW id rather than a
// borrowed one because the device app has no clean-jibe field to mirror: its session message
// has been at the 16-field ceiling since 0.9.0 (docs/fit-schema.md), so the watch computes the
// count and shows it and cannot write it down. The data field's tighter BYTE budget happens to
// leave it the room the device app's does not, and 51 is the next free id in the field's own
// band — 50 is `turn_outcomes`, 52 is unallocated and stays that way, and 55/56 are the device
// app's packed fields and must never mean something else here.
//
// It is deliberately NOT packed into `turn_outcomes`(50). That field's three lanes are the
// outcome ladder — flew, touched down, fell in — which are mutually exclusive and sum to the
// counted turns. A clean jibe is a stricter question asked of one of those lanes (a fly-through
// that also carried its speed AND was named a jibe), so it does not partition anything and
// would have to be documented as "the fourth byte that is not like the others". A slot was
// cheaper than that sentence.
module SessionPack {
    enum {
        SLOT_FOIL_TIME = 0,         // 21 uint32 s
        SLOT_FOIL_PCT = 1,          // 22 uint8  %
        SLOT_FLIGHT_COUNT = 2,      // 23 uint16 count
        SLOT_LONGEST_S = 3,         // 24 uint16 s
        SLOT_BEST_2S = 4,           // 26 uint16 cm/s
        SLOT_BEST_10S = 5,          // 27 uint16 cm/s
        SLOT_TACKS = 6,             // 32 uint8  count
        SLOT_JIBES = 7,             // 33 uint8  count
        SLOT_TURN_SUCCESS = 8,      // 34 uint8  %
        SLOT_WIND_DIR = 9,          // 39 uint16 deg (65535 = unset)
        SLOT_APP_VERSION = 10,      // 43 uint16 (minor << 8 | schema)
        SLOT_OUTCOMES = 11,         // 50 uint32 packed flew/touchdown/fell
        SLOT_CLEAN_JIBES = 12,      // 51 uint8  count
        SLOT_DISCIPLINE = 13,       // 53 uint8  enum (1 = wingfoil)
        SLOT_CFG = 14,              // 54 uint32 packed entry/minFlight/exit
        SLOT_COUNT = 15
    }

    // Measured data-field limits, per message type (see the header).
    const LIMIT_BYTES = 32;
    const LIMIT_FIELDS = 16;

    const WIDTHS = [4, 1, 2, 2, 2, 2, 1, 1, 1, 2, 2, 4, 1, 1, 4] as Array<Number>;
    const FIELD_IDS = [21, 22, 23, 24, 26, 27, 32, 33, 34, 39, 43, 50, 51, 53, 54]
        as Array<Number>;

    // The RECORD message costs 3 fields / 3 B: foil_state(0) + turn_marker(3) + tick(4).
    const RECORD_BYTES = 3;
    const RECORD_FIELDS = 3;

    // 1 = wingfoil. The device app writes the same fact as the 16-byte `discipline` string
    // (field 20); a string that wide would eat half the field's whole session budget AND a
    // scarce field slot, so the field variant carries an enum. A parser accepts either.
    const DISCIPLINE_WINGFOIL = 1;

    function totalBytes() as Number {
        var n = 0;
        for (var i = 0; i < SLOT_COUNT; i++) {
            n += WIDTHS[i];
        }
        return n;
    }

    function fits() as Boolean {
        return totalBytes() <= LIMIT_BYTES && SLOT_COUNT <= LIMIT_FIELDS
            && RECORD_BYTES <= LIMIT_BYTES && RECORD_FIELDS <= LIMIT_FIELDS;
    }

    // ---- the two packed fields ----

    // 50 `turn_outcomes`: flew << 16 | touchdown << 8 | fell, each a uint8 count saturating
    // at 254. Three tallies, one field slot. The device app spends no field on these at all
    // (they are re-derived on the phone from the record-level turn markers) — the data field
    // carries them because it has no laps to hang them off.
    function packOutcomes(flew as Number, touchdown as Number, fell as Number) as Number {
        return (_u8(flew) << 16) | (_u8(touchdown) << 8) | _u8(fell);
    }

    function outcomeFlew(packed as Number) as Number {
        return (packed >> 16) & 0xFF;
    }

    function outcomeTouchdown(packed as Number) as Number {
        return (packed >> 8) & 0xFF;
    }

    function outcomeFell(packed as Number) as Number {
        return packed & 0xFF;
    }

    // 54 `cfg_pack`: the thresholds actually in effect, which the phone needs to reconcile
    // its own segmentation against the watch's (docs/fit-schema.md session fields 40-42, one
    // field instead of three):
    //     bits 31..16  entry speed, cm/s (0-65535)
    //     bits 15..11  min flight duration, s (0-31)
    //     bits 10..0   exit speed, cm/s (0-2047 — 73 km/h, far above any usable setting)
    function packCfg(entryCms as Number, exitCms as Number, minFlightS as Number) as Number {
        var e = entryCms < 0 ? 0 : (entryCms > 65535 ? 65535 : entryCms);
        var x = exitCms < 0 ? 0 : (exitCms > 2047 ? 2047 : exitCms);
        var m = minFlightS < 0 ? 0 : (minFlightS > 31 ? 31 : minFlightS);
        return (e << 16) | (m << 11) | x;
    }

    function cfgEntryCms(packed as Number) as Number {
        return (packed >> 16) & 0xFFFF;
    }

    function cfgMinFlightS(packed as Number) as Number {
        return (packed >> 11) & 0x1F;
    }

    function cfgExitCms(packed as Number) as Number {
        return packed & 0x7FF;
    }

    function _u8(v as Number) as Number {
        return v < 0 ? 0 : (v > 254 ? 254 : v);
    }

    // Clamp into the slot's width. Counts saturate one below the FIT "invalid" sentinel
    // (254 / 65534), exactly like the device app's counters, so a saturated count never
    // decodes as "field absent". wind_dir legitimately uses 65535 as its unset sentinel, and
    // app_version / the packed fields are bit patterns, not counts — all pass through.
    function clampSlot(slot as Number, v as Number) as Number {
        if (v < 0) {
            return 0;
        }
        if (slot == SLOT_WIND_DIR || slot == SLOT_APP_VERSION) {
            return v > 65535 ? 65535 : v;
        }
        if (slot == SLOT_OUTCOMES || slot == SLOT_CFG) {
            return v;                       // already packed by packOutcomes/packCfg
        }
        var w = WIDTHS[slot];
        if (w == 1) {
            return v > 254 ? 254 : v;
        }
        if (w == 2) {
            return v > 65534 ? 65534 : v;
        }
        return v;                           // uint32: nothing a session produces comes close
    }

    // Little-endian byte image of the whole message. Nothing on the watch transmits this —
    // FitContributor writes the values field by field — but encoding is how the schema's
    // byte cost is *measured* rather than asserted in a comment, and the round-trip test
    // proves every value survives the width the table claims for it.
    function encode(values as Array<Number>) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < SLOT_COUNT; i++) {
            var v = clampSlot(i, values[i]);
            for (var b = 0; b < WIDTHS[i]; b++) {
                out.add((v >> (8 * b)) & 0xFF);
            }
        }
        return out;
    }

    function decode(bytes as Array<Number>) as Array<Number> {
        var out = new Array<Number>[SLOT_COUNT];
        var p = 0;
        for (var i = 0; i < SLOT_COUNT; i++) {
            var v = 0;
            for (var b = 0; b < WIDTHS[i]; b++) {
                v = v | ((bytes[p] & 0xFF) << (8 * b));
                p++;
            }
            out[i] = v;
        }
        return out;
    }

    // Speeds are uint16 cm/s across the whole schema (docs/fit-schema.md).
    function cms(mps as Float) as Number {
        var v = (mps * 100.0).toNumber();
        return v < 0 ? 0 : (v > 65534 ? 65534 : v);
    }

    // The live detector state as the session values, clamped. Sole place the mapping from
    // detector counters to FIT session fields exists; FieldFit.updateSession() just hands
    // these to setData(), and the unit test round-trips them.
    function fromEngine(engine as FieldEngine, cfg as WingFoilCore.Config,
            appVersion as Number) as Array<Number> {
        var d = engine.detector;
        var t = engine.turns;
        var r = engine.records;
        var pct = engine.timerS > 0 ? (d.foilTimeS / engine.timerS * 100.0).toNumber() : 0;
        if (pct > 100) {
            pct = 100;
        }
        var vals = new Array<Number>[SLOT_COUNT];
        vals[SLOT_FOIL_TIME] = d.foilTimeS.toNumber();
        vals[SLOT_FOIL_PCT] = pct;
        vals[SLOT_FLIGHT_COUNT] = d.flightCount;
        vals[SLOT_LONGEST_S] = d.longestS.toNumber();
        vals[SLOT_BEST_2S] = cms(r.best2sMps);
        vals[SLOT_BEST_10S] = cms(r.best10sMps);
        vals[SLOT_TACKS] = t.tackCount;
        vals[SLOT_JIBES] = t.jibeCount;
        vals[SLOT_TURN_SUCCESS] = t.successPct();
        vals[SLOT_WIND_DIR] = cfg.windDirection < 0 ? 65535 : cfg.windDirection;
        vals[SLOT_APP_VERSION] = appVersion;
        vals[SLOT_OUTCOMES] = packOutcomes(t.flewCount, t.touchdownCount, t.fellCount);
        // The count only — never the rate. CPH is a division the reader can do better than the
        // watch can (the phone has the cleaned track and the field has moving time), and a
        // rounded rate written into a FIT would be the watch's denominator preserved forever.
        vals[SLOT_CLEAN_JIBES] = t.cleanJibeCount;
        vals[SLOT_DISCIPLINE] = DISCIPLINE_WINGFOIL;
        vals[SLOT_CFG] = packCfg(cms(cfg.foilEntryMps), cms(cfg.foilExitMps),
            cfg.minFlightS);
        for (var i = 0; i < SLOT_COUNT; i++) {
            vals[i] = clampSlot(i, vals[i]);
        }
        return vals;
    }
}

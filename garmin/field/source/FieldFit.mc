import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.WatchUi;
import WingFoilCore;

// Sole writer of the field variant's FIT developer fields (docs/fit-schema.md
// "Field-variant FIT (class d)"). A data field contributes to the FIT the NATIVE activity is
// writing, so there is no session to create and no laps to add — and a hard per-message
// budget of 32 bytes AND 16 fields (SessionPack documents how both were measured):
//   RECORD  3 fields / 3 B — foil_state(0) + turn_marker(3) + tick(4), identical meaning
//                            to the device app's
//   SESSION 14 fields / 29 B — the compact summary, whose table lives in SessionPack
// Field IDs shared with the device app carry exactly the app's meaning and type.
class FieldFit {
    const SCHEMA_VERSION = 1;
    // High byte of the session's `app_version`: the MINOR of the manifest's release version,
    // the way the device app's FitSchema.APP_MINOR is. It was 1 for as long as the field's
    // manifests carried no version at all and there was nothing for it to agree with; 0.9.5
    // gave them one, so it is 9. Only the LOW byte (SCHEMA_VERSION) has a reader downstream —
    // lab/parse.py and WingFoilKit both take the wire format from it — so this is the half
    // that says which build wrote the file, and it must move with the manifest.
    const APP_MINOR = 9;

    // record turn_marker enum — the docs/fit-schema.md record field 3 contract, byte for
    // byte the device app's FitFields enum (a parser must not care which app wrote it).
    enum {
        MARK_NONE = 0,
        MARK_TACK = 1,
        MARK_JIBE = 2,
        MARK_TURN = 3,
        MARK_FLEW = 4,
        MARK_TOUCHDOWN = 5,
        MARK_FELL = 6
    }

    hidden var _foilState as FitContributor.Field;
    hidden var _turnMarker as FitContributor.Field;
    hidden var _tick as FitContributor.Field;
    hidden var _session as Array<FitContributor.Field>;

    // Session field names and units, in SessionPack slot order (the table is the schema).
    hidden const NAMES = ["foil_time", "foil_pct", "flight_count", "longest_flight_s",
        "best_2s", "best_10s", "tack_count", "jibe_count", "turn_success_pct",
        "wind_dir_user", "app_version", "turn_outcomes", "discipline_id",
        "cfg_pack"] as Array<String>;
    hidden const UNITS = ["s", "%", "", "s", "cm/s", "cm/s", "", "", "%", "deg", "", "", "",
        ""] as Array<String>;

    function initialize(df as WatchUi.DataField) {
        _foilState = df.createField("foil_state", 0, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});
        _turnMarker = df.createField("turn_marker", 3, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});
        _tick = df.createField("tick", 4, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD});

        _session = new Array<FitContributor.Field>[SessionPack.SLOT_COUNT];
        for (var i = 0; i < SessionPack.SLOT_COUNT; i++) {
            var opts = {:mesgType => FitContributor.MESG_TYPE_SESSION};
            if (!UNITS[i].equals("")) {
                opts[:units] = UNITS[i];
            }
            _session[i] = df.createField(NAMES[i], SessionPack.FIELD_IDS[i], _typeOf(i),
                opts);
        }

        _foilState.setData(0);
        _turnMarker.setData(MARK_NONE);
        _tick.setData(0);
        // A session that never gets a usable fix still identifies itself as ours.
        _session[SessionPack.SLOT_DISCIPLINE].setData(SessionPack.DISCIPLINE_WINGFOIL);
        _session[SessionPack.SLOT_APP_VERSION].setData(appVersion());
    }

    function appVersion() as Number {
        return APP_MINOR * 256 + SCHEMA_VERSION;
    }

    // The FIT base type each slot's declared width implies — the one place widths become
    // types, so SessionPack's byte count and the wire format cannot disagree.
    hidden function _typeOf(slot as Number) as FitContributor.DataType {
        var w = SessionPack.WIDTHS[slot];
        if (w == 1) {
            return FitContributor.DATA_TYPE_UINT8;
        }
        return w == 2 ? FitContributor.DATA_TYPE_UINT16 : FitContributor.DATA_TYPE_UINT32;
    }

    // Record marker for a TurnDetector event: kind at confirmation, outcome when resolved.
    static function markerFor(turnEvent as Number, kind as Number) as Number {
        if (turnEvent == TurnDetector.EVENT_TURN) {
            return kind;                    // KIND_TACK/JIBE/TURN == MARK_TACK/JIBE/TURN
        }
        if (turnEvent == TurnDetector.EVENT_FLEW) {
            return MARK_FLEW;
        }
        if (turnEvent == TurnDetector.EVENT_TOUCHDOWN) {
            return MARK_TOUCHDOWN;
        }
        if (turnEvent == TurnDetector.EVENT_FELL) {
            return MARK_FELL;
        }
        return MARK_NONE;
    }

    // Every compute() tick. Values persist at their last level between writes, so the marker
    // is rewritten every second and marks exactly its own second.
    function setRecord(foilState as Number, tick as Number, turnMarker as Number) as Void {
        _foilState.setData(foilState);
        _turnMarker.setData(turnMarker);
        // 0xFF is FIT's uint8 invalid sentinel -- roll 0-254 so no tick decodes as absent.
        _tick.setData(tick % 255);
    }

    // The session message is written by the native activity when it ends, taking whatever
    // values were last set — so this runs every tick and never needs a "save" hook.
    function updateSession(engine as FieldEngine, cfg as WingFoilCore.Config) as Void {
        var vals = SessionPack.fromEngine(engine, cfg, appVersion());
        for (var i = 0; i < SessionPack.SLOT_COUNT; i++) {
            _session[i].setData(vals[i]);
        }
    }
}

// GENERATED from docs/copy/watch.json by garmin/tools/make_strings.py — do not edit.
//
// One member per word the pages draw, and one `WatchUi.loadResource` each, filled by
// `Words.load()`. The names are the ones the drawing code and the layout suite already used
// when these were `const` literals, with `Words.` in front of them.
//
// WHY A MODULE and not the file-scope globals they were: Monkey C caps the `globals` module
// at 253 members and CIQ 3.x enforces it, so 105 words failed every fenix 5 Plus build at
// 286. A module costs the globals table one name.
//
// WHEN IT RUNS: `WingfoilApp.initialize()` and the first line of every View's
// `initialize()` — page construction, never `onUpdate`. The guard makes every call after
// the first free, which is what lets a view be built twice (the lock screen hands over to
// the start page) and what lets a unit test load the words without an app around it.
//
// WHAT IT COSTS: one String per entry below, held for the life of the app. They were
// already in the program as code constants; this moves them into the resource table and
// hands the app a reference to each.

import Toybox.Lang;
import Toybox.WatchUi;


module Words {
    var SPLASH_DOMAIN as String = "";
    var START_TITLE as String = "";
    var START_HINT as String = "";
    var START_HINT_LONG as String = "";
    var START_WIND_UNSET as String = "";
    var START_WIND_PREFIX as String = "";
    var START_GPS_GOOD as String = "";
    var START_GPS_READY as String = "";
    var START_GPS_WEAK as String = "";
    var START_GPS_NONE as String = "";
    var TALLY_CAP_FLEW as String = "";
    var TALLY_CAP_TOUCH as String = "";
    var TALLY_CAP_FELL as String = "";
    var TALLY_CAP_CLEAN as String = "";
    var STREAK_CAPTION as String = "";
    var STREAK_ROW_CAPTION as String = "";
    var KINDS_NO_WIND as String = "";
    var PAUSED_TEXT as String = "";
    var PAUSED_TEXT_LONG as String = "";
    var TURNS_PORT as String = "";
    var TURNS_STBD as String = "";
    var FOIL_TITLE as String = "";
    var LBL_FOIL as String = "";
    var FOIL_COL_TIME as String = "";
    var LBL_TIME as String = "";
    var CAP_TIME as String = "";
    var TIGHT_TIME as String = "";
    var FOIL_COL_DIST as String = "";
    var MAP_KM as String = "";
    var LBL_KM as String = "";
    var CAP_KM as String = "";
    var UNIT_KM as String = "";
    var FOIL_KEY_TOTAL as String = "";
    var FOIL_KEY_TOTAL_TIGHT as String = "";
    var FOIL_KEY_MAX as String = "";
    var MAP_WAITING as String = "";
    var REC_NEW_PB as String = "";
    var STORY_ON_FOIL as String = "";
    var STORY_TOP_SPEED as String = "";
    var LBL_TURNS as String = "";
    var CAP_TURNS as String = "";
    var STORY_TURNS as String = "";
    var LBL_BEST_2S as String = "";
    var REC_BEST_2S as String = "";
    var LBL_BEST_10S as String = "";
    var REC_BEST_10S as String = "";
    var KINDS_JIBES as String = "";
    var LBL_JIBES as String = "";
    var KINDS_TACKS as String = "";
    var LBL_TACKS as String = "";
    var SUM_SAVED as String = "";
    var SUM_NOT_SAVED as String = "";
    var SUM_HERO_ON_FOIL as String = "";
    var SUM_HERO_FOIL as String = "";
    var SUM_HERO_OF as String = "";
    var TAKEOFF_WORD as String = "";
    var LBL_TAKEOFFS as String = "";
    var TAKEOFF_OF as String = "";
    var TAKEOFF_PUMPS as String = "";
    var TAKEOFF_COST as String = "";
    var TAKEOFF_BPM as String = "";
    var UNIT_BPM_PAD as String = "";
    var MENU_SESSION as String = "";
    var MENU_RESUME as String = "";
    var MENU_WIND as String = "";
    var MENU_SAVE as String = "";
    var MENU_DISCARD as String = "";
    var MENU_DISCARD_ASK as String = "";
    var MENU_KEEP as String = "";
    var MENU_WIND_FROM as String = "";
    var MENU_UNSET as String = "";
    var LOCK_TITLE as String = "";
    var LOCK_KIND as String = "";
    var LOCK_KEY_BAD as String = "";
    var LOCK_SEND_CODE as String = "";
    var LOCK_HINT_1 as String = "";
    var LOCK_HINT_2 as String = "";
    var FLASH_FLEW as String = "";
    var FLASH_TOUCH as String = "";
    var FLASH_FELL as String = "";
    var FLASH_CLEAN as String = "";
    var FLASH_CLEAN_JIBE as String = "";
    var FLASH_DRY as String = "";
    var FLASH_LONGEST as String = "";
    var FLASH_JIBE as String = "";
    var FLASH_TACK as String = "";
    var FLASH_TURN as String = "";
    var LBL_FOIL_PCT as String = "";
    var LBL_FLIGHTS as String = "";
    var LBL_FLIGHT as String = "";
    var LBL_LONGEST as String = "";
    var LBL_TIMER as String = "";
    var LBL_BPM as String = "";
    var UNIT_BPM as String = "";
    var LBL_SCORE as String = "";
    var LBL_BATT as String = "";
    var LBL_PUMPS as String = "";
    var LBL_TO_FOIL as String = "";
    var LBL_HR_COST as String = "";
    var LBL_DRY_RUN as String = "";
    var LBL_FOIL_DIST as String = "";
    var CAP_NOW as String = "";
    var CAP_TIME_ON_FOIL as String = "";
    var CAP_DIST_ON_FOIL as String = "";
    var TIGHT_DIST as String = "";

    var _loaded as Boolean = false;

    //! Fill every word above from the resource table, once.
    function load() as Void {
        if (_loaded) { return; }
        _loaded = true;
        SPLASH_DOMAIN = WatchUi.loadResource(Rez.Strings.SplashDomain) as String;
        START_TITLE = WatchUi.loadResource(Rez.Strings.StartTitle) as String;
        START_HINT = WatchUi.loadResource(Rez.Strings.StartHint) as String;
        START_HINT_LONG = WatchUi.loadResource(Rez.Strings.StartHintLong) as String;
        START_WIND_UNSET = WatchUi.loadResource(Rez.Strings.StartWindUnset) as String;
        START_WIND_PREFIX = (WatchUi.loadResource(Rez.Strings.StartWindPrefix) as String) + " ";
        START_GPS_GOOD = WatchUi.loadResource(Rez.Strings.StartGpsGood) as String;
        START_GPS_READY = WatchUi.loadResource(Rez.Strings.StartGpsReady) as String;
        START_GPS_WEAK = WatchUi.loadResource(Rez.Strings.StartGpsWeak) as String;
        START_GPS_NONE = WatchUi.loadResource(Rez.Strings.StartGpsNone) as String;
        TALLY_CAP_FLEW = WatchUi.loadResource(Rez.Strings.CapFlew) as String;
        TALLY_CAP_TOUCH = WatchUi.loadResource(Rez.Strings.CapTouch) as String;
        TALLY_CAP_FELL = WatchUi.loadResource(Rez.Strings.CapFell) as String;
        TALLY_CAP_CLEAN = WatchUi.loadResource(Rez.Strings.CapClean) as String;
        STREAK_CAPTION = WatchUi.loadResource(Rez.Strings.CapDry) as String;
        STREAK_ROW_CAPTION = WatchUi.loadResource(Rez.Strings.CapStreakRow) as String;
        KINDS_NO_WIND = WatchUi.loadResource(Rez.Strings.KindsNoWind) as String;
        PAUSED_TEXT = WatchUi.loadResource(Rez.Strings.Paused) as String;
        PAUSED_TEXT_LONG = WatchUi.loadResource(Rez.Strings.PausedLong) as String;
        TURNS_PORT = WatchUi.loadResource(Rez.Strings.TurnsPort) as String;
        TURNS_STBD = WatchUi.loadResource(Rez.Strings.TurnsStbd) as String;
        FOIL_TITLE = WatchUi.loadResource(Rez.Strings.Foil) as String;
        LBL_FOIL = FOIL_TITLE;
        FOIL_COL_TIME = WatchUi.loadResource(Rez.Strings.Time) as String;
        LBL_TIME = FOIL_COL_TIME;
        CAP_TIME = FOIL_COL_TIME;
        TIGHT_TIME = FOIL_COL_TIME;
        FOIL_COL_DIST = WatchUi.loadResource(Rez.Strings.Km) as String;
        MAP_KM = FOIL_COL_DIST;
        LBL_KM = FOIL_COL_DIST;
        CAP_KM = FOIL_COL_DIST;
        UNIT_KM = FOIL_COL_DIST;
        FOIL_KEY_TOTAL = WatchUi.loadResource(Rez.Strings.FoilKeyTotal) as String;
        FOIL_KEY_TOTAL_TIGHT = WatchUi.loadResource(Rez.Strings.FoilKeyTotalTight) as String;
        FOIL_KEY_MAX = WatchUi.loadResource(Rez.Strings.FoilKeyMax) as String;
        MAP_WAITING = WatchUi.loadResource(Rez.Strings.MapWaiting) as String;
        REC_NEW_PB = WatchUi.loadResource(Rez.Strings.NewPb) as String;
        STORY_ON_FOIL = WatchUi.loadResource(Rez.Strings.StoryOnFoil) as String;
        STORY_TOP_SPEED = (WatchUi.loadResource(Rez.Strings.StoryTopSpeed) as String) + " ";
        LBL_TURNS = WatchUi.loadResource(Rez.Strings.Turns) as String;
        CAP_TURNS = LBL_TURNS;
        STORY_TURNS = LBL_TURNS;
        LBL_BEST_2S = WatchUi.loadResource(Rez.Strings.Best2s) as String;
        REC_BEST_2S = LBL_BEST_2S;
        LBL_BEST_10S = WatchUi.loadResource(Rez.Strings.Best10s) as String;
        REC_BEST_10S = LBL_BEST_10S;
        KINDS_JIBES = WatchUi.loadResource(Rez.Strings.Jibes) as String;
        LBL_JIBES = KINDS_JIBES;
        KINDS_TACKS = WatchUi.loadResource(Rez.Strings.Tacks) as String;
        LBL_TACKS = KINDS_TACKS;
        SUM_SAVED = WatchUi.loadResource(Rez.Strings.SumSaved) as String;
        SUM_NOT_SAVED = WatchUi.loadResource(Rez.Strings.SumNotSaved) as String;
        SUM_HERO_ON_FOIL = WatchUi.loadResource(Rez.Strings.SumHeroOnFoil) as String;
        SUM_HERO_FOIL = " " + (WatchUi.loadResource(Rez.Strings.SumHeroFoil) as String);
        SUM_HERO_OF = (WatchUi.loadResource(Rez.Strings.SumHeroOf) as String) + " ";
        TAKEOFF_WORD = WatchUi.loadResource(Rez.Strings.Takeoffs) as String;
        LBL_TAKEOFFS = TAKEOFF_WORD;
        TAKEOFF_OF = " " + (WatchUi.loadResource(Rez.Strings.TakeoffOf) as String) + " ";
        TAKEOFF_PUMPS = " " + (WatchUi.loadResource(Rez.Strings.TakeoffPumps) as String);
        TAKEOFF_COST = WatchUi.loadResource(Rez.Strings.TakeoffCost) as String;
        TAKEOFF_BPM = " " + (WatchUi.loadResource(Rez.Strings.TakeoffBpm) as String);
        UNIT_BPM_PAD = TAKEOFF_BPM;
        MENU_SESSION = WatchUi.loadResource(Rez.Strings.MenuSession) as String;
        MENU_RESUME = WatchUi.loadResource(Rez.Strings.MenuResume) as String;
        MENU_WIND = WatchUi.loadResource(Rez.Strings.MenuWind) as String;
        MENU_SAVE = WatchUi.loadResource(Rez.Strings.MenuSave) as String;
        MENU_DISCARD = WatchUi.loadResource(Rez.Strings.MenuDiscard) as String;
        MENU_DISCARD_ASK = WatchUi.loadResource(Rez.Strings.MenuDiscardAsk) as String;
        MENU_KEEP = WatchUi.loadResource(Rez.Strings.MenuKeep) as String;
        MENU_WIND_FROM = WatchUi.loadResource(Rez.Strings.MenuWindFrom) as String;
        MENU_UNSET = WatchUi.loadResource(Rez.Strings.MenuUnset) as String;
        LOCK_TITLE = WatchUi.loadResource(Rez.Strings.LockTitle) as String;
        LOCK_KIND = WatchUi.loadResource(Rez.Strings.LockKind) as String;
        LOCK_KEY_BAD = WatchUi.loadResource(Rez.Strings.LockKeyBad) as String;
        LOCK_SEND_CODE = WatchUi.loadResource(Rez.Strings.LockSendCode) as String;
        LOCK_HINT_1 = WatchUi.loadResource(Rez.Strings.LockHint1) as String;
        LOCK_HINT_2 = WatchUi.loadResource(Rez.Strings.LockHint2) as String;
        FLASH_FLEW = WatchUi.loadResource(Rez.Strings.FlashFlew) as String;
        FLASH_TOUCH = WatchUi.loadResource(Rez.Strings.FlashTouch) as String;
        FLASH_FELL = WatchUi.loadResource(Rez.Strings.FlashFell) as String;
        FLASH_CLEAN = WatchUi.loadResource(Rez.Strings.FlashClean) as String;
        FLASH_CLEAN_JIBE = WatchUi.loadResource(Rez.Strings.FlashCleanJibe) as String;
        FLASH_DRY = " " + (WatchUi.loadResource(Rez.Strings.FlashDry) as String);
        FLASH_LONGEST = WatchUi.loadResource(Rez.Strings.FlashLongest) as String;
        FLASH_JIBE = WatchUi.loadResource(Rez.Strings.FlashJibe) as String;
        FLASH_TACK = WatchUi.loadResource(Rez.Strings.FlashTack) as String;
        FLASH_TURN = WatchUi.loadResource(Rez.Strings.FlashTurn) as String;
        LBL_FOIL_PCT = WatchUi.loadResource(Rez.Strings.LblFoilPct) as String;
        LBL_FLIGHTS = WatchUi.loadResource(Rez.Strings.LblFlights) as String;
        LBL_FLIGHT = WatchUi.loadResource(Rez.Strings.LblFlight) as String;
        LBL_LONGEST = WatchUi.loadResource(Rez.Strings.LblLongest) as String;
        LBL_TIMER = WatchUi.loadResource(Rez.Strings.LblTimer) as String;
        LBL_BPM = WatchUi.loadResource(Rez.Strings.Bpm) as String;
        UNIT_BPM = LBL_BPM;
        LBL_SCORE = WatchUi.loadResource(Rez.Strings.LblScore) as String;
        LBL_BATT = WatchUi.loadResource(Rez.Strings.LblBatt) as String;
        LBL_PUMPS = WatchUi.loadResource(Rez.Strings.LblPumps) as String;
        LBL_TO_FOIL = WatchUi.loadResource(Rez.Strings.LblToFoil) as String;
        LBL_HR_COST = WatchUi.loadResource(Rez.Strings.LblHrCost) as String;
        LBL_DRY_RUN = WatchUi.loadResource(Rez.Strings.LblDryRun) as String;
        LBL_FOIL_DIST = WatchUi.loadResource(Rez.Strings.LblFoilDist) as String;
        CAP_NOW = (WatchUi.loadResource(Rez.Strings.CapNow) as String) + " ";
        CAP_TIME_ON_FOIL = WatchUi.loadResource(Rez.Strings.CapTimeOnFoil) as String;
        CAP_DIST_ON_FOIL = WatchUi.loadResource(Rez.Strings.CapDistOnFoil) as String;
        TIGHT_DIST = WatchUi.loadResource(Rez.Strings.TightDist) as String;
    }
}

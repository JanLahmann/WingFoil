import Toybox.Lang;

module WingFoilCore {

// Fastest a wingfoil sample can plausibly be. The outright sailing speed record is 65.45 kn
// (33.7 m/s) and a wing rider will never see half of it, so 40 m/s (144 km/h) is far above
// anything real and far below anything broken.
const MAX_SPEED_MPS = 40.0;

// A single impossible sample poisons everything that latches: SpeedRecords keeps the best
// value it ever saw, distance integrates it, and both ride to the FIT and on to the phone.
// The simulator produced one of 1.4e7 m/s during FIT replay, which showed as a 50 675 121 km/h
// best-2 s and 14 934 km of distance; a watch produces the small version of it when a fix
// returns after a swim. Samples outside the plausible band are treated exactly like a sample
// with unusable GPS quality: not fed to any detector, and worth no distance.
function speedPlausible(mps as Float) as Boolean {
    return mps >= 0.0 && mps <= MAX_SPEED_MPS;
}

}

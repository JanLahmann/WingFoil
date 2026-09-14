import Foundation

/// The channel's cut of the brand mark on the wrist — the same rule as the phone's
/// `ChannelArt` (docs/channels.md, "Telling the channels apart"): the release mark as drawn,
/// a red BETA label for the beta, the mark mirrored for dev. The watch app's icon follows
/// its phone's per configuration in project.yml; this names the start page's mark.
enum ChannelArt {
    #if DEV
    static let brandMark = "BrandMark-Dev"
    #elseif BETA
    static let brandMark = "BrandMark-Beta"
    #else
    static let brandMark = "BrandMark"
    #endif
}

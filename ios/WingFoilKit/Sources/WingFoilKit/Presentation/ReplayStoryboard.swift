import Foundation

/// The whole shape of a recorded clip: a title card, the replay `ReplayDriver` paces, the
/// rider's own photos spliced into it at the moment they were taken, and a closing card.
///
/// **The closing card's content is not here.** It used to carry
/// `ReplayCommentary.highlights` — two or three superlatives to print under the metrics — and
/// two of the three said what the metrics grid already said, four centimetres higher up. The
/// card now prints numbers and only numbers (`ShareCardStats.outro`), so the storyboard's job
/// is the *shape* of the clip and nothing that goes on the frames.
///
/// **Why this is not part of `ReplayDriver`.** The driver answers one question — where is the
/// playhead one tick later — and it answers it as a function of (span, rate, milestones) with
/// nothing else in it. The moment a clip grew bookends and photo pauses, "how long is this
/// going to be" stopped being a property of the playhead: three of the five things that make
/// up a 40-second clip never move the playhead at all. So the driver keeps its contract and
/// this wraps it, which also means the pinned Torbole run times (`ReplayDriverTests`) stay
/// pinned to the same arithmetic they always were, and the cards are visibly *added* to them.
///
/// **Why the photo scheduling is here and not in the view.** "This picture was taken at 14:32,
/// so it belongs 25 minutes into the replay" is a statement about the session, of exactly the
/// kind `ReplayBeats` and `ReplayCommentary` already own — and it is the kind of statement
/// that is invisible until a rider notices the photo of his best jibe played after the outro.
/// A view that did the arithmetic inline would also have to do it 20 times a second.
///
/// Nothing in here loads an image, decodes EXIF or knows what a `PhotosPickerItem` is. It
/// takes ids and dates and hands back an order.
public struct ReplayStoryboard: Sendable, Equatable {

    // MARK: - What goes in

    /// A photo the rider chose, reduced to the two things a schedule needs: something to call
    /// it by, and when the shutter fired.
    ///
    /// `takenAt` is optional because a picture very often cannot say. A screenshot, a photo
    /// saved out of a chat app, anything re-encoded by a messenger — all of them arrive with
    /// the EXIF date stripped, and a rider who added one did not thereby ask for it to be
    /// dropped. See `slideshow`.
    public struct Photo: Sendable, Equatable, Identifiable {
        public let id: String
        public let takenAt: Date?

        public init(id: String, takenAt: Date? = nil) {
            self.id = id
            self.takenAt = takenAt
        }
    }

    /// A photo that landed inside the session, placed on the session clock.
    public struct Splice: Sendable, Equatable, Identifiable {
        /// The `Photo.id` it came from — the view looks the image up by this.
        public let photo: String
        /// Session-clock seconds the replay pauses at, the same clock the playhead rides on.
        public let t: Double
        /// Wall seconds the picture is held. Carried per splice rather than read off the
        /// timing so a later "hold the best one longer" rule has somewhere to live.
        public let holdS: Double

        public var id: String { photo }

        public init(photo: String, t: Double, holdS: Double) {
            self.photo = photo
            self.t = t
            self.holdS = holdS
        }
    }

    /// How long each piece of the clip is on screen.
    ///
    /// One struct rather than five constants scattered over the view, because these five
    /// numbers *are* the clip's length and the rate picker quotes it before anything is
    /// recorded. A number the rider is choosing by does not belong in a private static on a
    /// `View`.
    public struct Timing: Sendable, Equatable {
        /// The opening card. Long enough to read a place and a time, short enough that a
        /// viewer who came for the session does not think the clip is broken.
        public var titleS: Double
        /// The closing card — the key metrics and two or three highlight lines. Longer than
        /// the title because there is four times as much on it, and because it is the frame
        /// somebody screenshots.
        public var outroS: Double
        /// How long the replay stops for one photo taken during the session.
        public var spliceHoldS: Double
        /// How long each photo *without* a usable moment gets in the closing slideshow.
        /// Shorter than a splice: a slideshow is a run of pictures and a splice is an
        /// interruption, and an interruption has to be worth the stop.
        public var slideS: Double
        /// The most photos one clip will carry. Six pauses is already a third of a 30×
        /// Torbole clip; a dozen would be a slideshow with a replay in it.
        public var maxPhotos: Int

        public init(titleS: Double = 2.5, outroS: Double = 4, spliceHoldS: Double = 2,
                    slideS: Double = 1.5, maxPhotos: Int = 6) {
            self.titleS = max(titleS, 0)
            self.outroS = max(outroS, 0)
            self.spliceHoldS = max(spliceHoldS, 0)
            self.slideS = max(slideS, 0)
            self.maxPhotos = max(maxPhotos, 0)
        }

        /// What the cinema view uses.
        public static let standard = Timing()

        /// The replay and nothing else — the shape the clip had before it grew bookends.
        /// Kept so a caller that wants the bare run does not have to reach past this type.
        public static let bare = Timing(titleS: 0, outroS: 0, spliceHoldS: 0, slideS: 0,
                                        maxPhotos: 0)
    }

    // MARK: - What comes out

    /// The pacing of the middle. Untouched by anything here.
    public let driver: ReplayDriver
    /// The opening card's two lines.
    public let title: ReplayTitleCard
    /// Photos with a moment inside the session, in time order.
    public let splices: [Splice]
    /// Photo ids with no usable moment, in the order the rider picked them. They play as a
    /// short run between the last frame of the replay and the closing card, which is the one
    /// place in the clip where an undated picture is not a lie about when it happened.
    public let slideshow: [String]
    public let timing: Timing

    public init(driver: ReplayDriver, title: ReplayTitleCard,
                splices: [Splice] = [],
                slideshow: [String] = [], timing: Timing = .standard) {
        self.driver = driver
        self.title = title
        self.splices = splices
        self.slideshow = slideshow
        self.timing = timing
    }

    // MARK: - Building

    /// The whole script, from the session's own clock and the rider's own pictures.
    ///
    /// `place` and `startedAt` are the caller's, exactly as `ReplayCommentary.make` takes
    /// them and for the same reason: deriving a readable place name from a filename is
    /// presentation the kit has no business owning. `startedAt` does double duty here — it is
    /// what turns a photo's wall-clock EXIF date into a position on the session clock, so
    /// without it every photo falls to the slideshow rather than being placed wrongly.
    public static func make(span: ClosedRange<Double>,
                            rate: Double,
                            milestones: [ReplayMilestone] = [],
                            photos: [Photo] = [],
                            place: String? = nil,
                            startedAt: Date? = nil,
                            timeZone: TimeZone = .current,
                            timing: Timing = .standard,
                            ease: ReplayDriver.Ease = .cinema) -> ReplayStoryboard {
        let driver = ReplayDriver(span: span, rate: rate, easeAt: milestones.map(\.t),
                                  ease: ease)

        // The cap is applied to the rider's own order — first six picked, not first six by
        // time. A rider who chose seven and got the six he chose first can see the rule; one
        // who got "the six earliest" would have to reason about EXIF to find the missing one.
        var splices: [Splice] = []
        var slideshow: [String] = []
        for photo in photos.prefix(timing.maxPhotos) {
            if let takenAt = photo.takenAt, let startedAt,
               let t = sessionTime(of: takenAt, startedAt: startedAt, in: span) {
                splices.append(Splice(photo: photo.id, t: t, holdS: timing.spliceHoldS))
            } else {
                slideshow.append(photo.id)
            }
        }
        // Stable on ties, so two frames of one burst play in the order they were shot. Two
        // photos seconds apart are deliberately *not* merged: at 30× they are a tenth of a
        // wall second apart, so the clip simply shows them back to back and the pair reads as
        // one four-second interlude — which is what a burst is.
        splices = splices.enumerated()
            .sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset
                                                   : $0.element.t < $1.element.t }
            .map(\.element)

        return ReplayStoryboard(
            driver: driver,
            title: ReplayTitleCard.make(place: place, startedAt: startedAt,
                                        timeZone: timeZone),
            splices: splices,
            slideshow: slideshow,
            timing: timing)
    }

    /// The same script, from a **length** the rider asked for instead of a speed.
    ///
    /// This is what the setup sheet calls: its picker offers 10 s / 25 s / 60 s, and the rate
    /// (and, on a short target, a briefer ease) is worked out by `ReplayPacing`. The target is
    /// the *replay's* length; the two cards and the photo pauses are still added on top by
    /// `runWallS`, and still said out loud — a rider who asks for ten seconds of replay and
    /// then adds three photos has asked for a longer clip, and the sheet's sentence has to
    /// keep up.
    public static func make(span: ClosedRange<Double>,
                            targetWallS: Double,
                            milestones: [ReplayMilestone] = [],
                            photos: [Photo] = [],
                            place: String? = nil,
                            startedAt: Date? = nil,
                            timeZone: TimeZone = .current,
                            timing: Timing = .standard) -> ReplayStoryboard {
        let plan = ReplayPacing.plan(span: span, targetWallS: targetWallS,
                                     easeAt: milestones.map(\.t))
        return make(span: span, rate: plan.rate, milestones: milestones, photos: photos,
                    place: place, startedAt: startedAt, timeZone: timeZone, timing: timing,
                    ease: plan.ease)
    }

    /// Where on the session clock a wall-clock instant falls, or nil when it falls outside
    /// the replay entirely.
    ///
    /// The offset is measured from `startedAt`, which is the instant `span.lowerBound` names
    /// — the same assumption `ReplayCommentary.startLine` already makes when it prints the
    /// session's opening time against the opening bookend.
    ///
    /// **Outside means outside.** A photo from the drive home is not a photo of the session,
    /// and placing it at the last frame because that is the nearest legal position would put
    /// a picture of a car park on the closing jibe. It goes to the slideshow instead, where
    /// it makes no claim about when it happened.
    public static func sessionTime(of takenAt: Date, startedAt: Date,
                                   in span: ClosedRange<Double>) -> Double? {
        let t = span.lowerBound + takenAt.timeIntervalSince(startedAt)
        return span.contains(t) ? t : nil
    }

    // MARK: - Playing it out

    /// The next photo the replay stops for, given how many it has already shown.
    ///
    /// Index-based rather than "the next splice after `t`" because the playhead is the wrong
    /// thing to ask: a splice pauses the replay *at* its own instant, so immediately after
    /// one has played the playhead still satisfies "at or after". A count cannot double-fire.
    public func nextSplice(shown: Int) -> Splice? {
        shown >= 0 && shown < splices.count ? splices[shown] : nil
    }

    // MARK: - How long the clip will be

    /// Wall seconds the replay itself runs — the driver's own number, unchanged.
    public var replayWallS: Double { driver.runWallS }

    /// Wall seconds the photos add: every splice is a pause in the replay, every slide is a
    /// frame after it, and neither moves the playhead.
    public var photoWallS: Double {
        splices.reduce(0) { $0 + $1.holdS } + Double(slideshow.count) * timing.slideS
    }

    /// What the rate picker offers — "30× · about 41 s".
    ///
    /// This is the number, not `driver.runWallS`: on the 30 Aug Torbole fixture the cards
    /// alone add six and a half seconds to a 34-second run, which is a fifth of the clip, and
    /// a rider choosing a speed by a length that omitted them would be choosing by a length
    /// nothing produces.
    public var runWallS: Double {
        guard driver.sessionSpanS > 0 else { return 0 }
        return timing.titleS + replayWallS + photoWallS + timing.outroS
    }
}

/// The clip's opening card: where, and when.
///
/// **The same vocabulary as the commentary's opening bookend**, which is the point of it
/// existing as a type rather than as two `Text`s in the cinema view. "Torbole, 14:07 —
/// session start" is the line the replay itself says on its first frame; the title card is
/// that line laid out instead of spoken, so it uses the same place string, the same POSIX
/// 24-hour clock (`ReplayCommentary.hourMinute`) and the same long date the share card
/// prints (`ShareCardStats.dateLine`). A card that invented its own date format would be a
/// third rendering of one afternoon's timestamp.
public struct ReplayTitleCard: Sendable, Equatable {

    /// The place, when the caller could name one. Nil degrades the card to the date alone,
    /// exactly as `startLine` degrades to "Session start" — neither invents a location.
    public let place: String?
    /// "30 August 2026 · 14:07". One line, because a card held for two and a half seconds
    /// gets one thing to read after the place.
    public let dateLine: String

    public init(place: String?, dateLine: String) {
        self.place = place
        self.dateLine = dateLine
    }

    public static func make(place: String?, startedAt: Date?,
                            timeZone: TimeZone = .current) -> ReplayTitleCard {
        let trimmed = place?.trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        if let startedAt {
            parts.append(ShareCardStats.dateLine(startedAt, timeZone: timeZone))
            parts.append(ReplayCommentary.hourMinute(startedAt, timeZone: timeZone))
        }
        return ReplayTitleCard(place: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                               dateLine: parts.joined(separator: " · "))
    }
}

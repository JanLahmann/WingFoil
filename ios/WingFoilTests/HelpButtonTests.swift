import Foundation
import Testing
import WingFoilKit
@testable import WingFoil

/// **Every `?` in the app opens something.**
///
/// `HelpCatalog.topic(_:)` is total by construction and traps rather than returning nil
/// (`preconditionFailure("HelpCatalog is incomplete")`), so a card pointing at a topic
/// nobody wrote is a crash on the tap rather than a blank sheet. The kit's own suite holds
/// the catalogue from the inside; this holds it from the app's side, which is where the
/// buttons actually are.
@Suite struct HelpButtonTests {

    /// Where a help topic is named on a screen: the `?` itself, the card groups' heading,
    /// the `help:` parameter the summary tiles carry, and the two screens that raise a
    /// topic from a sheet binding.
    private let markers = ["HelpButton", "HelpSectionHeader", "HelpTopicSheet",
                           "helpTopic", "help: ."]

    /// The topics the app's screens actually name, read out of the sources.
    private func referenced() -> [(id: HelpTopicID, file: String)] {
        AppSources.dotTokens(onLinesContaining: markers)
            .compactMap { token, file in
                HelpTopicID(rawValue: token).map { ($0, file) }
            }
    }

    /// The scan is worth nothing if it silently matched nothing, so the floor is asserted
    /// before the topics are. Twenty is well under what the app names today and well over
    /// what a broken pattern would find.
    @Test func theScanFindsTheButtons() throws {
        try #require(AppSources.directory != nil,
                     "the checkout this bundle was built from is not readable")
        let ids = Set(referenced().map(\.id))
        #expect(ids.count >= 20)
        #expect(ids.contains(.speedRecords))
        #expect(ids.contains(.windAxis))
    }

    /// The test the audit asked for: every topic a `?` button names resolves, and resolves
    /// to something written rather than to an empty card.
    @Test func everyTopicAButtonNamesResolves() throws {
        try #require(AppSources.directory != nil,
                     "the checkout this bundle was built from is not readable")
        for (id, file) in referenced() {
            let topic = HelpCatalog.topic(id, channel: AppChannel.channel)
            #expect(!topic.title.isEmpty, "\(id.rawValue) has no title, named in \(file)")
            #expect(!topic.summary.isEmpty, "\(id.rawValue) has no summary, in \(file)")
            #expect(!topic.body.isEmpty, "\(id.rawValue) has no body, named in \(file)")
        }
    }

    /// A `?` opens the topic, and the topic's own "read this next" list is a second set of
    /// links the rider can follow from the sheet that button just raised.
    @Test func everyTopicTheSheetOffersNextResolves() {
        for id in HelpTopicID.allCases {
            for next in HelpCatalog.topic(id, channel: AppChannel.channel).related {
                #expect(!HelpCatalog.topic(next, channel: AppChannel.channel).title.isEmpty)
            }
        }
    }
}

import SwiftUI
import WingFoilKit

/// **The Beta page** — what the beta is, what is in it now, how to join, how to tell us.
///
/// New on 25 September 2026 (Jan's plan of 24 September, section 5), reshaped on
/// 30 September around the community message (`BetaGuide.community`). Doors: the menu's
/// last row, the footer of *What CleanJibe does*, the Apple Watch app's card in that page's
/// family section and, in the beta and the dev build, every `BetaChip`. Every sentence is
/// the kit's (`BetaGuide`), and the list is `ChannelFeatures.beta`, the one
/// docs/channels.md is written into.
///
/// **Gated per docs/channels.md.** The release asks the rider in and carries the public
/// TestFlight link (`AppChannel.testFlight`). The beta and the dev build are titled "You
/// are in the beta", have no join step, and ask the tester's two questions instead: how it
/// works, and what we should test next. Both open the feedback sheet from this page, so
/// every door onto it has them.
struct BetaView: View {
    @Environment(\.dismiss) private var dismiss

    #if BETA
    @State private var howItWorks = 0
    @State private var whatNext = 0
    #endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(BetaGuide.community)
                }

                #if BETA
                // The tester's two questions, first for the reason the release puts its
                // join step first: they are what he can act on. The first opens the sheet
                // at the beta features' works / has a problem ticks, the second at the idea
                // line.
                Section {
                    Button { howItWorks += 1 } label: {
                        Label(BetaGuide.tellHowItWorks, systemImage: "envelope")
                            .font(.callout.weight(.semibold))
                    }
                    Button { whatNext += 1 } label: {
                        Label(BetaGuide.whatNext, systemImage: "lightbulb")
                            .font(.callout.weight(.semibold))
                    }
                }
                #endif

                #if !BETA
                // The one thing on the page a rider can act on today, so it comes first
                // and it is a prominent button rather than a line of blue text.
                Section {
                    Link(destination: AppChannel.testFlight) {
                        Label(BetaGuide.joinButton, systemImage: "arrow.up.forward.app")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 4, leading: 0, bottom: 4, trailing: 0))
                    ForEach(BetaGuide.howToJoin, id: \.self) { line in
                        Text(line).font(.callout)
                    }
                } header: {
                    Text(BetaGuide.howToJoinTitle)
                }
                #endif

                Section {
                    ForEach(ChannelFeatures.beta, id: \.self) { feature in
                        Label {
                            Text(feature).font(.callout)
                        } icon: {
                            Image(systemName: "testtube.2")
                                .foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text(BetaGuide.inItNowTitle)
                }

            }
            .readableColumn()
            .navigationTitle(BetaGuide.title(for: AppChannel.channel))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if BETA
            .feedbackMail(on: $howItWorks)
            .feedbackMail(on: $whatNext, focusIdea: true)
            #endif
        }
    }
}

import SwiftUI
import WingFoilKit

/// **The Beta page** — what the beta is, what is in it now, how to join, how to tell us.
///
/// New on 25 September 2026 (Jan's plan of 24 September, section 5). Three doors open it:
/// the menu's last row, the footer of *What CleanJibe does*, and the Apple Watch app's card
/// in that page's family section. Every sentence is the kit's (`BetaGuide`), and the list
/// is `ChannelFeatures.beta`, the one docs/channels.md is written into.
///
/// **Gated per docs/channels.md.** The release asks the rider in and carries the public
/// TestFlight link (`AppChannel.testFlight`); the beta and the dev build are titled "You
/// are in the beta" and have no join step, because the link would point the reader at the
/// build he is holding.
struct BetaView: View {
    @Environment(\.dismiss) private var dismiss
    /// Handed down by whichever screen owns the feedback composer; nil elsewhere, and then
    /// the button is simply not drawn.
    @Environment(\.sendFeedback) private var sendFeedback

    var body: some View {
        NavigationStack {
            List {
                Section {
                    #if BETA
                    Text(BetaGuide.insideLede)
                    #else
                    Text(BetaGuide.whatItIs)
                    #endif
                }

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

                Section {
                    ForEach(BetaGuide.feedback, id: \.self) { line in
                        Text(line).font(.callout)
                    }
                    if let sendFeedback {
                        Button {
                            sendFeedback()
                        } label: {
                            Label(BetaGuide.feedbackButton, systemImage: "envelope")
                                .font(.callout.weight(.semibold))
                        }
                    }
                } header: {
                    Text(BetaGuide.feedbackTitle)
                } footer: {
                    Text(FeedbackInvitation.community)
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
        }
    }
}

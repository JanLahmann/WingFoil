import SwiftUI
import WingFoilKit

/// Spot + gear pickers shared by Records and Trends. Both are menus rather than segmented
/// controls because the lists grow with the library and neither has a sensible cap.
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    @Environment(SessionStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            menu(title: spotTitle, symbol: "mappin.and.ellipse", active: filter.spotId != nil) {
                Button("All spots") { filter.spotId = nil }
                Divider()
                ForEach(store.spots) { entry in
                    Button {
                        filter.spotId = entry.spot.id
                    } label: {
                        Text("\(entry.spot.name) (\(entry.sessions))")
                    }
                }
            }
            menu(title: gearTitle, symbol: "bag", active: filter.gearId != nil) {
                Button("All gear") { filter.gearId = nil }
                ForEach(GearKind.allCases) { kind in
                    let items = store.gearAggregates.filter {
                        $0.gear.gearKind == kind && $0.gear.active
                    }
                    if !items.isEmpty {
                        Section(kind.label) {
                            ForEach(items) { entry in
                                Button {
                                    filter.gearId = entry.gear.id
                                } label: {
                                    Text("\(entry.gear.name) (\(entry.sessions))")
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if !filter.isEmpty {
                Button("Clear") { filter = LibraryFilter(since: filter.since) }
                    .font(.footnote)
            }
        }
        .font(.footnote)
    }

    private var spotTitle: String {
        store.spots.first { $0.spot.id == filter.spotId }?.spot.name ?? "All spots"
    }

    private var gearTitle: String {
        store.gearAggregates.first { $0.gear.id == filter.gearId }?.gear.name ?? "All gear"
    }

    private func menu(title: String, symbol: String, active: Bool,
                      @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).imageScale(.small)
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: .capsule)
            .foregroundStyle(active ? Color.accentColor : .primary)
        }
    }
}

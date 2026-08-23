import SwiftUI

/// Home. The map fills the screen; everything else floats over it.
struct WorldMapScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    @State private var focusedContinent: Continent?
    @State private var activeSheet: ActiveSheet?

    /// Both sheets go through one modifier on purpose: two `.sheet`s attached to the same
    /// view silently leave one of them unable to present.
    private enum ActiveSheet: Identifiable {
        case countryDetail(Country)
        case addVisit

        var id: String {
            switch self {
            case .countryDetail(let country): return "country-\(country.code)"
            case .addVisit: return "add-visit"
            }
        }
    }

    private var progress: VisitProgress { visitStore.progress(for: focusedContinent) }
    private var badgeTitle: String { focusedContinent?.displayName ?? "World visited" }

    var body: some View {
        ZStack(alignment: .top) {
            map
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 12) {
                VisitedBadge(title: badgeTitle, progress: progress)
                ContinentFilterBar(selection: $focusedContinent)
            }
            .padding(.top, 8)

            addVisitButton
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .countryDetail(let country):
                CountryDetailSheet(country: country)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .addVisit:
                AddVisitView(preselectedCountry: nil)
            }
        }
    }

    @ViewBuilder
    private var map: some View {
        if let mapData = visitStore.mapData {
            CountryMapView(
                mapData: mapData,
                visitedCountryCodes: visitStore.visitedCountryCodes,
                focusedContinent: focusedContinent,
                onSelectCountry: { activeSheet = .countryDetail($0) }
            )
        } else {
            ZStack {
                Color(.secondarySystemBackground)
                if let mapDataError = visitStore.mapDataError {
                    ContentUnavailableView(
                        "Map data unavailable",
                        systemImage: "globe.badge.chevron.backward",
                        description: Text(mapDataError)
                    )
                } else {
                    ProgressView("Loading the world…")
                }
            }
        }
    }

    /// The floating + — the whole point is that logging a visit is never buried.
    private var addVisitButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    activeSheet = .addVisit
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(AppTheme.accent, in: .circle)
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
                .accessibilityLabel("Add a visit")
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

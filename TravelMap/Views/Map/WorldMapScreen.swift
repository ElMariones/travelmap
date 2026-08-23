import SwiftUI

/// Home. The map fills the screen; every control floats above it in glass.
struct WorldMapScreen: View {
    @Environment(SessionStore.self) private var session
    @Environment(VisitStore.self) private var visitStore

    @State private var focusedContinent: Continent?
    @State private var activeSheet: ActiveSheet?

    /// Source for the zoom transition out of the add-visit button.
    @Namespace private var zoom

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

            // Badge and chips share a container so they sample the map together and read
            // as one floating cluster rather than two unrelated pills.
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 12) {
                    VisitedBadge(title: badgeTitle, progress: progress)
                    ContinentFilterBar(selection: $focusedContinent)
                }
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
                    // Grows out of the + rather than sliding up from nowhere. Zoom
                    // transitions stay interruptible: a drag partway through the dismiss
                    // hands the view back instead of finishing the animation first.
                    .navigationTransition(.zoom(sourceID: "add-visit", in: zoom))
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

    /// The floating primary action — logging a visit is never buried.
    ///
    /// It deliberately sits *inside* the safe area. The tab bar below is already system
    /// glass, and letting this overlap it would stack glass on glass.
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
                        .frame(width: 60, height: 60)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(AppTheme.accent)
                .matchedTransitionSource(id: "add-visit", in: zoom)
                .accessibilityLabel("Add a visit")
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
        }
    }
}

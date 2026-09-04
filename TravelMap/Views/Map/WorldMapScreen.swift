import SwiftUI

/// Home. The map fills the screen; every control floats above it in glass.
struct WorldMapScreen: View {
    @Environment(VisitStore.self) private var visitStore
    @Environment(Haptics.self) private var haptics

    @State private var focusedContinent: Continent?
    @State private var activeSheet: ActiveSheet?

    /// Source for the zoom transition out of the add-visit button.
    @Namespace private var zoom

    /// Both sheets go through one modifier on purpose: two `.sheet`s attached to the same
    /// view silently leave one of them unable to present.
    private enum ActiveSheet: Identifiable {
        case countryDetail(Country)
        case addVisit
        case browse

        var id: String {
            switch self {
            case .countryDetail(let country): return "country-\(country.code)"
            case .addVisit: return "add-visit"
            case .browse: return "browse"
            }
        }
    }

    private var progress: VisitProgress { visitStore.progress(for: focusedContinent) }
    private var badgeTitle: String { focusedContinent?.displayName ?? "World visited" }

    var body: some View {
        ZStack(alignment: .top) {
            // All edges, not just the bottom: a notch or Dynamic Island leaves the
            // status-bar strip unpainted otherwise, which reads as a broken map.
            map
                .ignoresSafeArea()

            // Badge and chips share a container so they sample the map together and read
            // as one floating cluster rather than two unrelated pills.
            GlassEffectContainer(spacing: 14) {
                VStack(spacing: 12) {
                    VisitedBadge(title: badgeTitle, progress: progress)
                    ContinentFilterBar(selection: $focusedContinent)
                }
            }
            .padding(.top, 8)

            actionButtons
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
            case .browse:
                CountryBrowserSheet()
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
            // A `MKMapView` full of overlays is one opaque blob to VoiceOver: there is
            // nothing to swipe to and nothing to hear. Rather than fake 236 elements over
            // a view that can't focus them, the map states what it shows and the country
            // browser beside it is the accessible route into any of it.
            .accessibilityElement()
            .accessibilityLabel("World map")
            .accessibilityValue(
                "\(progress.visited) of \(progress.total) countries in \(badgeTitle.lowercased()) filled in"
            )
            .accessibilityHint("Use the browse countries button to open a country")
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
            .ignoresSafeArea()
        }
    }

    /// The floating actions — logging a visit is never buried, and neither is finding a
    /// country without hunting for it on the map.
    ///
    /// They deliberately sit *inside* the safe area. The tab bar below is already system
    /// glass, and letting these overlap it would stack glass on glass.
    private var actionButtons: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Spacer()

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        Button {
                            haptics.fire(.selection)
                            activeSheet = .browse
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title3.weight(.semibold))
                                .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Browse countries")

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
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 12)
            }
        }
    }
}

/// A searchable way into any country, without having to find it on the map.
///
/// It exists for three reasons at once: pinching around for Liechtenstein is miserable,
/// VoiceOver cannot target a polygon at all, and the picker that powers it was already
/// written for the add-visit flow.
///
/// Selecting a country *pushes* the detail rather than swapping the sheet underneath it.
/// Dismissing one sheet to present another in the same frame drops the second one often
/// enough to be a bug report.
struct CountryBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Country?

    var body: some View {
        NavigationStack {
            CountryPickerList(onSelect: { selected = $0 })
                .navigationTitle("Countries")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $selected) { country in
                    CountryDetailContent(country: country)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
